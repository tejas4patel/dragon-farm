"""Answer the 35 gold questions about the documentation under several conditions.

  python eval_docs.py retrieval                      # hit@k of bge-small over chunks.jsonl
  python eval_docs.py gen <name> [--base ID] [--adapter DIR] [--no-rag]
  python eval_docs.py score

Scoring: a question counts as answered when every regex in its `all_of` list
matches the reply (case-insensitive). `cites` is whether the retrieved set
contained a chunk that itself matches all_of (so the model had the fact in front
of it); `unsupported_ids` counts replies that name a function, file or version
that appears in neither the retrieved chunks nor the question.
"""
import json, os, re, sys, argparse
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "rag_prototype"))
from rag_lib import Dense, top_k, load_jsonl
from qa_gen import identifiers

K = 4
SYSTEM = ("You answer questions about the dragonfarm R package using only the documentation excerpts provided. "
          "If the excerpts do not contain the answer, say so. Keep answers to one to three sentences.")

def chunk_text(c): return f'[{c["source"]} > {c["section"]}]\n{c["text"]}'

def retrieve(questions, chunks):
    d = Dense("BAAI/bge-small-en-v1.5", prefix_q="Represent this sentence for searching relevant passages: ",
              device=os.environ.get("DF_DEVICE"))   # DF_DEVICE=cpu keeps the GPU free for generation
    d.index([c["section"] + ". " + c["text"] for c in chunks])
    return [top_k(d.scores(q), K) for q in questions]

def matches(text, pats): return all(re.search(p, text.lower()) for p in pats)

def prompt_rag(q, ctx): return f"Documentation excerpts:\n{ctx}\n\nQuestion: {q}"

def generate(base, adapter, prompts, system, max_new=160, bs=8):
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer
    tok = AutoTokenizer.from_pretrained(base, padding_side="left")
    model = AutoModelForCausalLM.from_pretrained(base, dtype=torch.bfloat16).to("cuda").eval()
    if adapter:
        from peft import PeftModel
        model = PeftModel.from_pretrained(model, adapter).eval()
    outs = []
    for i in range(0, len(prompts), bs):
        texts = [tok.apply_chat_template(([{"role": "system", "content": system}] if system else []) + [{"role": "user", "content": p}],
                                         tokenize=False, add_generation_prompt=True) for p in prompts[i:i + bs]]
        enc = tok(texts, return_tensors="pt", padding=True).to("cuda")
        with torch.no_grad():
            g = model.generate(**enc, max_new_tokens=max_new, do_sample=False, pad_token_id=tok.pad_token_id)
        outs += [tok.decode(s[enc["input_ids"].shape[1]:], skip_special_tokens=True).strip() for s in g]
    return outs

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("mode"); ap.add_argument("name", nargs="?")
    ap.add_argument("--base", default="Qwen/Qwen2.5-0.5B-Instruct"); ap.add_argument("--adapter")
    ap.add_argument("--no-rag", action="store_true"); ap.add_argument("--no-system", action="store_true")
    a = ap.parse_args()
    chunks = load_jsonl("chunks.jsonl"); gold = load_jsonl("gold.jsonl")
    os.makedirs("outputs", exist_ok=True)
    qs = [g["q"] for g in gold]

    if a.mode == "retrieval":
        hits = retrieve(qs, chunks)
        res = {}
        for k in (1, 2, 4):
            res[f"hit@{k}"] = round(sum(any(matches(chunks[i]["text"], g["all_of"]) for i in h[:k]) for g, h in zip(gold, hits)) / len(gold), 3)
        json.dump({"k": K, "hits": hits, **res}, open("outputs/retrieval.json", "w"), indent=1)
        print(res)

    elif a.mode == "gen":
        hits = json.load(open("outputs/retrieval.json"))["hits"]
        if a.no_rag:
            prompts = qs
        else:
            prompts = [prompt_rag(q, "\n\n".join(chunk_text(chunks[i]) for i in h)) for q, h in zip(qs, hits)]
        replies = generate(a.base, a.adapter, prompts, None if (a.no_rag or a.no_system) else SYSTEM)
        with open(f"outputs/{a.name}.jsonl", "w", encoding="utf-8") as f:
            for g, h, r in zip(gold, hits, replies):
                f.write(json.dumps({"q": g["q"], "reply": r, "retrieved": h if not a.no_rag else []}, ensure_ascii=False) + "\n")
        print("wrote", a.name)

    else:
        results = {}
        for fn in sorted(os.listdir("outputs")):
            if not fn.endswith(".jsonl"): continue
            rows = load_jsonl("outputs/" + fn); name = fn[:-6]
            ok = cited = unsup = 0
            for g, r in zip(gold, rows):
                ans = matches(r["reply"], g["all_of"]); ok += ans
                ctx = " ".join(chunk_text(chunks[i]) for i in r["retrieved"])
                cited += any(matches(chunks[i]["text"], g["all_of"]) for i in r["retrieved"])
                known = identifiers(ctx + " " + g["q"]) | set(re.findall(r"[a-z0-9_.]+", (ctx + " " + g["q"]).lower()))
                extra = [i for i in identifiers(r["reply"]) if i not in known]
                r["unsupported"] = extra; r["correct"] = ans; unsup += bool(extra)
            n = len(rows)
            results[name] = dict(answered=round(ok / n, 3), fact_in_context=round(cited / n, 3), unsupported_ids=round(unsup / n, 3),
                                 avg_words=round(sum(len(r["reply"].split()) for r in rows) / n, 1))
            with open("outputs/" + fn, "w", encoding="utf-8") as f:
                for r in rows: f.write(json.dumps(r, ensure_ascii=False) + "\n")
        json.dump(results, open("results.json", "w"), indent=1)
        for k, v in results.items(): print(k, json.dumps(v))
