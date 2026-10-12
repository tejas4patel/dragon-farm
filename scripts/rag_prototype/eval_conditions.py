"""Generate replies for unseen tickets under several conditions and score them.

  python eval_conditions.py gen   <condition> [--adapter DIR] [--base ID] [--changed]
  python eval_conditions.py score

Scoring is automatic and deterministic (see FACTS / quantity checks below); it
does not need a judge model. Outputs are cached in outputs/<condition>.jsonl.
"""
import json, os, re, sys, argparse
from rag_lib import load_jsonl

SYSTEM_RAG = ("You are a customer support agent for a smart-home company. Answer the customer's "
              "ticket using only the policy excerpts provided. Do not state policies, numbers, "
              "or timeframes that are not in the excerpts.")

def p_plain(t): return f"{t['subject']}\n\n{t['body']}"
def p_rag(t): return f"Policy excerpts:\n{t['context']}\n\nTicket:\n{t['subject']}\n\n{t['body']}"

# ---------------------------------------------------------------- generation
def generate(cond, base, adapter, rows, prompt_fn, system=None, max_new=220, bs=16):
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer
    tok = AutoTokenizer.from_pretrained(base, padding_side="left")
    model = AutoModelForCausalLM.from_pretrained(base, torch_dtype=torch.bfloat16).to("cuda").eval()
    if adapter:
        from peft import PeftModel
        model = PeftModel.from_pretrained(model, adapter).eval()
    outs = []
    for i in range(0, len(rows), bs):
        chunk = rows[i:i + bs]
        texts = []
        for t in chunk:
            msgs = ([{"role": "system", "content": system}] if system else []) + [{"role": "user", "content": prompt_fn(t)}]
            texts.append(tok.apply_chat_template(msgs, tokenize=False, add_generation_prompt=True))
        enc = tok(texts, return_tensors="pt", padding=True).to("cuda")
        with torch.no_grad():
            g = model.generate(**enc, max_new_tokens=max_new, do_sample=False, pad_token_id=tok.pad_token_id)
        for t, seq in zip(chunk, g):
            outs.append({"id": t["id"], "category": t["category"],
                         "reply": tok.decode(seq[enc["input_ids"].shape[1]:], skip_special_tokens=True).strip()})
    return outs

CONDS = {  # name -> (prompt_fn, system)
    "base_plain":  (p_plain, None),
    "ft_plain":    (p_plain, None),
    "base_rag":    (p_rag, SYSTEM_RAG),
    "ft_rag":      (p_rag, None),
    "ragtuned":    (p_rag, None),
}

# ---------------------------------------------------------------- scoring
def facts(changed):
    ret = "45 days" if changed else "30 days"
    dmg = "3 business days" if changed else "2 business days"
    war = "3-year" if changed else "2-year"
    app = "4.13.0" if changed else "4.12.2"
    return {
        "wifi": [r"2\.4 ?ghz", r"band.steering", r"10 seconds", r"amber", r"24 hours", r"router model"],
        "billing": [r"2 to 3 business days|2-3 business days", r"last four", r"order number", r"one business day|1 business day|within a business day"],
        "damaged": [r"no cost|no charge|on us|free", r"photo", r"shipping label", r"prepaid", re.escape(dmg)],
        "app": [re.escape(app), r"sign out", r"force close", r"refresh|pull down", r"email"],
        "return": [re.escape(ret), r"orders", r"start a return", r"prepaid", r"5 business days", r"remove"],
        "warranty": [re.escape(war), r"order number|serial number", r"replacement|replace"],
        "howto": [r"automations", r"\badd\b", r"trigger"],
    }

WORDS = {"a": "1", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6"}
QTY = re.compile(r"\b(\d+(?:\.\d+)?|a|one|two|three|four|five|six)(?:\s*(?:to|-|or)\s*(\d+))?[\s-]*"
                 r"(business days?|days?|hours?|seconds?|years?|minutes?|weeks?|months?|ghz)\b", re.I)
VER = re.compile(r"\b\d+\.\d+\.\d+\b")

def quantities(text):
    q = set()
    for m in QTY.finditer(text):
        unit = re.sub(r"s$", "", m.group(3).lower())
        for g in (m.group(1), m.group(2)):
            if g:
                q.add(f"{WORDS.get(g.lower(), g.lower())} {unit}")
    q.update(VER.findall(text))
    return q

def allowed_for(category, kb, ticket_text):
    a = set()
    for c in kb:
        if c["category"] in (category, "general"):  # general chunks are in the library for every ticket
            a |= quantities(c["title"] + ". " + c["text"])
    return a | quantities(ticket_text)

def score_condition(outs, tickets, kb, changed):
    F = facts(changed)
    byid = {t["id"]: t for t in tickets}
    rec, unsup, words = [], [], []
    for o in outs:
        t = byid[o["id"]]; r = o["reply"].lower()
        hits = [bool(re.search(p, r)) for p in F[o["category"]]]
        rec.append(sum(hits) / len(hits))
        extra = quantities(o["reply"]) - allowed_for(o["category"], kb, t["subject"] + " " + t["body"])
        o["unsupported"] = sorted(extra)
        unsup.append(bool(extra)); words.append(len(r.split()))
    n = len(outs)
    return dict(n=n, fact_recall=round(sum(rec) / n, 3), unsupported_rate=round(sum(unsup) / n, 3),
                avg_words=round(sum(words) / n, 1))

def changed_fact_rates(outs):
    spec = {"return": ("45 days", "30 days"), "damaged": ("3 business days", "2 business days"),
            "warranty": ("3-year", "2-year"), "app": ("4.13.0", "4.12.2")}
    res = {}
    for cat, (new, old) in spec.items():
        rs = [o["reply"].lower() for o in outs if o["category"] == cat]
        res[cat] = dict(new=round(sum(new in r for r in rs) / len(rs), 2), stale=round(sum(old in r for r in rs) / len(rs), 2))
    tot_new = sum(v["new"] for v in res.values()) / 4; tot_stale = sum(v["stale"] for v in res.values()) / 4
    return dict(by_category=res, new_mean=round(tot_new, 3), stale_mean=round(tot_stale, 3))

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("mode"); ap.add_argument("cond", nargs="?")
    ap.add_argument("--adapter"); ap.add_argument("--base", default="Qwen/Qwen2.5-0.5B-Instruct")
    ap.add_argument("--tag", default="")
    ap.add_argument("--changed", action="store_true")
    a = ap.parse_args()
    os.makedirs("outputs", exist_ok=True)
    if a.mode == "gen":
        rows = load_jsonl("eval_changed_with_context.jsonl" if a.changed else "eval_with_context.jsonl")
        fn, system = CONDS[a.cond]
        name = a.cond + a.tag + ("__changed" if a.changed else "")
        outs = generate(a.cond, a.base, a.adapter, rows, fn, system)
        with open(f"outputs/{name}.jsonl", "w", encoding="utf-8") as f:
            for o in outs: f.write(json.dumps(o, ensure_ascii=False) + "\n")
        print("wrote", name, len(outs))
    else:
        kb, kb2 = load_jsonl("kb.jsonl"), load_jsonl("kb_changed.jsonl")
        t_main, t_ch = load_jsonl("eval_with_context.jsonl"), load_jsonl("eval_changed_with_context.jsonl")
        results = {}
        for fn_ in sorted(os.listdir("outputs")):
            if not fn_.endswith(".jsonl"): continue
            name = fn_[:-6]; outs = load_jsonl("outputs/" + fn_)
            ch = name.endswith("__changed")
            res = score_condition(outs, t_ch if ch else t_main, kb2 if ch else kb, ch)
            if ch: res["changed_facts"] = changed_fact_rates(outs)
            results[name] = res
            with open("outputs/" + fn_, "w", encoding="utf-8") as f:
                for o in outs: f.write(json.dumps(o, ensure_ascii=False) + "\n")
        json.dump(results, open("results.json", "w"), indent=1)
        for k, v in results.items(): print(k, json.dumps(v))
