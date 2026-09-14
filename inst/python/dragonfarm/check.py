"""Print a JSON report of the Python environment. Used by dragon_check()."""

import json
import platform
import sys


def main():
    import torch
    import transformers
    import peft

    from .hardware import describe

    info = {
        "python": platform.python_version(),
        "executable": sys.executable,
        "transformers": transformers.__version__,
        "peft": peft.__version__,
    }
    info.update(describe())
    try:
        import bitsandbytes  # noqa: F401

        info["bitsandbytes"] = True
    except Exception:
        info["bitsandbytes"] = False
    print(json.dumps(info))


if __name__ == "__main__":
    main()
