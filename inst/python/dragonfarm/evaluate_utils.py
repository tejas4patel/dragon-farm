"""Held-out loss and sample generations. Shared by train.py and evaluate.py."""

import gc
import json
import math

import torch
import torch.nn.functional as F

from .data import IGNORE_INDEX, PadCollator, render_prompt

# Positions scored per lm_head call. 256 positions x a 150k vocabulary in
# float32 is about 150 MB per row, against several GB for a whole sequence.
LOSS_CHUNK = 256


def _decoder_and_head(model):
    """The transformer body and the output projection, or (None, None).

    Scoring the hidden states chunk by chunk through lm_head avoids ever
    holding the full [batch, seq, vocab] logits tensor, which is what runs an
    8 GB GPU out of memory at long sequence lengths. Models with logit
    soft-capping (Gemma 2) apply it after lm_head, so they take the full path.
    """
    base = model.get_base_model() if hasattr(model, "get_base_model") else model
    cfg = getattr(base, "config", None)
    if getattr(cfg, "final_logit_softcapping", None):
        return None, None
    try:
        dec = base.get_decoder()
        head = base.get_output_embeddings()
    except Exception:
        return None, None
    if dec is None or head is None:
        return None, None
    return dec, head


@torch.no_grad()
def token_loss_sum(model, input_ids, attention_mask, labels, chunk=LOSS_CHUNK):
    """Summed cross-entropy over the labelled (assistant) tokens of a batch."""
    labels = labels[:, 1:]
    dec, head = _decoder_and_head(model)
    total = torch.zeros((), dtype=torch.float32, device=input_ids.device)
    if dec is not None:
        hidden = dec(input_ids=input_ids, attention_mask=attention_mask).last_hidden_state[:, :-1]
        for s in range(0, hidden.size(1), chunk):
            lab = labels[:, s:s + chunk]
            if not bool((lab != IGNORE_INDEX).any()):
                continue
            logits = head(hidden[:, s:s + chunk]).float()
            total += F.cross_entropy(logits.reshape(-1, logits.size(-1)), lab.reshape(-1),
                                     ignore_index=IGNORE_INDEX, reduction="sum")
        return total
    logits_all = model(input_ids=input_ids, attention_mask=attention_mask).logits[:, :-1]
    for s in range(0, logits_all.size(1), chunk):
        logits = logits_all[:, s:s + chunk].float()
        total += F.cross_entropy(logits.reshape(-1, logits.size(-1)), labels[:, s:s + chunk].reshape(-1),
                                 ignore_index=IGNORE_INDEX, reduction="sum")
    return total


def free_gpu_memory():
    gc.collect()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()


def is_oom(err):
    return isinstance(err, torch.cuda.OutOfMemoryError) or "out of memory" in str(err).lower()


@torch.no_grad()
def eval_loss(model, dataset, pad_token_id, device, batch_size=1):
    """Mean token-level cross-entropy over the assistant tokens.

    Falls back to one row at a time if a batch runs out of GPU memory.
    """
    collate = PadCollator(pad_token_id)
    total_loss, total_tokens = 0.0, 0
    model.eval()

    def score(rows):
        batch = collate(rows)
        batch = {k: v.to(device) for k, v in batch.items()}
        loss = token_loss_sum(model, batch["input_ids"], batch["attention_mask"], batch["labels"])
        n = int((batch["labels"][:, 1:] != IGNORE_INDEX).sum())
        return float(loss), n

    i = 0
    while i < len(dataset):
        rows = [dataset[j] for j in range(i, min(i + batch_size, len(dataset)))]
        try:
            loss, n = score(rows)
        except Exception as e:  # noqa: BLE001 - only OOM is handled, anything else is re-raised
            if not is_oom(e) or len(rows) == 1:
                raise
            print(f"[dragonfarm] evaluation batch of {len(rows)} ran out of memory; retrying one row at a time",
                  flush=True)
            free_gpu_memory()
            batch_size = 1
            continue
        total_loss += loss
        total_tokens += n
        i += len(rows)
    if total_tokens == 0:
        return None
    mean = total_loss / total_tokens
    return {"eval_loss": mean, "perplexity": math.exp(min(mean, 50)), "eval_tokens": total_tokens}


def evaluate_or_warn(status, label, fn):
    """Run an end-of-training evaluation; on GPU out-of-memory, record a warning instead of failing the run.

    By this point the adapter is saved and training has succeeded, so a run
    should not be marked failed because the GPU could not also fit the
    evaluation.
    """
    try:
        return fn()
    except Exception as e:  # noqa: BLE001
        if not is_oom(e):
            raise
        msg = (f"{label} skipped: the GPU ran out of memory after training finished. "
               "The adapter is saved. Lower max_seq_len or eval_batch_size, or run dragon_evaluate() on a freer GPU.")
        print(f"[dragonfarm] {msg}", flush=True)
        status.update(eval_warning=msg)
        free_gpu_memory()
        return None


@torch.no_grad()
def generate_reply(model, tok, messages, device, max_new_tokens=256, temperature=0.7, top_p=0.9):
    text = render_prompt(tok, messages)
    enc = tok(text, return_tensors="pt", add_special_tokens=False).to(device)
    kwargs = dict(max_new_tokens=max_new_tokens, pad_token_id=tok.pad_token_id)
    if temperature and temperature > 0:
        kwargs.update(do_sample=True, temperature=float(temperature), top_p=float(top_p))
    else:
        kwargs.update(do_sample=False)
    out = model.generate(**enc, **kwargs)
    new_tokens = out[0, enc["input_ids"].shape[1]:]
    return tok.decode(new_tokens, skip_special_tokens=True).strip()


def sample_generations(model, tok, records, device, n=10, max_new_tokens=200):
    samples = []
    for rec in records[:n]:
        messages = rec["messages"]
        prompt_msgs = messages[:-1]
        user = next((m["content"] for m in prompt_msgs if m["role"] == "user"), "")
        generated = generate_reply(model, tok, prompt_msgs, device, max_new_tokens=max_new_tokens, temperature=0.0)
        samples.append({"prompt": user, "reference": messages[-1]["content"], "generated": generated})
    return samples


def write_eval_files(run_dir, metrics, samples):
    with open(run_dir / "eval.json", "w", encoding="utf-8") as f:
        json.dump(metrics or {}, f, indent=2)
    with open(run_dir / "samples.json", "w", encoding="utf-8") as f:
        json.dump(samples, f, indent=2, ensure_ascii=False)
