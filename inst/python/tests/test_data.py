"""Run with: python -m pytest inst/python/tests  (needs PYTHONPATH=inst/python)"""

import torch

from dragonfarm.data import IGNORE_INDEX, PadCollator, encode_example, fallback_prompt


class FakeTok:
    """Character-level tokenizer with no chat template."""

    chat_template = None
    eos_token = "<eos>"
    pad_token_id = 0

    def __call__(self, text, add_special_tokens=False, **kw):
        ids = [ord(c) for c in text]
        return {"input_ids": ids}


def test_labels_mask_prompt_only():
    tok = FakeTok()
    messages = [{"role": "user", "content": "hi"}, {"role": "assistant", "content": "yo"}]
    enc = encode_example(tok, messages, max_len=4096)
    prompt_text = fallback_prompt(messages[:-1]) + "\n### Assistant:\n"
    n_prompt = len(prompt_text)
    assert enc["labels"][:n_prompt] == [IGNORE_INDEX] * n_prompt
    assert enc["labels"][n_prompt:] == enc["input_ids"][n_prompt:]
    assert "".join(chr(i) for i in enc["input_ids"]).endswith("yo\n<eos>")


def test_truncated_response_is_skipped():
    tok = FakeTok()
    messages = [{"role": "user", "content": "x" * 50}, {"role": "assistant", "content": "y"}]
    assert encode_example(tok, messages, max_len=10) is None


def test_collator_pads():
    col = PadCollator(pad_token_id=0)
    batch = col([
        {"input_ids": [1, 2, 3], "labels": [-100, 2, 3]},
        {"input_ids": [4], "labels": [4]},
    ])
    assert batch["input_ids"].shape == (2, 3)
    assert batch["attention_mask"].tolist() == [[1, 1, 1], [1, 0, 0]]
    assert batch["labels"].tolist()[1] == [4, IGNORE_INDEX, IGNORE_INDEX]
    assert batch["input_ids"].dtype == torch.long
