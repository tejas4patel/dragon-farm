"""Pick the compute device and dtype for a run."""

from dataclasses import dataclass


@dataclass
class Hardware:
    device: object          # torch.device
    device_str: str         # "cuda:0", "mps", "cpu"
    kind: str               # "cuda", "mps", "cpu"
    dtype: object           # torch.dtype
    dtype_name: str
    bf16: bool
    fp16: bool
    device_name: str
    vram_gb: float


def describe():
    """Facts about the machine, used by dragon_check()."""
    import torch

    info = {
        "torch": torch.__version__,
        "cuda_available": torch.cuda.is_available(),
        "mps_available": bool(getattr(torch.backends, "mps", None) and torch.backends.mps.is_available()),
        "device": "cpu",
        "device_name": "CPU",
        "vram_gb": 0.0,
        "bf16": False,
    }
    if info["cuda_available"]:
        info["device"] = "cuda"
        info["device_name"] = torch.cuda.get_device_name(0)
        info["vram_gb"] = torch.cuda.get_device_properties(0).total_memory / 1024**3
        info["bf16"] = bool(torch.cuda.is_bf16_supported())
        info["cuda_version"] = torch.version.cuda
    elif info["mps_available"]:
        info["device"] = "mps"
        info["device_name"] = "Apple MPS"
    return info


def resolve(cfg: dict) -> Hardware:
    """Resolve the ``hardware`` block of config.json into concrete choices."""
    import torch

    want = (cfg or {}).get("device", "auto")
    dtype_want = (cfg or {}).get("dtype", "auto")

    cuda_ok = torch.cuda.is_available()
    mps_ok = bool(getattr(torch.backends, "mps", None) and torch.backends.mps.is_available())

    if want == "auto":
        kind = "cuda" if cuda_ok else "mps" if mps_ok else "cpu"
    elif want == "cuda":
        if not cuda_ok:
            raise RuntimeError("device='cuda' requested but torch.cuda.is_available() is False")
        kind = "cuda"
    elif want == "mps":
        if not mps_ok:
            raise RuntimeError("device='mps' requested but MPS is not available")
        kind = "mps"
    else:
        kind = "cpu"

    if kind == "cuda":
        device = torch.device("cuda:0")
        device_name = torch.cuda.get_device_name(0)
        vram = torch.cuda.get_device_properties(0).total_memory / 1024**3
        bf16_supported = bool(torch.cuda.is_bf16_supported())
    elif kind == "mps":
        device = torch.device("mps")
        device_name = "Apple MPS"
        vram = 0.0
        bf16_supported = False
    else:
        device = torch.device("cpu")
        device_name = "CPU"
        vram = 0.0
        bf16_supported = False

    if dtype_want == "auto":
        if kind == "cuda":
            dtype_name = "bfloat16" if bf16_supported else "float16"
        else:
            dtype_name = "float32"
    else:
        dtype_name = dtype_want

    dtype = {"bfloat16": torch.bfloat16, "float16": torch.float16, "float32": torch.float32}[dtype_name]
    return Hardware(
        device=device,
        device_str=str(device),
        kind=kind,
        dtype=dtype,
        dtype_name=dtype_name,
        bf16=(dtype_name == "bfloat16"),
        fp16=(dtype_name == "float16"),
        device_name=device_name,
        vram_gb=vram,
    )
