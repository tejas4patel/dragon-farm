"""Retrieval quality on unseen tickets and on the shipped training tickets.
Gold = chunks whose category equals the ticket's category (3 per category).
hit@k: any gold chunk in top k. recall@k: fraction of the 3 gold chunks in top k.
"""
import json, sys
from rag_lib import *

here = "."
kb = load_jsonl("kb.jsonl")
docs = [doc_text(c) for c in kb]
unseen = load_jsonl("eval_tickets.jsonl")
shipped = load_jsonl("../../inst/extdata/support_tickets.jsonl")[:112]  # a slice is enough
sets = {"unseen(56)": unseen, "shipped(112)": shipped}

systems = {"BM25": BM25(docs)}
for name, kw in [("MiniLM-L6", dict(model_name="sentence-transformers/all-MiniLM-L6-v2")),
                 ("bge-small", dict(model_name="BAAI/bge-small-en-v1.5", prefix_q="Represent this sentence for searching relevant passages: "))]:
    try:
        d = Dense(**kw); d.index(docs); systems[name] = d
    except Exception as e:
        print("skip", name, repr(e)[:150])

res = {}
for sname, tickets in sets.items():
    for yname, sysm in systems.items():
        for k in (1, 3, 5):
            hit = rec = mrr = 0
            for t in tickets:
                idx = top_k(sysm.scores(ticket_text(t)), k)
                gold = {i for i, c in enumerate(kb) if c["category"] == t["category"]}
                got = [i for i in idx if i in gold]
                hit += bool(got); rec += len(got) / len(gold)
                if k == 5:
                    full = top_k(sysm.scores(ticket_text(t)), len(kb))
                    r = next(j for j, i in enumerate(full) if i in gold) + 1
                    mrr += 1 / r
            n = len(tickets)
            res[f"{sname}|{yname}|k={k}"] = dict(hit=round(hit / n, 3), recall=round(rec / n, 3), **({"mrr": round(mrr / n, 3)} if k == 5 else {}))
for k, v in res.items():
    print(k, v)
json.dump(res, open("retrieval_results.json", "w"), indent=1)
