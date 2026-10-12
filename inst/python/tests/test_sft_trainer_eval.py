"""The SFT trainer's evaluation step must use the chunked loss and agree with the plain loss."""

import tempfile

import torch

from dragonfarm.data import IGNORE_INDEX
from dragonfarm.train import make_sft_trainer_class
from test_evaluate_utils import _batch, _full_loss, _tiny_model


def test_sft_trainer_prediction_step_matches_mean_token_loss():
    from transformers import TrainingArguments

    model = _tiny_model()
    ids, mask, labels = _batch(300, pad_from=120)
    with tempfile.TemporaryDirectory() as tmp:
        targs = TrainingArguments(output_dir=tmp, per_device_eval_batch_size=2, report_to=[], use_cpu=True)
        trainer = make_sft_trainer_class()(model=model, args=targs)
        loss, logits, lab = trainer.prediction_step(
            model, {"input_ids": ids, "attention_mask": mask, "labels": labels}, prediction_loss_only=True)
    assert logits is None and lab is None
    n = int((labels[:, 1:] != IGNORE_INDEX).sum())
    want = _full_loss(model, ids, mask, labels) / n
    assert torch.allclose(loss, want, rtol=1e-4, atol=1e-3), (float(loss), float(want))
