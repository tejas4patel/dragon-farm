"""Index building, reuse, weighting, and search, with a stub encoder (no model download)."""

import json
import tempfile
from pathlib import Path

import torch

from dragonfarm import documents as D
from dragonfarm import retrieval as R

VOCAB = ["return", "refund", "days", "warranty", "year", "wifi", "router", "band", "reset", "app", "version", "changelog"]


class StubEncoder:
    """Bag-of-words over a tiny vocabulary, normalised: deterministic and cheap."""

    model_id = "stub"
    query_prefix = ""

    def encode(self, texts, batch_size=32, prefix=""):
        rows = []
        for t in texts:
            words = t.lower().replace(".", " ").replace(",", " ").split()
            v = torch.tensor([float(sum(w.startswith(tok) for w in words)) for tok in VOCAB]) + 1e-3
            rows.append(v / v.norm())
        return torch.stack(rows)

    def encode_queries(self, texts):
        return self.encode(texts)


def _make_set(tmp):
    src = Path(tmp) / "src"
    src.mkdir()
    (src / "policy.md").write_text(
        "# Returns\n\n" + "Any device can be returned within 30 days of delivery for a full refund. " * 6 +
        "\n\n# Warranty\n\n" + "Every device carries a 2-year warranty from delivery; a warranty claim needs the serial number. " * 6 +
        "\n\n# Wi-Fi\n\n" + "Wi-Fi drops come from band steering on mesh routers; reset the device and use the 2.4 GHz band. " * 6,
        encoding="utf-8")
    (src / "NEWS.md").write_text("# 1.2.0\n\n" + "Changelog: the return flow and refund timing changed in this version. " * 8, encoding="utf-8")
    out = Path(tmp) / "set"
    D.build([str(src)], out, "t", max_words=120, min_words=20)
    return out


def test_index_is_built_reused_and_rebuilt_when_chunks_change():
    with tempfile.TemporaryDirectory() as tmp:
        out = _make_set(tmp)
        enc = StubEncoder()
        logs = []
        info = R.build_index(out, encoder=enc, model_id="stub", log=logs.append)
        assert info["n_chunks"] == 4 and info["dim"] == len(VOCAB) and info["model"] == "stub"
        assert (out / "index" / "embeddings.npy").exists()
        manifest = json.loads((out / "manifest.json").read_text(encoding="utf-8"))
        assert manifest["index"]["signature"] == info["signature"]

        again = R.build_index(out, encoder=enc, model_id="stub", log=logs.append)
        assert again == info and any("up to date" in m for m in logs)

        forced = R.build_index(out, encoder=enc, model_id="stub", force=True)
        assert forced["signature"] == info["signature"]

        # A changed chunk set invalidates the index: documents.build drops the stale block.
        (Path(tmp) / "src" / "policy.md").write_text("# Only\n\n" + "Something else entirely about the app version. " * 10, encoding="utf-8")
        D.build([str(Path(tmp) / "src")], out, "t", max_words=120, min_words=20)
        manifest = json.loads((out / "manifest.json").read_text(encoding="utf-8"))
        assert manifest["index"] is None
        rebuilt = R.build_index(out, encoder=enc, model_id="stub")
        assert rebuilt["signature"] != info["signature"]


def test_search_ranks_by_similarity_times_weight():
    with tempfile.TemporaryDirectory() as tmp:
        out = _make_set(tmp)
        enc = StubEncoder()
        R.build_index(out, encoder=enc, model_id="stub")
        idx = R.LoadedIndex(out)
        hits = idx.search(enc.encode_queries(["How long is the warranty?"]), k=2)[0]
        assert [h["id"] for h in hits][0].endswith("-001") or "warranty" in idx.chunks[idx.ids.index(hits[0]["id"])]["text"].lower()
        # the changelog chunk talks about returns and refunds too, but is down-weighted below the policy
        hits = idx.search(enc.encode_queries(["return refund days"]), k=2)[0]
        top = idx.chunks[idx.ids.index(hits[0]["id"])]
        assert top["source"] == "policy.md" and top["section"] == "Returns"
        news = [h for h in hits if idx.chunks[idx.ids.index(h["id"])]["source"] == "NEWS.md"]
        assert all(abs(h["score"] - 0.7 * h["similarity"]) < 1e-6 for h in news)
        assert len(idx.search(enc.encode_queries(["x"]), k=99)[0]) == 4   # k is capped at the chunk count


def test_loaded_index_detects_a_rebuild():
    with tempfile.TemporaryDirectory() as tmp:
        out = _make_set(tmp)
        enc = StubEncoder()
        R.build_index(out, encoder=enc, model_id="stub")
        idx = R.LoadedIndex(out)
        assert not idx.stale()
        import os, time
        time.sleep(0.05)
        R.build_index(out, encoder=enc, model_id="stub", force=True)
        os.utime(out / "index" / "embeddings.npy", None)
        assert idx.stale()


def test_missing_index_is_a_clear_error():
    with tempfile.TemporaryDirectory() as tmp:
        out = _make_set(tmp)
        try:
            R.LoadedIndex(out)
        except RuntimeError as e:
            assert "dragon_index" in str(e)
        else:
            raise AssertionError("expected RuntimeError")


def test_chunk_signature_depends_on_ids_only():
    assert R.chunk_signature(["a", "b"]) == R.chunk_signature(["a", "b"])
    assert R.chunk_signature(["a", "b"]) != R.chunk_signature(["b", "a"])


def test_keyword_tokens_keep_numbers_and_drop_stop_words():
    assert R.keyword_tokens("How many employees did Costco have? 333,000 and $4,409.") == \
        ["many", "employees", "costco", "have", "333,000", "4,409"]   # "$" dropped: tables write "$ 4,409" or "(4,409)"


def test_bm25_prefers_the_chunk_with_the_exact_terms():
    bm = R.BM25(["We employed 333,000 employees worldwide.", "Warehouses opened in Japan and Korea.",
                 "Employees receive wage increases."])
    s = bm.scores("how many employees at year end 333,000")
    assert s.argmax() == 0 and s[1] == 0


def test_hybrid_search_lifts_a_keyword_match_the_embedding_ranks_low():
    import numpy as np

    class Vec:
        def __init__(self, a):
            self.a = np.asarray(a, dtype="float32")

        def numpy(self):
            return self.a

    idx = R.LoadedIndex.__new__(R.LoadedIndex)
    idx.ids = ["a", "b", "c", "d"]
    idx.chunks = [{"text": t} for t in ["Warehouse openings by country.", "Membership fee revenue.",
                                         "Executive officers.", "We employed 333,000 employees at year end."]]
    idx.vectors = np.eye(4, dtype="float32")
    idx.weights = np.ones(4, dtype="float32")
    idx.bm25 = R.BM25([c["text"] for c in idx.chunks])
    q = Vec([[0.9, 0.8, 0.7, 0.1]])          # the embedding puts the employee chunk last
    dense = [h["id"] for h in idx.search(q, k=2)[0]]
    hybrid = [h["id"] for h in idx.search(q, k=2, queries=["How many employees at year end?"])[0]]
    assert dense == ["a", "b"]
    assert "d" in hybrid
    assert idx.search(q, k=2, queries=["employees"], mode="dense")[0][0]["id"] == "a"
    # scores keep the cosine x weight scale whatever the ordering
    by_id = {h["id"]: h["score"] for h in idx.search(q, k=4, queries=["employees"])[0]}
    assert abs(by_id["d"] - 0.1) < 1e-6 and abs(by_id["a"] - 0.9) < 1e-6
