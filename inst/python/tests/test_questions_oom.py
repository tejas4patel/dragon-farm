"""The question generator survives GPU memory errors. Seen on an 8 GB card with
the 7B generator: one long chunk in a batch of four ran out of memory 236
chunks in, and the whole job died with the rest unwritten."""

from dragonfarm import questions as Q


def _chunks(n):
    return [{"id": f"c{i}", "source": "doc.pdf", "section": "S", "text": "words " * 20} for i in range(n)]


def test_a_batch_that_does_not_fit_is_retried_one_chunk_at_a_time():
    calls = []

    def gen(batch):
        calls.append(len(batch))
        if len(batch) > 1:
            raise RuntimeError("CUDA out of memory. Tried to allocate 1.65 GiB")
        return ["Q1: q\nA1: a" for _ in batch]

    outputs, skipped = Q.generate_batch(_chunks(4), gen)
    assert [cid for cid, _ in outputs] == ["c0", "c1", "c2", "c3"]
    assert skipped == []
    assert calls == [4, 1, 1, 1, 1]


def test_a_single_chunk_that_never_fits_is_skipped_and_reported():
    messages = []

    def gen(batch):
        if any(c["id"] == "c2" for c in batch):
            raise RuntimeError("CUDA out of memory")
        return ["Q1: q\nA1: a" for _ in batch]

    outputs, skipped = Q.generate_batch(_chunks(4), gen, log=messages.append)
    assert [cid for cid, _ in outputs] == ["c0", "c1", "c3"]
    assert skipped == ["c2"]
    assert any("c2" in m and "skipped" in m for m in messages)


def test_other_errors_still_propagate():
    def gen(batch):
        raise ValueError("not a memory problem")

    try:
        Q.generate_batch(_chunks(2), gen)
    except ValueError:
        return
    raise AssertionError("expected the ValueError to propagate")


def test_long_code_chunks_are_cut_in_the_prompt_but_prose_is_not():
    prose = {"id": "p", "source": "a", "section": "", "text": "word " * 160}
    code = {"id": "c", "source": "a", "section": "", "text": "x <- 1\n" * 2000}
    assert Q.passage(prose) == prose["text"]
    cut = Q.passage(code)
    assert cut.endswith(" ...") and len(cut.split()) <= Q.MAX_PASSAGE_WORDS + 1
    assert "x <- 1" in Q.prompt_for(code, 2)
