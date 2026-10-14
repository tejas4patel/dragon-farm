"""Batched generation keeps per-prompt results and survives memory errors.
The fakes stand in for a tokenizer and a model: the model appends a fixed
'reply' token id per prompt, so the decoded text shows which prompt it came
from and whether left padding was handled."""

from dragonfarm import evaluate_utils as E


class FakeTok:
    pad_token_id = 0
    padding_side = "right"
    chat_template = "fake"   # so render_prompt() uses apply_chat_template

    def apply_chat_template(self, messages, tokenize=False, add_generation_prompt=True):
        return messages[-1]["content"]

    def __call__(self, texts, return_tensors="pt", padding=False, add_special_tokens=False):
        import torch

        if isinstance(texts, str):
            texts = [texts]
        ids = [[ord(c) for c in t] for t in texts]
        width = max(len(i) for i in ids)
        rows, masks = [], []
        for i in ids:
            pad = [0] * (width - len(i))
            rows.append(pad + i if self.padding_side == "left" else i + pad)
            masks.append([0] * len(pad) + [1] * len(i) if self.padding_side == "left" else [1] * len(i) + [0] * len(pad))
        enc = {"input_ids": torch.tensor(rows), "attention_mask": torch.tensor(masks)}
        return _Enc(enc)

    def decode(self, ids, skip_special_tokens=True):
        return "".join(chr(int(i)) for i in ids if int(i) != 0)


class _Enc(dict):
    def to(self, device):
        return self


class FakeModel:
    def __init__(self, oom_above=None):
        self.oom_above = oom_above
        self.calls = []

    def generate(self, input_ids=None, attention_mask=None, **kw):
        import torch

        n = input_ids.shape[0]
        self.calls.append(n)
        if self.oom_above is not None and n > self.oom_above:
            raise RuntimeError("CUDA out of memory")
        # reply = last real character of each prompt, upper-cased, then '!'
        last = [int(row[mask.bool()][-1]) for row, mask in zip(input_ids, attention_mask)]
        new = torch.tensor([[ord(chr(c).upper()), ord("!")] for c in last])
        return torch.cat([input_ids, new], dim=1)


def _convs(words):
    return [[{"role": "user", "content": w}] for w in words]


def test_batches_return_one_reply_per_prompt_in_order():
    model, tok = FakeModel(), FakeTok()
    out = E.generate_replies(model, tok, _convs(["ab", "cdef", "g"]), "cpu", temperature=0, batch_size=8)
    assert out == ["B!", "F!", "G!"]
    assert model.calls == [3]
    assert tok.padding_side == "right"     # restored after the batch


def test_long_lists_are_chunked():
    model, tok = FakeModel(), FakeTok()
    out = E.generate_replies(model, tok, _convs(list("abcdefghijk")), "cpu", temperature=0, batch_size=4)
    assert out == [c.upper() + "!" for c in "abcdefghijk"]
    assert model.calls == [4, 4, 3]


def test_a_batch_that_does_not_fit_falls_back_to_single_prompts():
    model, tok = FakeModel(oom_above=1), FakeTok()
    out = E.generate_replies(model, tok, _convs(["ab", "cd", "ef"]), "cpu", temperature=0, batch_size=8)
    assert out == ["B!", "D!", "F!"]
    assert model.calls == [3, 1, 1, 1]
    assert tok.padding_side == "right"


def test_single_prompt_uses_the_plain_path():
    model, tok = FakeModel(), FakeTok()
    assert E.generate_replies(model, tok, _convs(["xy"]), "cpu", temperature=0) == ["Y!"]
    assert E.generate_replies(model, tok, [], "cpu") == []
