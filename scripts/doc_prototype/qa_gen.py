"""Chunks -> question/answer pairs with a local instruct model, then filters.

  python qa_gen.py chunks.jsonl pairs_<tag>.jsonl Qwen/Qwen2.5-3B-Instruct [--per-chunk 3] [--bs 4]

Nothing is sent to a remote service. Each pair is kept with the reason it was
dropped (if it was), so the filters can be inspected.
"""
import json, re, sys, argparse

def passage(c): return f'{c["source"]} > {c["section"]}\n{c["text"]}'

PROMPT = ('Passage from the documentation of a software package (file: {source}, section: "{section}"):\n'
          '"""\n{text}\n"""\n\n'
          'Write {n} different questions that a user of this software might ask, each fully answered by this passage alone. '
          'Make every question self-contained: name the function, feature or setting it is about, and never mention '
          '"the passage", "the text" or "the document". Then answer each question in one or two sentences, using only '
          'facts stated in the passage.\n'
          'Use exactly this format:\n' + "\n".join(f"Q{i}: ...\nA{i}: ..." for i in (1, 2, 3)))

def parse(out):
    pairs = []
    for m in re.finditer(r"Q(\d)\s*:\s*(.+?)\s*\n+\s*A\1\s*:\s*(.+?)(?=\n+\s*Q\d\s*:|\Z)", out, re.S):
        q, a = m.group(2).strip(), re.sub(r"\s+", " ", m.group(3)).strip()
        pairs.append((re.sub(r"\s+", " ", q), a))
    return pairs

STOP = set("a an the and or of to in on is it for with as at by be this that are was can you your i my not if from "
           "then so do does will which what how when into than also its their they them these those has have use used "
           "using allows allow user users function feature software provides provide".split())
def stem(t): return re.sub(r"(ing|ed|es|s)$", "", t) if len(t) > 4 else t
def content(s): return [stem(t) for t in re.findall(r"[a-z0-9_.\-]+", s.lower()) if t not in STOP and len(t) > 1]
def identifiers(s):
    """Code-like tokens: snake_case names, calls with (), file names, versions, flags."""
    ids = set(re.findall(r"[A-Za-z]+_[A-Za-z_]+|[A-Za-z_.]+\(\)|\w+\.(?:R|Rmd|json|jsonl|py|md)|\d+\.\d+(?:\.\d+)?", s))
    return {i.rstrip("()").lower() for i in ids}

THRESHOLD = 0.55
META = re.compile(r"\b(the passage|this passage|the text|this text|the document|this document|the section|the article|the excerpt|according to the)\b", re.I)

def grounded(answer, ctx):
    toks = content(answer)
    if not toks: return 0.0
    cset = set(content(ctx))
    return sum(t in cset for t in toks) / len(toks)

def unknown_ids(answer, ctx):
    have = identifiers(ctx) | {t for t in re.findall(r"[a-z0-9_.]+", ctx.lower())}
    return sorted(i for i in identifiers(answer) if i not in have)

def judge(q, a, c, seen):
    if not (5 <= len(q.split()) <= 45): return "question length"
    if not q.rstrip().endswith("?"): return "not a question"
    if not (3 <= len(a.split()) <= 90): return "answer length"
    if META.search(q) or META.search(a): return "refers to the passage"
    bad = unknown_ids(a, passage(c)) + unknown_ids(q, passage(c))
    if bad: return f"names not in the source ({bad[0]})"
    g = grounded(a, passage(c))
    if g < THRESHOLD: return f"answer not grounded ({g:.2f})"
    qs = set(content(q))
    for s in seen:
        if len(qs & s) / max(1, len(qs | s)) > 0.8: return "duplicate question"
    seen.append(qs)
    return None

def generate(model_id, chunks, n, bs):
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer
    tok = AutoTokenizer.from_pretrained(model_id, padding_side="left")
    model = AutoModelForCausalLM.from_pretrained(model_id, dtype=torch.bfloat16).to("cuda").eval()
    outs = []
    for i in range(0, len(chunks), bs):
        batch = chunks[i:i + bs]
        texts = [tok.apply_chat_template([{"role": "user", "content": PROMPT.format(n=n, **{k: c[k] for k in ("source", "section", "text")})}],
                                         tokenize=False, add_generation_prompt=True) for c in batch]
        enc = tok(texts, return_tensors="pt", padding=True).to("cuda")
        with torch.no_grad():
            g = model.generate(**enc, max_new_tokens=420, do_sample=False, pad_token_id=tok.pad_token_id)
        outs += [tok.decode(s[enc["input_ids"].shape[1]:], skip_special_tokens=True) for s in g]
        print(f"  {min(i + bs, len(chunks))}/{len(chunks)}", flush=True)
    return outs

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("chunks"); ap.add_argument("out"); ap.add_argument("model")
    ap.add_argument("--per-chunk", type=int, default=3); ap.add_argument("--bs", type=int, default=4)
    ap.add_argument("--regenerate", action="store_true")
    ap.add_argument("--skip", default="NEWS.md", help="source files to leave out of generation")
    a = ap.parse_args()
    chunks = [json.loads(l) for l in open(a.chunks, encoding="utf-8")]
    chunks = [c for c in chunks if c["source"] not in a.skip.split(",")]
    import os
    rawp = a.out + ".raw.json"
    if os.path.exists(rawp) and not a.regenerate:
        raw = json.load(open(rawp, encoding="utf-8"))
    else:
        raw = generate(a.model, chunks, a.per_chunk, a.bs)
        json.dump(raw, open(rawp, "w", encoding="utf-8"))
    seen, rows, drop = [], [], {}
    for c, out in zip(chunks, raw):
        ps = parse(out)
        if not ps: drop["unparseable output"] = drop.get("unparseable output", 0) + 1
        for q, ans in ps:
            why = judge(q, ans, c, seen)
            rows.append({"chunk": c["id"], "source": c["source"], "q": q, "a": ans, "dropped": why})
            if why: drop[why.split(" (")[0]] = drop.get(why.split(" (")[0], 0) + 1
    with open(a.out, "w", encoding="utf-8") as f:
        for r in rows: f.write(json.dumps(r, ensure_ascii=False) + "\n")
    kept = sum(r["dropped"] is None for r in rows)
    print(f"{a.model}: {len(chunks)} chunks -> {len(rows)} pairs, kept {kept}; dropped by reason: {drop}")
