"""Training failures that mean the GPU ran out of memory carry a hint."""

from dragonfarm.train import memory_hint


class OutOfMemoryError(RuntimeError):
    pass


def test_cublas_execution_failure_gets_the_hint():
    e = RuntimeError("CUDA error: CUBLAS_STATUS_EXECUTION_FAILED when calling `cublasSgemmStridedBatched(...)`")
    assert "ran out of memory" in memory_hint(e)
    assert "batch size 1" in memory_hint(e)


def test_out_of_memory_errors_get_the_hint():
    assert memory_hint(RuntimeError("CUDA out of memory. Tried to allocate 2.00 GiB")) != ""
    assert memory_hint(OutOfMemoryError("anything")) != ""


def test_other_errors_do_not():
    assert memory_hint(ValueError("Unknown column 'reply'")) == ""
    assert memory_hint(FileNotFoundError("train.jsonl")) == ""
