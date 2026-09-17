import json
import tempfile
from pathlib import Path

from dragonfarm.api import Run, runs


def _write_run(base, name, config, status=None, progress=None, log=None):
    d = base / name
    d.mkdir(parents=True)
    (d / "config.json").write_text(json.dumps(config), encoding="utf-8")
    if status is not None:
        (d / "status.json").write_text(json.dumps(status), encoding="utf-8")
    if progress is not None:
        (d / "progress.jsonl").write_text("\n".join(json.dumps(r) for r in progress) + "\n", encoding="utf-8")
    if log is not None:
        (d / "log.txt").write_text(log, encoding="utf-8")
    return d


def test_run_reads_config_status_progress_and_log():
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        d = _write_run(
            base, "20260101-000000-demo",
            {"stage": "sft", "created_at": "2026-01-01T00:00:00Z"},
            status={"state": "succeeded"},
            progress=[{"step": 1, "loss": 2.0}, {"step": 2, "loss": 1.5}],
            log="line1\nline2\nline3\n",
        )
        run = Run(d)
        assert run.id == "20260101-000000-demo"
        assert run.stage == "sft"
        assert run.state == "succeeded"
        assert run.config["created_at"] == "2026-01-01T00:00:00Z"
        assert run.progress() == [{"step": 1, "loss": 2.0}, {"step": 2, "loss": 1.5}]
        assert run.log() == ["line1", "line2", "line3"]
        assert run.log(tail=2) == ["line2", "line3"]
        assert "20260101-000000-demo" in repr(run)


def test_run_defaults_when_optional_files_are_missing():
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp) / "run"
        d.mkdir()
        (d / "config.json").write_text("{}", encoding="utf-8")
        run = Run(d)
        assert run.stage == "sft"      # default when config.json has no "stage"
        assert run.state == "queued"  # Status.read() defaults to queued when status.json does not exist
        assert run.progress() == []
        assert run.log() == []
        assert run.adapter_dir is None
        assert run.merged_dir is None


def test_run_reports_adapter_and_merged_directories_once_they_exist():
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp) / "run"
        (d / "adapter").mkdir(parents=True)
        (d / "merged").mkdir(parents=True)
        (d / "config.json").write_text("{}", encoding="utf-8")
        (d / "adapter" / "adapter_config.json").write_text("{}", encoding="utf-8")
        (d / "merged" / "config.json").write_text("{}", encoding="utf-8")
        run = Run(d)
        assert run.adapter_dir == d / "adapter"
        assert run.merged_dir == d / "merged"


def test_run_requires_a_config_json():
    with tempfile.TemporaryDirectory() as tmp:
        try:
            Run(Path(tmp) / "nope")
        except FileNotFoundError:
            pass
        else:
            raise AssertionError("expected FileNotFoundError")


def test_runs_lists_by_created_at_newest_first_and_skips_non_run_directories():
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        _write_run(base, "old", {"created_at": "2026-01-01T00:00:00Z"})
        _write_run(base, "new", {"created_at": "2026-06-01T00:00:00Z"})
        (base / "not-a-run").mkdir()
        found = runs(base)
        assert [r.id for r in found] == ["new", "old"]
        assert runs(base / "missing") == []
