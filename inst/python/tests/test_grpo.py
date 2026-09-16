import torch

from dragonfarm.losses import token_logps
from dragonfarm.reinforce import build_batch, group_advantages, grpo_loss
from dragonfarm.data import IGNORE_INDEX


def test_group_advantages_are_zero_mean_and_zero_when_flat():
    adv = group_advantages([1.0, 0.0, 1.0, 0.0])
    assert abs(float(adv.mean())) < 1e-6
    assert float(adv[0]) > 0 > float(adv[1])
    assert group_advantages([0.5, 0.5, 0.5]).abs().sum() == 0
    assert group_advantages([1.0]).abs().sum() == 0


def test_token_logps_shift_and_mask():
    logits = torch.full((1, 4, 3), -10.0)
    logits[0, 1, 2] = 10.0
    logits[0, 2, 2] = 10.0
    labels = torch.tensor([[IGNORE_INDEX, IGNORE_INDEX, 2, 2]])
    lp, mask = token_logps(logits, labels)
    assert lp.shape == (1, 3) and mask.shape == (1, 3)
    assert mask.tolist() == [[0, 1, 1]]
    assert float((lp * mask).sum()) > -1e-3


def test_grpo_loss_prefers_raising_positive_advantage_tokens():
    pol = torch.tensor([[-1.0, -1.0], [-1.0, -1.0]], requires_grad=True)
    ref = torch.tensor([[-1.0, -1.0], [-1.0, -1.0]])
    mask = torch.ones(2, 2)
    adv = torch.tensor([1.0, -1.0])
    loss, kl = grpo_loss(pol, ref, mask, adv, beta=0.1)
    assert abs(kl) < 1e-9                     # identical policies => no KL
    loss.backward()
    # gradient of loss w.r.t. logp is -A/denom: negative for the positive-advantage row
    assert float(pol.grad[0, 0]) < 0 < float(pol.grad[1, 0])
    # a policy that drifted from the reference pays a KL penalty
    drifted = torch.tensor([[-3.0, -3.0], [-3.0, -3.0]])
    _, kl2 = grpo_loss(drifted, ref, mask, torch.zeros(2), beta=0.1)
    assert kl2 > 0


def test_build_batch_masks_prompt_and_pads():
    ids, mask, labels = build_batch([1, 2], [[3, 4, 5], [6]], pad_id=0, device="cpu")
    assert ids.tolist() == [[1, 2, 3, 4, 5], [1, 2, 6, 0, 0]]
    assert mask.tolist() == [[1, 1, 1, 1, 1], [1, 1, 1, 0, 0]]
    assert labels.tolist() == [[IGNORE_INDEX, IGNORE_INDEX, 3, 4, 5], [IGNORE_INDEX, IGNORE_INDEX, 6, IGNORE_INDEX, IGNORE_INDEX]]
