import math

import torch

from dragonfarm.data import IGNORE_INDEX
from dragonfarm.losses import dpo_loss, orpo_loss, sequence_logps


def test_sequence_logps_masks_prompt_and_shifts_by_one():
    # vocab of 3, batch of 1, sequence of 4 tokens; labels mask the first two
    logits = torch.full((1, 4, 3), -10.0)
    # position t predicts token t+1: make token index 2 near-certain at t=1 and t=2
    logits[0, 1, 2] = 10.0
    logits[0, 2, 2] = 10.0
    labels = torch.tensor([[IGNORE_INDEX, IGNORE_INDEX, 2, 2]])
    total, n = sequence_logps(logits, labels)
    assert int(n) == 2
    assert float(total) > -1e-3  # two near-certain tokens => log-prob about 0


def test_dpo_loss_is_log2_when_indifferent_and_falls_when_chosen_preferred():
    pc = torch.tensor([-5.0])
    pr = torch.tensor([-5.0])
    loss, cr, rr = dpo_loss(pc, pr, pc, pr, beta=0.1)
    assert math.isclose(float(loss), math.log(2), rel_tol=1e-6)
    assert float(cr) == 0.0 and float(rr) == 0.0

    better, _, _ = dpo_loss(torch.tensor([-3.0]), pr, pc, pr, beta=0.1)
    worse, _, _ = dpo_loss(torch.tensor([-7.0]), pr, pc, pr, beta=0.1)
    assert float(better) < math.log(2) < float(worse)


def test_dpo_beta_scales_rewards():
    pc, pr = torch.tensor([-2.0]), torch.tensor([-4.0])
    _, cr1, _ = dpo_loss(pc, pr, torch.tensor([-3.0]), pr, beta=1.0)
    _, cr5, _ = dpo_loss(pc, pr, torch.tensor([-3.0]), pr, beta=0.5)
    assert math.isclose(float(cr1), 1.0) and math.isclose(float(cr5), 0.5)


def test_orpo_loss_prefers_chosen_and_uses_mean_logps():
    lens = torch.tensor([10.0])
    # chosen mean logp -0.5, rejected mean logp -2.0
    loss_good, log_odds, lc, lr = orpo_loss(torch.tensor([-5.0]), torch.tensor([-20.0]), lens, lens, lam=0.1)
    assert math.isclose(float(lc), -0.5) and math.isclose(float(lr), -2.0)
    assert float(log_odds) > 0
    # same chosen NLL but rejected now equally likely => larger loss
    loss_flat, log_odds_flat, _, _ = orpo_loss(torch.tensor([-5.0]), torch.tensor([-5.0]), lens, lens, lam=0.1)
    assert math.isclose(float(log_odds_flat), 0.0, abs_tol=1e-6)
    assert float(loss_good) < float(loss_flat)
    # with lam = 0 the loss is exactly the chosen NLL
    loss_nll, _, _, _ = orpo_loss(torch.tensor([-5.0]), torch.tensor([-20.0]), lens, lens, lam=0.0)
    assert math.isclose(float(loss_nll), 0.5, rel_tol=1e-6)


def test_orpo_handles_zero_length_and_certain_sequences():
    zero = torch.tensor([0.0])
    loss, log_odds, lc, lr = orpo_loss(torch.tensor([0.0]), torch.tensor([0.0]), zero, zero, lam=0.1)
    assert torch.isfinite(loss) and torch.isfinite(log_odds)
