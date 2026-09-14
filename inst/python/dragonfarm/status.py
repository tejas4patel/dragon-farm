"""Atomic status.json writer shared by every entry point."""

import json
import os
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def atomic_write_json(path: Path, payload: dict, attempts: int = 20) -> None:
    """Write via a temp file and rename. On Windows the rename fails with
    PermissionError while another process (R polling the file) has it open,
    so retry briefly instead of crashing the run."""
    path = Path(path)
    fd, tmp = tempfile.mkstemp(prefix=".status-", suffix=".json", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2)
        for i in range(attempts):
            try:
                os.replace(tmp, path)
                break
            except PermissionError:
                if i == attempts - 1:
                    raise
                time.sleep(0.05 * (i + 1))
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


class Status:
    """Read-modify-write access to <run_dir>/status.json."""

    def __init__(self, run_dir):
        self.path = Path(run_dir) / "status.json"

    def read(self) -> dict:
        if not self.path.exists():
            return {"state": "queued"}
        with open(self.path, encoding="utf-8") as f:
            return json.load(f)

    def update(self, **fields) -> dict:
        current = self.read()
        current.update(fields)
        atomic_write_json(self.path, current)
        return current
