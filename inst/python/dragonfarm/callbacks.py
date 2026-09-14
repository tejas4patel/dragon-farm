"""Trainer callbacks: progress rows, checkpoints, and cooperative cancel."""

import json
import os
import signal
import time
from pathlib import Path

from transformers import TrainerCallback


class CancelFlag:
    """Set by a cancel.request file in the run directory, or by SIGINT/SIGTERM
    when the trainer is run by hand. Under R (DRAGONFARM_MANAGED=1) console
    signals are logged and ignored, because a shared console can deliver
    Ctrl+C events that have nothing to do with this run."""

    def __init__(self, run_dir):
        self.requested = False
        self.managed = os.environ.get("DRAGONFARM_MANAGED") == "1"
        self.request_file = Path(run_dir) / "cancel.request"
        for sig in (signal.SIGINT, signal.SIGTERM):
            try:
                signal.signal(sig, self._handle)
            except (ValueError, OSError):
                pass

    def _handle(self, signum, frame):
        if self.managed:
            print(f"[dragonfarm] received signal {signum}; ignoring (write cancel.request to stop)", flush=True)
            return
        self.requested = True

    def check(self) -> bool:
        if not self.requested and self.request_file.exists():
            self.requested = True
        return self.requested


class ProgressCallback(TrainerCallback):
    def __init__(self, run_dir, status, cancel: CancelFlag):
        self.run_dir = Path(run_dir)
        self.progress_path = self.run_dir / "progress.jsonl"
        self.status = status
        self.cancel = cancel
        self.t0 = time.time()

    def _append(self, row):
        with open(self.progress_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(row) + "\n")

    def on_train_begin(self, args, state, control, **kwargs):
        self.t0 = time.time()
        self.status.update(total_steps=int(state.max_steps))

    def on_log(self, args, state, control, logs=None, **kwargs):
        logs = logs or {}
        elapsed = time.time() - self.t0
        step = int(state.global_step)
        row = {"step": step, "epoch": round(float(state.epoch or 0.0), 4), "elapsed_s": round(elapsed, 1)}
        if "loss" in logs:
            row["loss"] = float(logs["loss"])
        if "eval_loss" in logs:
            row["eval_loss"] = float(logs["eval_loss"])
        if "learning_rate" in logs:
            row["lr"] = float(logs["learning_rate"])
        if "grad_norm" in logs:
            try:
                row["grad_norm"] = float(logs["grad_norm"])
            except (TypeError, ValueError):
                pass
        if state.max_steps and step > 0:
            row["eta_s"] = round(elapsed / step * (state.max_steps - step), 1)
        self._append(row)

    def on_save(self, args, state, control, **kwargs):
        ckpt = f"checkpoints/checkpoint-{state.global_step}"
        self.status.update(latest_checkpoint=ckpt)

    def on_step_end(self, args, state, control, **kwargs):
        if self.cancel.check():
            control.should_training_stop = True
            control.should_save = True
        return control
