"""Load tokenizer and model, with or without a LoRA adapter."""

from pathlib import Path


def transformers_version():
    import transformers

    parts = transformers.__version__.split(".")
    try:
        return int(parts[0]), int(parts[1])
    except (ValueError, IndexError):
        return (0, 0)


def dtype_kwargs(dtype):
    """``dtype=`` on transformers >= 4.56, ``torch_dtype=`` before that."""
    return {"dtype": dtype} if transformers_version() >= (4, 56) else {"torch_dtype": dtype}


def load_tokenizer(model_id, revision=None, trust_remote_code=False):
    from transformers import AutoTokenizer

    tok = AutoTokenizer.from_pretrained(model_id, revision=revision, trust_remote_code=trust_remote_code)
    if tok.pad_token is None:
        tok.pad_token = tok.eos_token
    tok.padding_side = "right"
    return tok


def load_base_model(model_id, hw, revision=None, trust_remote_code=False, load_in_4bit=False):
    from transformers import AutoModelForCausalLM

    kwargs = dict(revision=revision, trust_remote_code=trust_remote_code)
    if load_in_4bit:
        try:
            from transformers import BitsAndBytesConfig
            import bitsandbytes  # noqa: F401
        except Exception as e:
            raise RuntimeError(
                "load_in_4bit requires bitsandbytes, which is only available on Linux with CUDA"
            ) from e
        kwargs["quantization_config"] = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_compute_dtype=hw.dtype,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_use_double_quant=True,
        )
        kwargs["device_map"] = {"": 0}
    else:
        kwargs.update(dtype_kwargs(hw.dtype))

    model = AutoModelForCausalLM.from_pretrained(model_id, **kwargs)
    if not load_in_4bit:
        model = model.to(hw.device)
    return model


def apply_base_adapters(model, adapter_dirs):
    """Fold earlier-stage adapters into the weights, in order.

    Each adapter is applied to the result of the previous merge, which is how
    a run that continued from another run reconstructs its starting point.
    """
    from peft import PeftModel

    for d in adapter_dirs or []:
        model = PeftModel.from_pretrained(model, str(d)).merge_and_unload()
    return model


def load_for_inference(model_id, hw, adapter=None, revision=None, trust_remote_code=False, base_adapters=None):
    """Base model, earlier-stage adapters folded in, plus optional adapter, in eval mode."""
    model = load_base_model(model_id, hw, revision=revision, trust_remote_code=trust_remote_code)
    model = apply_base_adapters(model, base_adapters)
    if adapter:
        from peft import PeftModel

        model = PeftModel.from_pretrained(model, str(adapter))
    model.eval()
    return model


def adapter_base_model(adapter_dir):
    """Read the base model id recorded inside an adapter directory."""
    import json

    cfg = Path(adapter_dir) / "adapter_config.json"
    with open(cfg, encoding="utf-8") as f:
        return json.load(f)["base_model_name_or_path"]
