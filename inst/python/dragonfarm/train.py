"""Entry point: python -m dragonfarm.train --run-dir <dir> [--resume]"""

import argparse
import json
import os
import signal
import sys
import traceback
from pathlib import Path

from .status import Status, now_iso

# Installed before torch is imported. A console Ctrl+C reaching this process
# while it is still loading would otherwise kill it silently. When R manages
# the run (DRAGONFARM_MANAGED=1) cancellation goes through cancel.request, so
# console signals are logged and ignored for the whole run; see callbacks.py.
_MANAGED = os.environ.get("DRAGONFARM_MANAGED") == "1"


def _startup_signal(signum, frame):
    print(f"[dragonfarm] received signal {signum} during startup; ignoring", flush=True)


for _sig in (signal.SIGINT, signal.SIGTERM):
    try:
        signal.signal(_sig, _startup_signal)
    except (ValueError, OSError):
        pass


def latest_checkpoint(run_dir: Path):
    ck = run_dir / "checkpoints"
    if not ck.exists():
        return None
    cands = [p for p in ck.iterdir() if p.is_dir() and p.name.startswith("checkpoint-")]
    if not cands:
        return None
    return max(cands, key=lambda p: int(p.name.split("-")[-1]))


def train(run_dir: Path, status: Status, resume: bool) -> str:
    with open(run_dir / "config.json", encoding="utf-8") as f:
        cfg = json.load(f)

    import torch
    from transformers import Trainer, TrainingArguments
    from peft import LoraConfig, get_peft_model

    from .callbacks import CancelFlag, ProgressCallback
    from .data import PadCollator, load_split
    from .evaluate_utils import eval_loss, sample_generations, write_eval_files
    from .hardware import resolve
    from .loading import load_base_model, load_tokenizer

    cancel = CancelFlag(run_dir)
    hw = resolve(cfg.get("hardware"))
    status.update(device=hw.device_str, dtype=hw.dtype_name, device_name=hw.device_name)
    print(f"[dragonfarm] device={hw.device_str} dtype={hw.dtype_name} ({hw.device_name})", flush=True)

    m = cfg["model"]
    tok = load_tokenizer(m["id"], m.get("revision"), m.get("trust_remote_code", False))
    print(f"[dragonfarm] loading {m['id']}", flush=True)
    model = load_base_model(
        m["id"], hw, revision=m.get("revision"),
        trust_remote_code=m.get("trust_remote_code", False),
        load_in_4bit=cfg["hardware"].get("load_in_4bit", False),
    )

    t = cfg["train"]
    if cfg["hardware"].get("load_in_4bit", False):
        from peft import prepare_model_for_kbit_training

        model = prepare_model_for_kbit_training(model, use_gradient_checkpointing=t.get("gradient_checkpointing", False))
    elif t.get("gradient_checkpointing", False):
        model.gradient_checkpointing_enable()
        model.enable_input_require_grads()

    lo = cfg["lora"]
    targets = lo.get("target_modules", "auto")
    lora_cfg = LoraConfig(
        r=int(lo["r"]),
        lora_alpha=float(lo["alpha"]),
        lora_dropout=float(lo["dropout"]),
        target_modules="all-linear" if targets == "auto" else list(targets),
        bias="none",
        task_type="CAUSAL_LM",
    )
    model = get_peft_model(model, lora_cfg)
    # Keep trainable weights in fp32 so fp16/bf16 autocast can scale gradients.
    for p in model.parameters():
        if p.requires_grad and p.dtype != torch.float32:
            p.data = p.data.float()
    trainable, total = model.get_nb_trainable_parameters()
    status.update(trainable_params=int(trainable), total_params=int(total))
    print(f"[dragonfarm] trainable params {trainable:,} of {total:,}", flush=True)

    max_len = int(t["max_seq_len"])
    train_ds, _ = load_split(run_dir / cfg["data"]["train"], tok, max_len)
    if len(train_ds) == 0:
        raise RuntimeError("no trainable examples after tokenization; check the column mapping and max_seq_len")
    if train_ds.skipped:
        print(f"[dragonfarm] skipped {train_ds.skipped} example(s) whose response was truncated away", flush=True)
    eval_ds, eval_records = (None, [])
    if cfg["data"].get("eval"):
        eval_ds, eval_records = load_split(run_dir / cfg["data"]["eval"], tok, max_len)
        if len(eval_ds) == 0:
            eval_ds = None

    extra = dict(t.get("extra") or {})
    import inspect

    ta_params = set(inspect.signature(TrainingArguments.__init__).parameters)
    warmup_ratio = float(t.get("warmup_ratio", 0.03))
    if "warmup_ratio" in ta_params:
        warmup_kwargs = {"warmup_ratio": warmup_ratio}
    else:
        # transformers >= 5: warmup_steps takes a fraction when below 1.
        warmup_kwargs = {"warmup_steps": warmup_ratio}
    targs_kwargs = dict(
        output_dir=str(run_dir / "checkpoints"),
        num_train_epochs=float(t["epochs"]),
        max_steps=int(t["max_steps"]) if t.get("max_steps") else -1,
        learning_rate=float(t["learning_rate"]),
        per_device_train_batch_size=int(t["per_device_batch_size"]),
        per_device_eval_batch_size=int(t["per_device_batch_size"]),
        gradient_accumulation_steps=int(t["gradient_accumulation"]),
        weight_decay=float(t.get("weight_decay", 0.0)),
        lr_scheduler_type="cosine",
        logging_steps=int(t["logging_steps"]),
        logging_first_step=True,
        save_strategy="steps",
        save_steps=int(t["save_steps"]),
        save_total_limit=2,
        eval_strategy="epoch" if eval_ds is not None else "no",
        bf16=hw.bf16,
        fp16=hw.fp16,
        seed=int(t.get("seed", 42)),
        report_to=[],
        disable_tqdm=True,
        remove_unused_columns=False,
        dataloader_pin_memory=(hw.kind == "cuda"),
        use_cpu=(hw.kind == "cpu"),
        gradient_checkpointing=bool(t.get("gradient_checkpointing", False)),
    )
    targs_kwargs.update(warmup_kwargs)
    targs_kwargs.update(extra)
    unknown = [k for k in targs_kwargs if k not in ta_params]
    if unknown:
        raise TypeError(f"TrainingArguments does not accept {unknown} in this transformers version")
    targs = TrainingArguments(**targs_kwargs)

    trainer_kwargs = dict(
        model=model, args=targs, train_dataset=train_ds, eval_dataset=eval_ds,
        data_collator=PadCollator(tok.pad_token_id),
        callbacks=[ProgressCallback(run_dir, status, cancel)],
    )
    try:
        trainer = Trainer(processing_class=tok, **trainer_kwargs)
    except TypeError:
        trainer = Trainer(tokenizer=tok, **trainer_kwargs)

    resume_from = str(latest_checkpoint(run_dir)) if resume else None
    if resume and resume_from is None:
        print("[dragonfarm] no checkpoint found, starting from scratch", flush=True)
    print(f"[dragonfarm] training {len(train_ds)} examples"
          + (f", evaluating on {len(eval_ds)}" if eval_ds is not None else ""), flush=True)
    trainer.train(resume_from_checkpoint=resume_from)

    adapter_dir = run_dir / "adapter"
    model.save_pretrained(str(adapter_dir))
    tok.save_pretrained(str(adapter_dir))
    print(f"[dragonfarm] adapter saved to {adapter_dir}", flush=True)

    if cancel.check():
        return "cancelled"

    metrics, samples = None, []
    if eval_ds is not None:
        print("[dragonfarm] evaluating", flush=True)
        metrics = eval_loss(model, eval_ds, tok.pad_token_id, hw.device)
        n = int(cfg.get("eval", {}).get("n_samples", 10))
        if n > 0:
            samples = sample_generations(model, tok, eval_records, hw.device, n=n)
    write_eval_files(run_dir, metrics, samples)
    if metrics:
        status.update(eval_loss=metrics["eval_loss"], perplexity=metrics["perplexity"])
    return "succeeded"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--resume", action="store_true")
    a = ap.parse_args()
    run_dir = Path(a.run_dir).resolve()
    status = Status(run_dir)
    status.update(state="running", pid=os.getpid(), started_at=now_iso(), finished_at=None, error=None)
    try:
        result = train(run_dir, status, resume=a.resume)
        status.update(state=result, finished_at=now_iso())
        print(f"[dragonfarm] {result}", flush=True)
        sys.exit(0)
    except BaseException as e:  # noqa: BLE001 - we want SystemExit/KeyboardInterrupt too
        if isinstance(e, SystemExit) and e.code in (0, None):
            raise
        traceback.print_exc()
        status.update(state="failed", finished_at=now_iso(), error=f"{type(e).__name__}: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
