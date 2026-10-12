"""Retrieve policy excerpts (bge-small, top 5) for every ticket and write the
context-augmented files used for training and evaluation."""
import json, copy
from rag_lib import *

K = 5
kb = load_jsonl("kb.jsonl")

# A changed-policy copy of the knowledge base, to test whether answers follow
# the documents rather than what the model memorised during training.
CHANGES = {  # chunk id -> (old, new)
    "return-1": ("30 days", "45 days"),
    "damaged-3": ("2 business days", "3 business days"),
    "warranty-1": ("2-year", "3-year"),
    "app-1": ("4.12.2", "4.13.0"),
    "app-3": ("4.12.2", "4.13.0"),
}
kb2 = copy.deepcopy(kb)
for c in kb2:
    if c["id"] in CHANGES:
        old, new = CHANGES[c["id"]]
        assert old in c["text"], c["id"]
        c["text"] = c["text"].replace(old, new)
with open("kb_changed.jsonl", "w", encoding="utf-8") as f:
    for c in kb2:
        f.write(json.dumps(c, ensure_ascii=False) + "\n")

dense = Dense("BAAI/bge-small-en-v1.5", prefix_q="Represent this sentence for searching relevant passages: ")

def contextualise(tickets, kbase):
    dense.index([doc_text(c) for c in kbase])
    out = []
    for t in tickets:
        idx = top_k(dense.scores(ticket_text(t)), K)
        t = dict(t)
        t["retrieved"] = [kbase[i]["id"] for i in idx]
        t["context"] = "\n".join("- " + doc_text(kbase[i]) for i in idx)
        out.append(t)
    return out

def write(path, rows):
    with open(path, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

shipped = load_jsonl("../../inst/extdata/support_tickets.jsonl")
unseen = load_jsonl("eval_tickets.jsonl")
write("train_with_context.jsonl", contextualise(shipped, kb))
write("eval_with_context.jsonl", contextualise(unseen, kb))
changed_cats = {"return", "damaged", "warranty", "app"}
write("eval_changed_with_context.jsonl", contextualise([t for t in unseen if t["category"] in changed_cats], kb2))
print("ok")
