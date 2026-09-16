"""Persistent inference worker: python -m dragonfarm.worker

Reads one JSON request per line on stdin and writes one JSON response per
line on stdout, keeping loaded models in memory between requests. R talks
to it through a pipe, so a session pays the model load once instead of
once per call.

Requests:
  {"op": "ping"}
  {"op": "generate", "model": id_or_path, "adapter": path_or_null,
   "base_adapters": [paths], "trust_remote_code": bool,
   "conversations": [[{"role": ..., "content": ...}, ...], ...],
   "max_new_tokens": int, "temperature": float, "top_p": float,
   "stream": bool}
  {"op": "unload"}          drop cached models
  {"op": "quit"}

Responses:
  {"ok": true, "outputs": [...], "device": "cuda:0"}      (generate)
  {"ok": true, "token": "..."}  ... {"ok": true, "done": true, "output": "..."}   (streaming, one conversation)
  {"ok": false, "error": "..."}
"""

import json
import sys
import threading
import traceback
from collections import OrderedDict


def emit(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


class ModelCache:
    """Keep the most recently used models loaded (default: two)."""

    def __init__(self, capacity=2):
        self.capacity = capacity
        self.items = OrderedDict()
        self.hw = None

    def key(self, req):
        return json.dumps([req["model"], req.get("adapter"), req.get("base_adapters") or [],
                           bool(req.get("trust_remote_code", False))])

    def get(self, req):
        from .hardware import resolve
        from .loading import load_for_inference, load_tokenizer

        if self.hw is None:
            self.hw = resolve({"device": req.get("device", "auto"), "dtype": req.get("dtype", "auto")})
        k = self.key(req)
        if k in self.items:
            self.items.move_to_end(k)
            return self.items[k]
        while len(self.items) >= self.capacity:
            _, (old_tok, old_model) = self.items.popitem(last=False)
            del old_tok, old_model
            try:
                import torch

                if torch.cuda.is_available():
                    torch.cuda.empty_cache()
            except Exception:
                pass
        trust = bool(req.get("trust_remote_code", False))
        tok = load_tokenizer(req["model"], trust_remote_code=trust)
        model = load_for_inference(req["model"], self.hw, adapter=req.get("adapter"), trust_remote_code=trust,
                                   base_adapters=req.get("base_adapters") or [])
        self.items[k] = (tok, model)
        return tok, model

    def clear(self):
        self.items.clear()
        try:
            import torch

            if torch.cuda.is_available():
                torch.cuda.empty_cache()
        except Exception:
            pass


def generate_all(tok, model, hw, req):
    from .evaluate_utils import generate_reply

    outputs = []
    for messages in req["conversations"]:
        outputs.append(generate_reply(
            model, tok, messages, hw.device,
            max_new_tokens=int(req.get("max_new_tokens", 256)),
            temperature=float(req.get("temperature", 0.7)),
            top_p=float(req.get("top_p", 0.9)),
        ))
    return outputs


def generate_stream(tok, model, hw, req):
    """Stream tokens for the first conversation; returns the full text."""
    import torch
    from transformers import TextIteratorStreamer

    from .data import render_prompt

    messages = req["conversations"][0]
    text = render_prompt(tok, messages)
    enc = tok(text, return_tensors="pt", add_special_tokens=False).to(hw.device)
    streamer = TextIteratorStreamer(tok, skip_prompt=True, skip_special_tokens=True)
    kwargs = dict(**enc, streamer=streamer, max_new_tokens=int(req.get("max_new_tokens", 256)),
                  pad_token_id=tok.pad_token_id)
    temperature = float(req.get("temperature", 0.7))
    if temperature > 0:
        kwargs.update(do_sample=True, temperature=temperature, top_p=float(req.get("top_p", 0.9)))
    else:
        kwargs.update(do_sample=False)

    def run():
        with torch.no_grad():
            model.generate(**kwargs)

    thread = threading.Thread(target=run)
    thread.start()
    pieces = []
    for piece in streamer:
        if piece:
            pieces.append(piece)
            emit({"ok": True, "token": piece})
    thread.join()
    return "".join(pieces).strip()


def main():
    cache = ModelCache()
    emit({"ok": True, "ready": True})
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            op = req.get("op")
            if op == "ping":
                emit({"ok": True, "pong": True, "loaded": len(cache.items)})
            elif op == "unload":
                cache.clear()
                emit({"ok": True, "loaded": 0})
            elif op == "quit":
                emit({"ok": True, "bye": True})
                break
            elif op == "generate":
                tok, model = cache.get(req)
                if req.get("stream"):
                    output = generate_stream(tok, model, cache.hw, req)
                    emit({"ok": True, "done": True, "output": output, "device": cache.hw.device_str})
                else:
                    outputs = generate_all(tok, model, cache.hw, req)
                    emit({"ok": True, "outputs": outputs, "device": cache.hw.device_str})
            else:
                emit({"ok": False, "error": f"unknown op {op!r}"})
        except Exception as e:  # noqa: BLE001 - report and keep serving
            emit({"ok": False, "error": f"{type(e).__name__}: {e}", "traceback": traceback.format_exc()[-2000:]})


if __name__ == "__main__":
    main()
