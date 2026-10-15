"""The chunked training loss must equal the model's own loss, in value and in
gradients, with and without num_items_in_batch (gradient accumulation). A
tiny randomly initialised model keeps this fast and offline."""

import torch

from dragonfarm.evaluate_utils import chunked_train_loss


def _tiny_model():
    from transformers import Qwen2Config, Qwen2ForCausalLM

    torch.manual_seed(0)
    cfg = Qwen2Config(vocab_size=512, hidden_size=32, intermediate_size=64, num_hidden_layers=2,
                      num_attention_heads=4, num_key_value_heads=2, max_position_embeddings=256,
                      tie_word_embeddings=True)
    return Qwen2ForCausalLM(cfg).float()


def _batch():
    torch.manual_seed(1)
    ids = torch.randint(0, 512, (2, 90))
    mask = torch.ones_like(ids)
    mask[1, 70:] = 0
    labels = ids.clone()
    labels[:, :30] = -100
    labels[1, 70:] = -100
    return ids, mask, labels


def _grads(model):
    return {n: p.grad.detach().clone() for n, p in model.named_parameters() if p.grad is not None}


def test_chunked_loss_matches_the_model_loss_and_gradients():
    model = _tiny_model()
    ids, mask, labels = _batch()
    for nib in (None, torch.tensor(150)):
        model.zero_grad()
        kw = {} if nib is None else {"num_items_in_batch": nib}
        ref = model(input_ids=ids, attention_mask=mask, labels=labels, **kw).loss
        ref.backward()
        g_ref = _grads(model)
        model.zero_grad()
        got = chunked_train_loss(model, ids, mask, labels, num_items_in_batch=nib, chunk=16)
        got.backward()
        g = _grads(model)
        assert abs(got.item() - ref.item()) < 1e-5, (got.item(), ref.item())
        assert set(g) == set(g_ref)
        for k in g:
            assert torch.allclose(g[k], g_ref[k], atol=1e-6, rtol=1e-4), k


def test_models_that_cannot_be_split_return_none():
    class Opaque(torch.nn.Module):
        def forward(self, **kw):
            raise AssertionError("not called")

    ids, mask, labels = _batch()
    assert chunked_train_loss(Opaque(), ids, mask, labels) is None
