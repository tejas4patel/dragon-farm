"""Kept generated pairs + retrieved excerpts -> a training table for dragonfarm.

  python build_train.py pairs_qwen3b.jsonl train_doc_rag.jsonl

The context for each pair is what retrieval returns for its *question* (not the
chunk it was written from), so training matches what happens at answer time,
including the cases where retrieval misses.
"""
import json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "rag_prototype"))
from rag_lib import Dense, top_k, load_jsonl
from eval_docs import chunk_text, K

pairs = [p for p in load_jsonl(sys.argv[1]) if p["dropped"] is None]
chunks = load_jsonl("chunks.jsonl")
d = Dense("BAAI/bge-small-en-v1.5", prefix_q="Represent this sentence for searching relevant passages: ",
          device=os.environ.get("DF_DEVICE"))
d.index([c["section"] + ". " + c["text"] for c in chunks])
n_hit = 0
with open(sys.argv[2], "w", encoding="utf-8") as f:
    for p in pairs:
        idx = top_k(d.scores(p["q"]), K)
        n_hit += p["chunk"] in [chunks[i]["id"] for i in idx]
        f.write(json.dumps({"question": p["q"], "context": "\n\n".join(chunk_text(chunks[i]) for i in idx),
                            "answer": p["a"]}, ensure_ascii=False) + "\n")
print(f"{len(pairs)} rows; source chunk retrieved for {n_hit} of them")
