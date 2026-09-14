#' Generate replies from a fine-tuned model
#'
#' Loads the model in a short-lived Python process, so each call pays a few
#' seconds of model-loading time. Pass several prompts at once to amortize it.
#'
#' @param x A `dragon_run`, a run directory, an adapter directory, a merged
#'   model directory, or a Hugging Face model id.
#' @param prompt One or more user prompts.
#' @param system Optional system prompt.
#' @param max_new_tokens Maximum tokens to generate per reply.
#' @param temperature Sampling temperature. `0` means greedy decoding.
#' @param top_p Nucleus sampling threshold.
#' @param base Ignore the adapter and generate from the base model. Useful for
#'   before-and-after comparisons.
#' @return A character vector, one reply per prompt.
#' @export
dragon_generate <- function(x, prompt, system = NULL, max_new_tokens = 256,
                            temperature = 0.7, top_p = 0.9, base = FALSE) {
  if (!is.character(prompt) || !length(prompt)) cli::cli_abort("{.arg prompt} must be a character vector.")
  target <- resolve_target(x)
  req <- list(
    model = target$model,
    adapter = if (!base) target$adapter,
    prompts = as.list(prompt),
    system = system,
    max_new_tokens = as.integer(max_new_tokens),
    temperature = temperature,
    top_p = top_p,
    trust_remote_code = isTRUE(target$trust_remote_code)
  )
  req_file <- tempfile("dragon-req-", fileext = ".json")
  out_file <- tempfile("dragon-out-", fileext = ".json")
  on.exit(unlink(c(req_file, out_file)))
  write_json(req, req_file)
  res <- run_python("dragonfarm.generate", c("--request", req_file, "--out", out_file))
  if (res$status != 0) python_failure_message(res, "Generation")
  out <- read_json(out_file)
  vapply(out$outputs, as.character, character(1))
}

# Work out base model id and adapter path from whatever the user passed.
resolve_target <- function(x) {
  if (inherits(x, "dragon_run")) {
    cfg <- run_config(x)
    adapter <- run_path(x, "adapter")
    if (!file.exists(file.path(adapter, "adapter_config.json"))) {
      st <- dragon_status(x)
      cli::cli_abort("Run {.strong {x$id}} has no saved adapter yet (state: {st$state}).")
    }
    return(list(model = cfg$model$id, adapter = adapter, trust_remote_code = cfg$model$trust_remote_code))
  }
  check_string(x, "x")
  if (dir.exists(x)) {
    x <- normalizePath(x, winslash = "/")
    if (file.exists(file.path(x, "config.json")) && file.exists(file.path(x, "adapter", "adapter_config.json"))) {
      return(resolve_target(dragon_run(x)))
    }
    if (file.exists(file.path(x, "adapter_config.json"))) {
      base <- read_json(file.path(x, "adapter_config.json"))$base_model_name_or_path
      return(list(model = base, adapter = x, trust_remote_code = FALSE))
    }
    if (file.exists(file.path(x, "config.json"))) {
      return(list(model = x, adapter = NULL, trust_remote_code = FALSE))
    }
    cli::cli_abort("{.path {x}} is neither a run, an adapter, nor a model directory.")
  }
  list(model = x, adapter = NULL, trust_remote_code = FALSE)
}
