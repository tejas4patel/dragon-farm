"""The chunked evaluation loss must equal the plain full-logits loss."""

import torch

from dragonfarm.data import IGNORE_INDEX
from dragonfarm.evaluate_utils import LOSS_CHUNK, token_loss_sum


def _tiny_model():
    from transformers import Qwen2Config, Qwen2ForCausalLM

    torch.manual_seed(0)
    cfg = Qwen2Config(vocab_size=97, hidden_size=32, intermediate_size=64, num_hidden_layers=2,
                      num_attention_heads=4, num_key_value_heads=2, max_position_embeddings=512,
                      tie_word_embeddings=False)
    return Qwen2ForCausalLM(cfg).eval()


def _full_loss(model, input_ids, attention_mask, labels):
    logits = model(input_ids=input_ids, attention_mask=attention_mask).logits[:, :-1].float()
    return torch.nn.functional.cross_entropy(
        logits.reshape(-1, logits.size(-1)), labels[:, 1:].reshape(-1),
        ignore_index=IGNORE_INDEX, reduction="sum")


def _batch(seq_len, batch=2, pad_from=None):
    torch.manual_seed(1)
    ids = torch.randint(5, 97, (batch, seq_len))
    mask = torch.ones_like(ids)
    labels = ids.clone()
    labels[:, : seq_len // 3] = IGNORE_INDEX          # prompt tokens are not scored
    if pad_from is not None:                           # right padding on the second row
        ids[1, pad_from:] = 0
        mask[1, pad_from:] = 0
        labels[1, pad_from:] = IGNORE_INDEX
    return ids, mask, labels


def test_chunked_loss_matches_full_loss_across_chunk_boundaries():
    model = _tiny_model()
    # longer than one chunk, and not a multiple of it, so the last chunk is partial
    ids, mask, labels = _batch(LOSS_CHUNK * 2 + 37)
    got = token_loss_sum(model, ids, mask, labels)
    want = _full_loss(model, ids, mask, labels)
    assert torch.allclose(got, want, rtol=1e-4, atol=1e-3), (float(got), float(want))


def test_chunked_loss_respects_padding_and_ignored_positions():
    model = _tiny_model()
    ids, mask, labels = _batch(300, pad_from=120)
    got = token_loss_sum(model, ids, mask, labels)
    want = _full_loss(model, ids, mask, labels)
    assert torch.allclose(got, want, rtol=1e-4, atol=1e-3), (float(got), float(want))


def test_decoder_path_is_used_for_plain_models():
    from dragonfarm.evaluate_utils import _decoder_and_head

    dec, head = _decoder_and_head(_tiny_model())
    assert dec is not None and head is not None


def test_softcapped_models_take_the_full_logits_path():
    from dragonfarm.evaluate_utils import _decoder_and_head

    model = _tiny_model()
    model.config.final_logit_softcapping = 30.0
    assert _decoder_and_head(model) == (None, None)
    ids, mask, labels = _batch(40)
    got = token_loss_sum(model, ids, mask, labels)   # must still work via the fallback
    assert torch.isfinite(got)
