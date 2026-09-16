#' Serve a run's model with Ollama
#'
#' Merges the adapter into the base model (if not done already) and
#' registers the result with Ollama, which imports safetensors directly for
#' the Llama, Qwen2, Gemma, and related families. Ollama then serves it
#' quickly on the CPU or GPU of whatever machine it runs on, and the returned
#' backend points [dragon_generate()] and [dragon_chat()] at it.
#'
#' Needs the `ollama` command on the PATH and the Ollama service running.
#'
#' @param run A `dragon_run`, or a merged model directory.
#' @param name Model name to register. Defaults to `dragonfarm-<run id>`.
#' @param quantize Optional Ollama quantization such as `"q8_0"` or `"q4_K_M"`
#'   to shrink the served model.
#' @param ollama Path to the `ollama` executable.
#' @return A `dragon_backend` for the served model.
#' @export
#' @examples
#' \dontrun{
#' backend <- dragon_serve_ollama(run)
#' options(dragonfarm.backend = backend)
#' dragon_chat(run)$say("Hello")
#' }
dragon_serve_ollama <- function(run, name = NULL, quantize = NULL, ollama = Sys.which("ollama")) {
  if (!nzchar(ollama)) {
    cli::cli_abort(c("Ollama was not found on the PATH.", "i" = "Install it from {.url https://ollama.com/download}, then try again."))
  }
  merged <- if (inherits(run, "dragon_run") || (is.character(run) && file.exists(file.path(run, "config.json")) && !file.exists(file.path(run, "model.safetensors")))) {
    r <- dragon_run(run)
    dir <- run_path(r, "merged")
    if (!file.exists(file.path(dir, "config.json"))) dragon_merge(r) else dir
  } else {
    run
  }
  merged <- normalizePath(merged, winslash = "/")
  name <- name %||% paste0("dragonfarm-", if (inherits(run, "dragon_run")) slugify(run$id) else slugify(basename(merged)))
  modelfile <- file.path(merged, "Modelfile")
  writeLines(ollama_modelfile(merged), modelfile)
  args <- c("create", name, "-f", modelfile)
  if (!is.null(quantize)) args <- c(args, "--quantize", quantize)
  cli::cli_alert_info("Registering {.val {name}} with Ollama from {.path {merged}}.")
  res <- processx::run(ollama, args, error_on_status = FALSE, windows_hide_window = TRUE)
  if (res$status != 0) {
    cli::cli_abort(c("{.code ollama create} failed (exit status {res$status}).",
                     "x" = "{paste(utils::tail(strsplit(paste(res$stdout, res$stderr), '\n')[[1]], 10), collapse = '\n')}"))
  }
  cli::cli_alert_success("Ollama serves {.val {name}}. Try {.code dragon_generate(run, \"Hello\", backend = dragon_backend_ollama(\"{name}\"))}.")
  dragon_backend_ollama(name)
}

ollama_modelfile <- function(merged_dir) {
  c(
    paste0("FROM ", merged_dir),
    "# Made by dragonfarm. The chat template comes from the model's tokenizer.",
    "PARAMETER temperature 0.7"
  )
}
