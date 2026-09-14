"""Python side of the dragonfarm R package.

Every module here is launched by R as ``python -m dragonfarm.<module>`` in a
subprocess. The only interface with R is the run directory: R writes
``config.json`` and ``data/*.jsonl``; this package writes ``status.json``,
``progress.jsonl``, checkpoints, the adapter, and evaluation output.
"""

__version__ = "0.1.0"
