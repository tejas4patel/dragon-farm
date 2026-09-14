"""Minimal test runner for environments without pytest.

Usage: PYTHONPATH=inst/python python inst/python/tests/run.py
"""

import importlib
import pathlib
import sys
import traceback

here = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(here))

failed = 0
for path in sorted(here.glob("test_*.py")):
    mod = importlib.import_module(path.stem)
    for name in sorted(dir(mod)):
        if name.startswith("test_"):
            try:
                getattr(mod, name)()
                print(f"ok   {path.stem}.{name}")
            except Exception:
                failed += 1
                print(f"FAIL {path.stem}.{name}")
                traceback.print_exc()
print(f"{failed} failure(s)")
sys.exit(1 if failed else 0)
