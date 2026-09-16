import torch

from dragonfarm.data import IGNORE_INDEX, PairCollator, encode_pair


class FakeTok:
    """Character-level tokenizer without a chat template, for deterministic tests."""

    eos_token = "<eos>"
    pad_token_id = 0
    chat_template = None

    def __call__(self, text, add_special_tokens=False, **kw):
        return {"input_ids": [ord(c) % 250 + 1 for c in text]}


def test_encode_pair_masks_prompt_and_keeps_both_replies():
    tok = FakeTok()
    prompt = [{"role": "user", "content": "hi"}]
    enc = encode_pair(tok, prompt, "good", "worse", max_len=512)
    assert enc is not None
    for side in ("chosen", "rejected"):
        ids, labels = enc[f"{side}_input_ids"], enc[f"{side}_labels"]
        assert len(ids) == len(labels)
        n_masked = sum(1 for l in labels if l == IGNORE_INDEX)
        assert 0 < n_masked < len(labels)
    # the rejected reply is one character longer than the chosen one
    assert len(enc["rejected_input_ids"]) == len(enc["chosen_input_ids"]) + 1


def test_encode_pair_returns_none_when_prompt_fills_the_window():
    tok = FakeTok()
    prompt = [{"role": "user", "content": "x" * 100}]
    assert encode_pair(tok, prompt, "a", "b", max_len=20) is None


def test_pair_collator_pads_each_side_to_its_own_width():
    batch = [
        {"chosen_input_ids": [5, 6, 7], "chosen_labels": [IGNORE_INDEX, 6, 7],
         "rejected_input_ids": [5, 8], "rejected_labels": [IGNORE_INDEX, 8]},
        {"chosen_input_ids": [5], "chosen_labels": [5],
         "rejected_input_ids": [5, 8, 9, 10], "rejected_labels": [IGNORE_INDEX, 8, 9, 10]},
    ]
    out = PairCollator(pad_token_id=0)(batch)
    assert out["chosen_input_ids"].shape == (2, 3)
    assert out["rejected_input_ids"].shape == (2, 4)
    assert out["chosen_attention_mask"].tolist() == [[1, 1, 1], [1, 0, 0]]
    assert out["chosen_labels"][1].tolist() == [5, IGNORE_INDEX, IGNORE_INDEX]
    assert out["rejected_input_ids"][0].tolist() == [5, 8, 0, 0]
    assert all(v.dtype == torch.long for v in out.values())
