"""Zip a run's outputs for dragon_import().

Usage: python -m dragonfarm.pack_results <run_dir> [--out DIR]

Writes dragonfarm-results-<run id>.zip holding status.json, progress.jsonl,
log.txt, eval.json, samples.json, the adapter/ directory, and a small
manifest. Checkpoints are left out; they are only useful for resuming on the
machine that wrote them.
"""

import argparse
import json
import platform
import zipfile
from pathlib import Path

from .status import now_iso

FILES = ["status.json", "progress.jsonl", "log.txt", "eval.json", "samples.json"]
MANIFEST = "dragonfarm-results.json"


def pack(run_dir, out_dir=None) -> Path:
    run_dir = Path(run_dir).resolve()
    with open(run_dir / "config.json", encoding="utf-8") as f:
        cfg = json.load(f)
    run_id = cfg.get("run_id", run_dir.name)
    status = {}
    if (run_dir / "status.json").exists():
        with open(run_dir / "status.json", encoding="utf-8") as f:
            status = json.load(f)

    out_dir = Path(out_dir).resolve() if out_dir else Path.cwd()
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"dragonfarm-results-{run_id}.zip"

    manifest = {
        "format": "dragonfarm-results",
        "version": 1,
        "run_id": run_id,
        "state": status.get("state"),
        "device": status.get("device_name"),
        "packed_at": now_iso(),
        "platform": platform.platform(),
    }
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(MANIFEST, json.dumps(manifest, indent=2))
        for name in FILES:
            p = run_dir / name
            if p.exists():
                z.write(p, name)
        adapter = run_dir / "adapter"
        if adapter.is_dir():
            for p in sorted(adapter.rglob("*")):
                if p.is_file():
                    z.write(p, str(Path("adapter") / p.relative_to(adapter)))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir")
    ap.add_argument("--out", default=None)
    a = ap.parse_args(argv)
    print(pack(a.run_dir, a.out))


if __name__ == "__main__":
    main()
