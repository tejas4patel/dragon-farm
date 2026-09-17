"""A minimal, dependency-light Python view of a dragonfarm run directory.

This mirrors the read side of the R package's ``dragon_run()``,
``dragon_status()``, and ``dragon_progress()``: it works on any run
directory dragonfarm has written, whether that run was started from R,
from ``dragonfarm train``, or from the app. Reading a run's config,
status, or progress needs none of torch, transformers, or peft -- those
are only imported when a stage actually trains or generates.
"""

import json
from pathlib import Path

from .status import Status


def _read_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _read_jsonl(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


class Run:
    """A run directory, e.g. ``Run("dragonfarm_runs/20260101-120000-my-model")``.

    Raises ``FileNotFoundError`` if the directory has no ``config.json``.
    """

    def __init__(self, run_dir):
        self.dir = Path(run_dir)
        self._config_path = self.dir / "config.json"
        if not self._config_path.exists():
            raise FileNotFoundError(f"{self.dir} is not a run directory (no config.json).")
        self._status = Status(self.dir)

    @property
    def id(self):
        return self.dir.name

    @property
    def config(self):
        """The run's ``config.json``: model, LoRA, and stage settings."""
        return _read_json(self._config_path)

    @property
    def status(self):
        """The run's current ``status.json``."""
        return self._status.read()

    @property
    def stage(self):
        """``"sft"``, ``"prefer"``, or ``"reinforce"``."""
        return self.config.get("stage", "sft")

    @property
    def state(self):
        """``"queued"``, ``"running"``, ``"succeeded"``, ``"failed"``, or ``"cancelled"``."""
        return self.status.get("state", "unknown")

    def progress(self):
        """Rows written during training: one per logged step (loss, eval_loss, reward, ...)."""
        path = self.dir / "progress.jsonl"
        return _read_jsonl(path) if path.exists() else []

    def log(self, tail=None):
        """The trainer's combined stdout/stderr, as a list of lines.

        @param tail Keep only the last this many lines; ``None`` for all of it.
        """
        path = self.dir / "log.txt"
        if not path.exists():
            return []
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        return lines[-tail:] if tail else lines

    @property
    def adapter_dir(self):
        """The trained LoRA adapter's directory, or ``None`` if there isn't one yet."""
        d = self.dir / "adapter"
        return d if (d / "adapter_config.json").exists() else None

    @property
    def merged_dir(self):
        """The merged, standalone model's directory, or ``None`` if it hasn't been merged."""
        d = self.dir / "merged"
        return d if (d / "config.json").exists() else None

    def __repr__(self):
        return f"Run({self.id!r}, stage={self.stage!r}, state={self.state!r})"


def runs(runs_dir):
    """Every run directory under ``runs_dir`` that has a config.json, newest first."""
    base = Path(runs_dir)
    if not base.exists():
        return []
    found = [Run(p) for p in base.iterdir() if p.is_dir() and (p / "config.json").exists()]
    return sorted(found, key=lambda r: r.config.get("created_at") or "", reverse=True)
