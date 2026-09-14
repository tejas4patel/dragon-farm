"""Held-out loss and sample generations. Shared by train.py and evaluate.py."""

import json
import math

import torch

from .data import IGNORE_INDEX, PadCollator, render_prompt


@torch.no_grad()
def eval_loss(model, dataset, pad_token_id, device, batch_size=4):
    """Mean token-level cross-entropy over the assistant tokens."""
    collate = PadCollator(pad_token_id)
    total_loss, total_tokens = 0.0, 0
    model.eval()
    for i in range(0, len(dataset), batch_size):
        batch = collate([dataset[j] for j in range(i, min(i + batch_size, len(dataset)))])
        batch = {k: v.to(device) for k, v in batch.items()}
        out = model(input_ids=batch["input_ids"], attention_mask=batch["attention_mask"])
        logits = out.logits[:, :-1, :].float()
        labels = batch["labels"][:, 1:]
        loss = torch.nn.functional.cross_entropy(
            logits.reshape(-1, logits.size(-1)), labels.reshape(-1),
            ignore_index=IGNORE_INDEX, reduction="sum",
        )
        n = int((labels != IGNORE_INDEX).sum())
        total_loss += float(loss)
        total_tokens += n
    if total_tokens == 0:
        return None
    mean = total_loss / total_tokens
    return {"eval_loss": mean, "perplexity": math.exp(min(mean, 50)), "eval_tokens": total_tokens}


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
