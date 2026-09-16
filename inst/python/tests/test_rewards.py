import json
import tempfile
from pathlib import Path

from dragonfarm.rewards import RewardSet


def test_exact_contains_numeric():
    rs = RewardSet([{"type": "exact"}, {"type": "contains"}, {"type": "numeric"}])
    total, parts = rs.score("q", "Paris.", "paris")
    assert parts == {"exact": 1.0, "contains": 1.0, "numeric": 0.0}
    assert total == 2.0
    _, parts = rs.score("q", "The total is $1,234.50 today", "1234.5")
    assert parts["numeric"] == 1.0 and parts["exact"] == 0.0
    _, parts = rs.score("q", "anything", None)
    assert parts == {"exact": 0.0, "contains": 0.0, "numeric": 0.0}


def test_regex_json_keyword_length_and_weights():
    rs = RewardSet([
        {"type": "regex", "pattern": r"^T-\d{4}", "weight": 2.0},
        {"type": "json", "keys": ["id", "status"]},
        {"type": "keyword", "words": ["refund", "replace"], "mode": "any"},
        {"type": "length", "max_chars": 20, "name": "short"},
    ])
    total, parts = rs.score("q", 'T-0001 {"id": 1}', None)
    assert parts["regex"] == 1.0
    assert parts["json"] == 0.0            # prose before the JSON makes it invalid
    assert parts["keyword"] == 0.0
    assert parts["short"] == 1.0
    assert total == 2.0 + 0.0 + 0.0 + 1.0

    _, parts = rs.score("q", '```json\n{"id": 1}\n```', None)
    assert parts["json"] == 0.5            # one of two required keys
    _, parts = rs.score("q", "we will replace it", None)
    assert parts["keyword"] == 1.0
    _, parts = rs.score("q", "x" * 40, None)
    assert parts["short"] == 0.0           # twice the cap => zero
    _, parts = rs.score("q", "x" * 30, None)
    assert abs(parts["short"] - 0.5) < 1e-9
    assert rs.names == ["regex", "json", "keyword", "short"]


def test_keyword_all_mode_gives_partial_credit_and_length_min():
    rs = RewardSet([{"type": "keyword", "words": ["a", "b"], "mode": "all"}, {"type": "length", "min_chars": 10}])
    _, parts = rs.score("q", "only a here", None)
    assert parts["keyword"] == 0.5
    assert parts["length"] == 1.0
    _, parts = rs.score("q", "short", None)
    assert parts["length"] == 0.5


def test_custom_reward_file_and_row_fields():
    with tempfile.TemporaryDirectory() as tmp:
        run = Path(tmp)
        (run / "rewards").mkdir()
        (run / "rewards" / "mine.py").write_text(
            "def reward(prompt, completion, reference, row):\n"
            "    return 1.0 if row.get('product', '') in completion else 0.0\n",
            encoding="utf-8",
        )
        rs = RewardSet([{"type": "custom", "file": "rewards/mine.py"}], run_dir=run)
        assert rs.names == ["mine"]
        total, parts = rs.score("q", "Your Ember thermostat is fine", None, {"product": "Ember"})
        assert total == 1.0
        total, _ = rs.score("q", "nope", None, {"product": "Ember"})
        assert total == 0.0


def test_errors_and_score_many():
    try:
        RewardSet([{"type": "nope"}])
        assert False, "expected an error"
    except RuntimeError as e:
        assert "unknown reward type" in str(e)
    try:
        RewardSet([])
        assert False
    except RuntimeError:
        pass
    rs = RewardSet([{"type": "exact"}])
    totals, breakdown = rs.score_many(["q", "q"], ["a", "b"], ["a", "a"], [{}, {}])
    assert totals == [1.0, 0.0]
    assert breakdown == {"exact": [1.0, 0.0]}
