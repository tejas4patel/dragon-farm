"""Entry point: python -m dragonfarm.merge --adapter <dir> --out <dir> [--model id]

Folds a LoRA adapter into its base model and saves a standalone model that
loads with plain transformers.
"""

import argparse
import json
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--adapter", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--model", default=None)
    ap.add_argument("--base-adapter", action="append", default=[],
                    help="earlier-stage adapter to fold in first; repeatable, applied in order")
    ap.add_argument("--trust-remote-code", action="store_true")
    a = ap.parse_args()

    import torch
    from peft import PeftModel
    from transformers import AutoModelForCausalLM

    from .loading import adapter_base_model, apply_base_adapters, dtype_kwargs, load_tokenizer

    adapter = Path(a.adapter).resolve()
    out = Path(a.out).resolve()
    model_id = a.model or adapter_base_model(adapter)

    tok = load_tokenizer(model_id, trust_remote_code=a.trust_remote_code)
    base = AutoModelForCausalLM.from_pretrained(model_id, trust_remote_code=a.trust_remote_code, **dtype_kwargs("auto"))
    base = base.to("cpu")
    base = apply_base_adapters(base, a.base_adapter)
    merged = PeftModel.from_pretrained(base, str(adapter)).merge_and_unload()
    out.mkdir(parents=True, exist_ok=True)
    merged.save_pretrained(str(out), safe_serialization=True)
    tok.save_pretrained(str(out))
    with open(out / "dragonfarm.json", "w", encoding="utf-8") as f:
        json.dump({"base_model": model_id, "adapter": str(adapter), "base_adapters": [str(p) for p in a.base_adapter]}, f, indent=2)
    print(json.dumps({"out": str(out), "dtype": str(next(merged.parameters()).dtype)}))


if __name__ == "__main__":
    main()
