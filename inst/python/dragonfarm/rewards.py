"""Verifiable rewards for reinforcement learning.

A reward spec is a dict from config.json: {"type": ..., "weight": ..., plus
type-specific fields}. build_rewards() turns a list of specs into callables
of (prompt, completion, reference, row) -> float in [0, 1] (or any float for
custom rewards), and score() combines them with their weights.

Kept free of torch so the functions can be unit-tested directly.
"""

import importlib.util
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path


def _normalize(text):
    text = (text or "").strip().lower()
    text = re.sub(r"\s+", " ", text)
    text = re.sub(r"[^\w\s]+$", "", text)
    return text


def _unfence(text):
    text = (text or "").strip()
    m = re.match(r"^```[a-zA-Z]*\s*\n?([\s\S]*?)\n?```$", text)
    return m.group(1) if m else text


def _last_number(text):
    nums = re.findall(r"-?\d[\d,]*\.?\d*", text or "")
    if not nums:
        return None
    try:
        return float(nums[-1].replace(",", ""))
    except ValueError:
        return None


def reward_exact(prompt, completion, reference, row, spec):
    return 1.0 if reference is not None and _normalize(completion) == _normalize(reference) else 0.0


def reward_contains(prompt, completion, reference, row, spec):
    ref = _normalize(reference)
    return 1.0 if ref and ref in _normalize(completion) else 0.0


def reward_numeric(prompt, completion, reference, row, spec):
    a, b = _last_number(completion), _last_number(reference)
    if a is None or b is None:
        return 0.0
    tol = max(1e-6, abs(b) * 1e-6)
    return 1.0 if abs(a - b) <= tol else 0.0


def reward_regex(prompt, completion, reference, row, spec):
    flags = 0 if spec.get("case_sensitive") else re.IGNORECASE
    return 1.0 if re.search(spec["pattern"], completion or "", flags) else 0.0


def reward_json(prompt, completion, reference, row, spec):
    try:
        obj = json.loads(_unfence(completion))
    except Exception:
        return 0.0
    keys = spec.get("keys") or []
    if keys:
        if not isinstance(obj, dict):
            return 0.0
        present = sum(1 for k in keys if k in obj)
        return present / len(keys)
    return 1.0


def reward_length(prompt, completion, reference, row, spec):
    """1 inside [min_chars, max_chars], falling linearly to 0 at twice the overshoot."""
    n = len(completion or "")
    lo = spec.get("min_chars") or 0
    hi = spec.get("max_chars")
    if n < lo:
        return max(0.0, n / lo) if lo else 1.0
    if hi is not None and n > hi:
        return max(0.0, 1.0 - (n - hi) / max(hi, 1))
    return 1.0


def reward_keyword(prompt, completion, reference, row, spec):
    words = [w.lower() for w in spec.get("words") or []]
    if not words:
        return 0.0
    text = (completion or "").lower()
    hits = [w in text for w in words]
    if spec.get("mode", "any") == "all":
        return 1.0 if all(hits) else sum(hits) / len(hits)
    return 1.0 if any(hits) else 0.0


def reward_command(prompt, completion, reference, row, spec):
    """Run a command against the completion; common for code tasks, where
    the command is a test suite or a linter and the reward is whether it
    passed. Never runs through a shell, so the completion's own text can't
    inject anything into the command line: it either goes to the command's
    stdin (the default), or, with ``"input": "file"``, is written to a
    temp file whose path replaces every ``"{completion_file}"`` token in
    ``command``.

    ``"score_from"``: ``"exit_code"`` (the default; 0 -> 1.0, anything else
    -> 0.0) or ``"stdout"`` (the last number printed, linearly rescaled
    from ``["min", "max"]`` -- default 0 to 1 -- and clamped to that range).
    """
    cmd = spec.get("command")
    if not cmd:
        raise RuntimeError("a 'command' reward needs a 'command' field")
    if isinstance(cmd, str):
        cmd = [cmd]
    timeout = float(spec.get("timeout", 30))
    tmp_path = None
    try:
        if spec.get("input") == "file":
            fd, tmp_path = tempfile.mkstemp(suffix=spec.get("suffix", ".txt"))
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(completion or "")
            cmd = [str(c).replace("{completion_file}", tmp_path) for c in cmd]
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        else:
            proc = subprocess.run(cmd, input=completion or "", capture_output=True, text=True, timeout=timeout)
    except (subprocess.TimeoutExpired, OSError):
        return 0.0
    finally:
        if tmp_path is not None:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass

    if spec.get("score_from") == "stdout":
        n = _last_number(proc.stdout)
        if n is None:
            return 0.0
        lo, hi = float(spec.get("min", 0.0)), float(spec.get("max", 1.0))
        if hi == lo:
            return 0.0
        return max(0.0, min(1.0, (n - lo) / (hi - lo)))
    return 1.0 if proc.returncode == 0 else 0.0


def _load_custom(spec, run_dir):
    path = Path(spec["file"])
    if not path.is_absolute():
        path = Path(run_dir) / path
    module_spec = importlib.util.spec_from_file_location(f"dragonfarm_reward_{path.stem}", path)
    module = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(module)
    fn = getattr(module, spec.get("function", "reward"), None)
    if fn is None:
        raise RuntimeError(f"custom reward file {path} has no function named {spec.get('function', 'reward')}")

    def call(prompt, completion, reference, row, _spec):
        return float(fn(prompt, completion, reference, row))

    return call


BUILTIN = {
    "exact": reward_exact,
    "contains": reward_contains,
    "numeric": reward_numeric,
    "regex": reward_regex,
    "json": reward_json,
    "length": reward_length,
    "keyword": reward_keyword,
    "command": reward_command,
}


class RewardSet:
    def __init__(self, specs, run_dir=None):
        if not specs:
            raise RuntimeError("at least one reward is required")
        self.items = []
        for i, spec in enumerate(specs):
            kind = spec.get("type")
            name = spec.get("name") or (kind if kind != "custom" else Path(spec["file"]).stem)
            weight = float(spec.get("weight", 1.0))
            if kind == "custom":
                fn = _load_custom(spec, run_dir)
            elif kind in BUILTIN:
                fn = BUILTIN[kind]
            else:
                raise RuntimeError(f"unknown reward type {kind!r}")
            self.items.append((name, weight, fn, spec))

    @property
    def names(self):
        return [name for name, _, _, _ in self.items]

    def score(self, prompt, completion, reference=None, row=None):
        """Weighted total and a per-reward breakdown."""
        total = 0.0
        parts = {}
        for name, weight, fn, spec in self.items:
            try:
                value = float(fn(prompt, completion, reference, row or {}, spec))
            except Exception:
                value = 0.0
            parts[name] = value
            total += weight * value
        return total, parts

    def score_many(self, prompts, completions, references, rows):
        totals, breakdown = [], {name: [] for name in self.names}
        for p, c, r, row in zip(prompts, completions, references, rows):
            t, parts = self.score(p, c, r, row)
            totals.append(t)
            for name in self.names:
                breakdown[name].append(parts[name])
        return totals, breakdown
