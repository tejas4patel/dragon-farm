"""Preference-optimization losses as pure tensor functions.

Kept free of model and trainer code so they can be unit-tested on tiny
tensors. Log-probabilities are per sequence: the sum over the response
tokens of log p(token | prefix), with the prompt masked out.
"""

import torch
import torch.nn.functional as F

from .data import IGNORE_INDEX


def sequence_logps(logits, labels):
    """Sum of label-token log-probs per sequence, and the number of label tokens.

    ``logits`` is (batch, seq, vocab) as returned by the model; ``labels`` is
    (batch, seq) with IGNORE_INDEX on positions that do not count. The shift
    by one position (predict token t from prefix < t) happens here.
    """
    logits = logits[:, :-1, :]
    labels = labels[:, 1:]
    mask = labels != IGNORE_INDEX
    safe = labels.masked_fill(~mask, 0)
    logp = torch.log_softmax(logits.float(), dim=-1).gather(-1, safe.unsqueeze(-1)).squeeze(-1)
    logp = logp * mask
    return logp.sum(-1), mask.sum(-1)


def token_logps(logits, labels):
    """Per-token label log-probs (batch, seq-1) and a float mask of counted positions."""
    logits = logits[:, :-1, :]
    labels = labels[:, 1:]
    mask = (labels != IGNORE_INDEX)
    safe = labels.masked_fill(~mask, 0)
    logp = torch.log_softmax(logits.float(), dim=-1).gather(-1, safe.unsqueeze(-1)).squeeze(-1)
    return logp * mask, mask.float()


def dpo_loss(policy_chosen, policy_rejected, ref_chosen, ref_rejected, beta):
    """Direct Preference Optimization (Rafailov et al., 2023).

    Returns (loss, chosen_rewards, rejected_rewards). Rewards are the implicit
    ``beta * log(pi / pi_ref)`` terms; their difference is what the sigmoid
    loss pushes up.
    """
    chosen_rewards = beta * (policy_chosen - ref_chosen)
    rejected_rewards = beta * (policy_rejected - ref_rejected)
    loss = -F.logsigmoid(chosen_rewards - rejected_rewards)
    return loss.mean(), chosen_rewards.detach(), rejected_rewards.detach()


def orpo_loss(chosen_logps, rejected_logps, chosen_len, rejected_len, lam):
    """Odds Ratio Preference Optimization (Hong et al., 2024).

    Uses length-normalised (mean per token) log-probs. The loss is the NLL of
    the chosen response plus ``lam`` times the odds-ratio term, so no
    reference model is needed. Returns (loss, log_odds, mean_chosen_logp,
    mean_rejected_logp).
    """
    lc = chosen_logps / chosen_len.clamp(min=1)
    lr = rejected_logps / rejected_len.clamp(min=1)
    # log(1 - p) with p = exp(mean logp); clamp keeps log1p away from -inf.
    def log1m_exp(x):
        return torch.log1p(-torch.exp(x).clamp(max=1 - 1e-6))

    log_odds = (lc - lr) - (log1m_exp(lc) - log1m_exp(lr))
    ratio_term = F.logsigmoid(log_odds)
    loss = (-lc) - lam * ratio_term
    return loss.mean(), log_odds.detach(), lc.detach(), lr.detach()
