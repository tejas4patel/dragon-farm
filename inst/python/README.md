# dragonfarm

Fine-tune small language models (roughly 100M to 3B parameters) with LoRA,
from a CLI or a few lines of Python. This is the Python side of
[dragon-farm](https://github.com/tejas4patel/dragon-farm), which also ships
an R package with a drag-and-drop Shiny app; the two share this same code,
so a run started from R can be inspected or continued from Python and back.

## Install

```bash
pip install dragonfarm
```

## Command line

```bash
# Environment and hardware, as JSON
dragonfarm check

# Run one post-training stage (sft, preference optimization, or GRPO,
# chosen by the run directory's config.json) on a run someone already set up
dragonfarm train --run-dir path/to/run

# Generate replies from a request file: {"model": ..., "adapter": ...,
# "prompts": [...], ...} in, {"outputs": [...]} out
dragonfarm generate --request request.json --out reply.json

# Zip a finished run's adapter, config, and samples for import elsewhere
dragonfarm pack path/to/run
```

Run `dragonfarm <command> --help` for each command's full set of flags.

## Python API

A run directory (the same one the CLI and the R package both read and
write) can be inspected without touching torch or transformers at all:

```python
from dragonfarm.api import Run, runs

run = Run("dragonfarm_runs/20260101-120000-my-model")
run.state          # "running", "succeeded", "failed", ...
run.stage          # "sft", "prefer", or "reinforce"
run.config         # the full config.json as a dict
run.progress()     # one row per logged training step
run.log(tail=20)   # the last 20 lines of the trainer's output

for r in runs("dragonfarm_runs"):
    print(r.id, r.stage, r.state)
```

## What a run directory holds

Every run is a plain directory of JSON and JSONL files: `config.json`
(model, LoRA, and stage settings), `data/train.jsonl` and
`data/eval.jsonl`, `status.json`, `progress.jsonl`, `log.txt`, and, once
training finishes, `adapter/` (the LoRA weights) and optionally `merged/`
(the adapter folded into the base model). Nothing here is specific to R or
to Python; either can create, read, or continue a run.

## License

MIT
