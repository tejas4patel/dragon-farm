import json
import tempfile
import zipfile
from pathlib import Path

from dragonfarm.pack_results import MANIFEST, pack


def _fake_run(root: Path) -> Path:
    run = root / "20260914-101500-smollm2"
    (run / "adapter").mkdir(parents=True)
    (run / "checkpoints" / "checkpoint-10").mkdir(parents=True)
    (run / "config.json").write_text(json.dumps({"run_id": run.name}), encoding="utf-8")
    (run / "status.json").write_text(json.dumps({"state": "succeeded", "device_name": "Tesla T4"}), encoding="utf-8")
    (run / "progress.jsonl").write_text('{"step":1,"loss":2.0}\n', encoding="utf-8")
    (run / "log.txt").write_text("hello\n", encoding="utf-8")
    (run / "adapter" / "adapter_config.json").write_text("{}", encoding="utf-8")
    (run / "adapter" / "adapter_model.safetensors").write_bytes(b"\x00" * 16)
    (run / "checkpoints" / "checkpoint-10" / "big.bin").write_bytes(b"\x00" * 16)
    return run


def test_pack_writes_manifest_outputs_and_adapter_but_not_checkpoints():
    with tempfile.TemporaryDirectory() as tmp:
        run = _fake_run(Path(tmp))
        out = pack(run, Path(tmp) / "out")
        assert out.name == f"dragonfarm-results-{run.name}.zip"
        with zipfile.ZipFile(out) as z:
            names = set(z.namelist())
            manifest = json.loads(z.read(MANIFEST))
        assert {MANIFEST, "status.json", "progress.jsonl", "log.txt",
                "adapter/adapter_config.json", "adapter/adapter_model.safetensors"} <= names
        assert not any(n.startswith("checkpoints") for n in names)
        assert "eval.json" not in names  # absent in the fake run, so not packed
        assert manifest["run_id"] == run.name
        assert manifest["state"] == "succeeded"
        assert manifest["device"] == "Tesla T4"


def test_pack_defaults_to_cwd_and_tolerates_missing_status():
    import os

    with tempfile.TemporaryDirectory() as tmp:
        run = _fake_run(Path(tmp))
        (run / "status.json").unlink()
        cwd = os.getcwd()
        os.chdir(tmp)
        try:
            out = pack(run)
        finally:
            os.chdir(cwd)
        assert out.parent == Path(tmp).resolve()
        with zipfile.ZipFile(out) as z:
            assert json.loads(z.read(MANIFEST))["state"] is None
