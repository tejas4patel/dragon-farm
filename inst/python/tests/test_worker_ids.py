"""The worker stamps every line it writes for a request with that request's id."""

import contextlib
import io
import json
import sys

from dragonfarm import worker


def run_worker(text):
    out = io.StringIO()
    old_in = sys.stdin
    sys.stdin = io.StringIO(text)
    try:
        with contextlib.redirect_stdout(out):
            worker.main()
    finally:
        sys.stdin = old_in
    return [json.loads(x) for x in out.getvalue().splitlines()]


def test_replies_carry_the_request_id():
    reqs = [{"op": "ping", "id": 7}, {"op": "nope", "id": 8}, {"op": "ping"}, {"op": "quit", "id": 9}]
    ready, pong, err, plain, bye = run_worker("".join(json.dumps(x) + "\n" for x in reqs))
    assert ready == {"ok": True, "ready": True}
    assert pong["pong"] and pong["id"] == 7
    assert err["ok"] is False and err["id"] == 8
    assert plain["pong"] and "id" not in plain
    assert bye["bye"] and bye["id"] == 9


def test_bad_json_does_not_reuse_the_previous_id():
    out = run_worker(json.dumps({"op": "ping", "id": 3}) + "\n{not json\n")
    assert out[1]["id"] == 3
    assert out[2]["ok"] is False and "id" not in out[2]
