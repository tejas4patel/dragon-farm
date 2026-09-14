"""Entry point: python -m dragonfarm.evaluate --run-dir <dir> [--n-samples N]

Recomputes held-out loss and sample generations for a finished run using the
saved adapter, writing eval.json and samples.json.
"""

import argparse
import json
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--n-samples", type=int, default=10)
    a = ap.parse_args()
    run_dir = Path(a.run_dir).resolve()
    with open(run_dir / "config.json", encoding="utf-8") as f:
        cfg = json.load(f)

    from .data import load_split
    from .evaluate_utils import eval_loss, sample_generations, write_eval_files
    from .hardware import resolve
    from .loading import load_for_inference, load_tokenizer

    adapter = run_dir / "adapter"
    if not adapter.exists():
        raise SystemExit("no adapter directory in this run; training did not finish")
    hw = resolve(cfg.get("hardware"))
    m = cfg["model"]
    tok = load_tokenizer(m["id"], m.get("revision"), m.get("trust_remote_code", False))
    model = load_for_inference(m["id"], hw, adapter=adapter, revision=m.get("revision"),
                               trust_remote_code=m.get("trust_remote_code", False))

    metrics, samples = None, []
    if cfg["data"].get("eval"):
        eval_ds, records = load_split(run_dir / cfg["data"]["eval"], tok, int(cfg["train"]["max_seq_len"]))
        if len(eval_ds):
            metrics = eval_loss(model, eval_ds, tok.pad_token_id, hw.device)
            samples = sample_generations(model, tok, records, hw.device, n=a.n_samples)
    write_eval_files(run_dir, metrics, samples)
    print(json.dumps({"metrics": metrics, "n_samples": len(samples)}))


if __name__ == "__main__":
    main()
