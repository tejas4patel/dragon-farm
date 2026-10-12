"""Tiny retrieval helpers for the dragonfarm RAG prototype (no extra dependencies).

BM25 is implemented here; dense retrieval uses plain `transformers` mean pooling,
so it runs in the same environment dragonfarm already builds.
"""
import json, math, re
from collections import Counter

def load_jsonl(path):
    with open(path, encoding="utf-8") as f:
        return [json.loads(l) for l in f if l.strip()]

_tok = re.compile(r"[a-z0-9][a-z0-9.\-]*")
_STOP = set("a an the and or of to in on is it for with as at by be this that are was i my me you your we our can do not".split())

def tokens(s):
    return [t.strip(".-") for t in _tok.findall(s.lower()) if t not in _STOP]

class BM25:
    def __init__(self, docs, k1=1.5, b=0.75):
        self.docs = [tokens(d) for d in docs]
        self.k1, self.b = k1, b
        self.avg = sum(len(d) for d in self.docs) / len(self.docs)
        df = Counter(t for d in self.docs for t in set(d))
        n = len(self.docs)
        self.idf = {t: math.log(1 + (n - c + 0.5) / (c + 0.5)) for t, c in df.items()}
        self.tf = [Counter(d) for d in self.docs]

    def scores(self, query):
        q = tokens(query)
        out = []
        for d, tf in zip(self.docs, self.tf):
            s = 0.0
            for t in q:
                if t in tf:
                    f = tf[t]
                    s += self.idf[t] * f * (self.k1 + 1) / (f + self.k1 * (1 - self.b + self.b * len(d) / self.avg))
            out.append(s)
        return out

class Dense:
    def __init__(self, model_name, prefix_q="", prefix_d="", device=None):
        import torch
        from transformers import AutoModel, AutoTokenizer
        self.torch = torch
        self.device = device or ("cuda" if torch.cuda.is_available() else "cpu")
        self.tok = AutoTokenizer.from_pretrained(model_name)
        self.model = AutoModel.from_pretrained(model_name).to(self.device).eval()
        self.pq, self.pd = prefix_q, prefix_d

    def encode(self, texts, prefix=""):
        torch = self.torch
        vecs = []
        for i in range(0, len(texts), 32):
            batch = [prefix + t for t in texts[i:i + 32]]
            enc = self.tok(batch, padding=True, truncation=True, max_length=256, return_tensors="pt").to(self.device)
            with torch.no_grad():
                h = self.model(**enc).last_hidden_state
            m = enc["attention_mask"].unsqueeze(-1).to(h.dtype)
            v = (h * m).sum(1) / m.sum(1)
            vecs.append(torch.nn.functional.normalize(v, dim=-1).cpu())
        return torch.cat(vecs)

    def index(self, docs):
        self.D = self.encode(docs, self.pd)

    def scores(self, query):
        q = self.encode([query], self.pq)
        return (q @ self.D.T)[0].tolist()

def top_k(scores, k):
    return sorted(range(len(scores)), key=lambda i: -scores[i])[:k]

def doc_text(chunk):
    return chunk["title"] + ". " + chunk["text"]

def ticket_text(t):
    return t["subject"] + "\n\n" + t["body"]
