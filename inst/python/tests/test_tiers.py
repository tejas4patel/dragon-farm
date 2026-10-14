"""Hardware tiers and the 4-bit decision are pure functions of a few numbers."""

from dragonfarm.hardware import TIERS, inference_tier, model_size_b, wants_4bit


def _raises(fn, needle):
    try:
        fn()
    except RuntimeError as e:
        assert needle in str(e), str(e)
        return
    raise AssertionError("expected a RuntimeError mentioning " + needle)


def test_model_size_is_read_from_the_id():
    assert model_size_b("Qwen/Qwen2.5-7B-Instruct") == 7.0
    assert model_size_b("Qwen/Qwen2.5-0.5B-Instruct") == 0.5
    assert model_size_b("HuggingFaceTB/SmolLM2-135M-Instruct") == 0.135
    assert model_size_b("meta-llama/Llama-3.2-1B-Instruct") == 1.0
    assert model_size_b("google/gemma-3-1b-it") == 1.0
    assert model_size_b("nvidia/Minitron-4B-Base") == 4.0
    assert model_size_b("models/support-merged") is None
    assert model_size_b("C:/runs/20261012-1234-qwen/adapter") is None


def test_tiers_follow_gpu_memory_and_fall_back_without_bitsandbytes():
    assert inference_tier("cpu", 0, True)["name"] == "cpu"
    assert inference_tier("mps", 0, True)["name"] == "cpu"
    assert inference_tier("cuda", 4.0, True)["name"] == "small"
    assert inference_tier("cuda", 6.0, True)["name"] == "medium"
    assert inference_tier("cuda", 8.0, True)["name"] == "large"
    assert inference_tier("cuda", 7.996, True)["name"] == "large"   # what an "8 GB" card reports
    assert inference_tier("cuda", 5.8, True)["name"] == "medium"    # and a "6 GB" one
    assert inference_tier("cuda", 7.5, True)["name"] == "medium"
    assert inference_tier("cuda", 8.0, True)["load_in_4bit"] is True
    assert inference_tier("cuda", 24.0, True)["name"] == "large"
    # the 4-bit tier needs bitsandbytes; without it the 8 GB card gets the 3B
    assert inference_tier("cuda", 8.0, False)["name"] == "medium"
    assert inference_tier("cuda", 2.0, True)["name"] == "small"   # never below the first GPU tier
    assert [t["min_vram_gb"] for t in TIERS] == sorted(t["min_vram_gb"] for t in TIERS)


def test_auto_quantizes_only_when_full_weights_would_not_fit():
    gpu8 = dict(kind="cuda", vram_gb=8.0, bnb_available=True)
    assert wants_4bit("auto", "Qwen/Qwen2.5-7B-Instruct", **gpu8) is True
    assert wants_4bit("auto", "Qwen/Qwen2.5-3B-Instruct", **gpu8) is False
    assert wants_4bit("auto", "Qwen/Qwen2.5-0.5B-Instruct", **gpu8) is False
    assert wants_4bit("auto", "models/merged-dir", **gpu8) is False          # unknown size: full precision
    assert wants_4bit("auto", "Qwen/Qwen2.5-7B-Instruct", kind="cuda", vram_gb=24.0, bnb_available=True) is False
    assert wants_4bit("auto", "Qwen/Qwen2.5-7B-Instruct", kind="cuda", vram_gb=8.0, bnb_available=False) is False
    assert wants_4bit("auto", "Qwen/Qwen2.5-7B-Instruct", kind="cpu", vram_gb=0, bnb_available=True) is False


def test_explicit_settings_are_honoured_or_refused_clearly():
    assert wants_4bit(False, "Qwen/Qwen2.5-7B-Instruct", "cuda", 8.0, True) is False
    assert wants_4bit(True, "Qwen/Qwen2.5-0.5B-Instruct", "cuda", 8.0, True) is True
    _raises(lambda: wants_4bit(True, "Qwen/Qwen2.5-7B-Instruct", "cpu", 0, True), "NVIDIA GPU")
    _raises(lambda: wants_4bit(True, "Qwen/Qwen2.5-7B-Instruct", "cuda", 8.0, False), "bitsandbytes")


def test_describe_reports_memory_fields_only_with_cuda():
    from dragonfarm.hardware import describe

    info = describe()
    if info["cuda_available"]:
        assert info["gpu_used_gb"] is None or info["gpu_used_gb"] >= 0
        assert info["gpu_free_gb"] is None or info["gpu_free_gb"] <= info["vram_gb"] + 0.01
    else:
        assert "gpu_used_gb" not in info
