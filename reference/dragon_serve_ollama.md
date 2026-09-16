# Serve a run's model with Ollama

Merges the adapter into the base model (if not done already) and
registers the result with Ollama, which imports safetensors directly for
the Llama, Qwen2, Gemma, and related families. Ollama then serves it
quickly on the CPU or GPU of whatever machine it runs on, and the
returned backend points
[`dragon_generate()`](https://dragonfarm.dev/reference/dragon_generate.md)
and [`dragon_chat()`](https://dragonfarm.dev/reference/dragon_chat.md)
at it.

## Usage

``` r
dragon_serve_ollama(
  run,
  name = NULL,
  quantize = NULL,
  ollama = Sys.which("ollama")
)
```

## Arguments

- run:

  A `dragon_run`, or a merged model directory.

- name:

  Model name to register. Defaults to `dragonfarm-<run id>`.

- quantize:

  Optional Ollama quantization such as `"q8_0"` or `"q4_K_M"` to shrink
  the served model.

- ollama:

  Path to the `ollama` executable.

## Value

A `dragon_backend` for the served model.

## Details

Needs the `ollama` command on the PATH and the Ollama service running.

## Examples

``` r
if (FALSE) { # \dontrun{
backend <- dragon_serve_ollama(run)
options(dragonfarm.backend = backend)
dragon_chat(run)$say("Hello")
} # }
```
