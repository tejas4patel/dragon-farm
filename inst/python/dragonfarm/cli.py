"""Command-line interface: ``dragonfarm <command> ...``.

Each command delegates to the same entry point ``python -m
dragonfarm.<module>`` already uses (train.py, generate.py, pack_results.py,
check.py) -- both R's own subprocess calls and this CLI run the identical
code, so behaviour never drifts between the two. This module just gives
people using the package directly from Python or a shell a friendlier,
single command to remember.
"""

import argparse
import sys


def build_parser():
    ap = argparse.ArgumentParser(
        prog="dragonfarm",
        description="Fine-tune small language models with LoRA, from a run directory.",
    )
    sub = ap.add_subparsers(dest="command", required=True)

    sub.add_parser("check", help="Print the Python environment and hardware as JSON.")

    p_train = sub.add_parser("train", help="Run one post-training stage on an existing run directory.")
    p_train.add_argument("--run-dir", required=True, help="A directory containing config.json and the mapped data files.")
    p_train.add_argument("--resume", action="store_true", help="Resume from the latest checkpoint instead of starting over.")

    p_generate = sub.add_parser("generate", help="Generate replies from a request JSON file.")
    p_generate.add_argument("--request", required=True, help="JSON file: model, adapter, prompts, and generation settings.")
    p_generate.add_argument("--out", required=True, help="Where to write the JSON list of replies.")

    p_pack = sub.add_parser("pack", help="Zip a run's adapter, config, and samples for import elsewhere.")
    p_pack.add_argument("run_dir")
    p_pack.add_argument("--out", default=None, help="Output zip path. Defaults to dragonfarm-results-<run id>.zip.")

    return ap


def main(argv=None):
    argv = sys.argv[1:] if argv is None else list(argv)
    a = build_parser().parse_args(argv)

    if a.command == "check":
        from . import check
        check.main()
    elif a.command == "train":
        from . import train
        rest = ["--run-dir", a.run_dir]
        if a.resume:
            rest.append("--resume")
        train.main(rest)
    elif a.command == "generate":
        from . import generate
        generate.main(["--request", a.request, "--out", a.out])
    elif a.command == "pack":
        from . import pack_results
        rest = [a.run_dir]
        if a.out:
            rest.extend(["--out", a.out])
        pack_results.main(rest)


if __name__ == "__main__":
    main()
