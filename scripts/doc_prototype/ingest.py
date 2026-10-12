"""Documents -> text -> chunks. PDF (pypdf), HTML (stdlib), Markdown, plain text.

  python ingest.py corpus/ chunks.jsonl

Each chunk keeps its source file and the heading it sits under, so answers can
cite where they came from. Nothing here needs a network or a model.
"""
import json, re, sys, pathlib
from html.parser import HTMLParser

# ------------------------------------------------------------------ readers
class _Html(HTMLParser):
    SKIP = {"script", "style", "nav", "header", "footer", "svg", "button", "noscript", "head"}
    VOID = {"meta", "link", "br", "img", "hr", "input", "source"}
    BLOCK = {"p", "li", "h1", "h2", "h3", "h4", "pre", "tr", "div", "section", "blockquote", "dt", "dd"}
    def __init__(self, main_only):
        super().__init__(); self.out = []; self.cur = []; self.head = None; self.pre = 0
        self.main_only = main_only; self.in_main = 0
        self.skip_tag = None; self.skip_depth = 0
    def _active(self): return self.skip_tag is None and (not self.main_only or self.in_main > 0)
    def _flush(self):
        t = "".join(self.cur).strip()
        if t: self.out.append((("#" * self.head + " ") if self.head else "") + t)
        self.cur = []; self.head = None
    def handle_starttag(self, tag, attrs):
        if tag in self.VOID:
            if tag == "br" and self._active(): self.cur.append("\n" if self.pre else " ")
            return
        a = dict(attrs)
        if self.skip_tag is not None:
            if tag == self.skip_tag: self.skip_depth += 1
            return
        if tag in self.SKIP or "visually-hidden" in (a.get("class") or ""):
            self._flush(); self.skip_tag, self.skip_depth = tag, 1; return
        if tag == "main": self.in_main += 1
        if not self._active(): return
        if tag in self.BLOCK:
            self._flush()
            if tag in ("h1", "h2", "h3", "h4"): self.head = int(tag[1])
            if tag == "pre": self.pre += 1
        if tag in ("td", "th") and self.cur: self.cur.append(" | ")
    def handle_endtag(self, tag):
        if tag in self.VOID: return
        if self.skip_tag is not None:
            if tag == self.skip_tag:
                self.skip_depth -= 1
                if self.skip_depth == 0: self.skip_tag = None
            return
        if tag == "main": self._flush(); self.in_main -= 1; return
        if not self._active(): return
        if tag in self.BLOCK:
            self._flush()
            if tag == "pre": self.pre = max(0, self.pre - 1)
    def handle_data(self, d):
        if self._active(): self.cur.append(d if self.pre else re.sub(r"\s+", " ", d))

def read_html(path):
    raw = pathlib.Path(path).read_text(encoding="utf-8", errors="replace")
    p = _Html("<main" in raw); p.feed(raw); p._flush()
    return "\n\n".join(p.out)

def read_pdf(path):
    sys.path.insert(0, __import__("os").environ.get("DF_PYLIBS", ""))
    from pypdf import PdfReader
    paras, buf = [], []
    def flush():
        if buf: paras.append(" ".join(buf)); buf.clear()
    for pg in PdfReader(path).pages:
        for line in (pg.extract_text() or "").splitlines():
            line = line.strip()
            if not line: flush(); continue
            short = len(line) < 55 and not re.search(r"[.,;:)]$", line)
            if short and not buf: paras.append("## " + line); continue   # heading-like line
            buf.append(line)
            if re.search(r"[.:]$", line) and len(line) < 60: flush()
    flush()
    return "\n\n".join(paras)

def read_text(path): return pathlib.Path(path).read_text(encoding="utf-8", errors="replace")

READERS = {".html": read_html, ".htm": read_html, ".pdf": read_pdf, ".md": read_text, ".txt": read_text}

# ------------------------------------------------------------------ chunker
def words(s): return len(s.split())

def chunk(text, source, max_words=170, min_words=35):
    text = re.sub(r"[-​﻿]", "", text)   # icon-font glyphs and zero-width marks from PDFs/HTML
    chunks, section, cur, cur_w = [], "", [], 0
    def emit():
        nonlocal cur, cur_w
        body = "\n\n".join(cur).strip()
        if words(body) >= min_words:
            chunks.append({"source": source, "section": section, "text": body})
        elif words(body) >= 12:               # a short section: fold into the previous chunk, or keep it
            if chunks and words(chunks[-1]["text"]) + words(body) <= max_words * 1.5:
                chunks[-1]["text"] += "\n\n" + (section + ". " if section else "") + body
            else:
                chunks.append({"source": source, "section": section, "text": body})
        cur, cur_w = [], 0
    in_code = False
    units = []
    for block in re.split(r"\n\s*\n", text):
        block = block.strip()
        if block: units.append(block)
    for u in units:
        m = re.match(r"^(#{1,4})\s+(.*)", u)
        if m:                                  # a heading starts a new chunk
            emit(); section = m.group(2).strip()
            continue
        w = words(u)
        if cur and cur_w + w > max_words: emit()
        cur.append(u); cur_w += w
    emit()
    return chunks

def main(src, out):
    allc = []
    for f in sorted(pathlib.Path(src).iterdir()):
        rd = READERS.get(f.suffix.lower())
        if not rd: print("skip", f.name); continue
        txt = rd(str(f)); cs = chunk(txt, f.name)
        print(f"{f.name}: {words(txt)} words -> {len(cs)} chunks")
        allc += cs
    for i, c in enumerate(allc): c["id"] = f"c{i:03d}"
    with open(out, "w", encoding="utf-8") as fh:
        for c in allc: fh.write(json.dumps(c, ensure_ascii=False) + "\n")
    print("total", len(allc), "chunks; words/chunk median", sorted(words(c["text"]) for c in allc)[len(allc)//2])

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
