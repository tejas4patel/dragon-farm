#' Python requirements used by dragonfarm
#'
#' The package declares these with [reticulate::py_require()] when it is
#' loaded. You normally never call this yourself.
#'
#' @return A list with `packages` (pip requirement strings) and `python_version`.
#' @export
#' @examples
#' dragon_python_requirements()
dragon_python_requirements <- function() {
  list(
    packages = c(
      "torch>=2.4",
      "transformers>=4.46",
      "peft>=0.13",
      "accelerate>=1.0",
      "safetensors>=0.4",
      "numpy",
      "sentencepiece",
      "protobuf"
    ),
    python_version = ">=3.10,<3.14"
  )
}

# Path to the Python interpreter that has the declared requirements.
# Cached per session. Set DRAGONFARM_PYTHON to bypass reticulate entirely and
# use an interpreter you manage yourself.
dragon_python <- function(quiet = FALSE) {
  if (!is.null(the$python) && file.exists(the$python)) return(the$python)
  override <- Sys.getenv("DRAGONFARM_PYTHON", unset = "")
  if (nzchar(override)) {
    if (!file.exists(override)) cli::cli_abort("DRAGONFARM_PYTHON points to {.path {override}}, which does not exist.")
    the$python <- override
    return(override)
  }
  if (!quiet) {
    cli::cli_alert_info("Preparing the Python environment. The first time this downloads torch and transformers (2 to 3 GB) and can take several minutes.")
  }
  if (configure_torch_index() && !quiet) {
    cli::cli_alert_info("NVIDIA GPU detected: using the CUDA build of torch from {.url {Sys.getenv('UV_EXTRA_INDEX_URL')}}. Set {.envvar DRAGONFARM_TORCH_INDEX} to \"\" to use the CPU build instead.")
  }
  reticulate::py_config()
  py <- reticulate::py_exe()
  if (is.null(py) || !nzchar(py)) cli::cli_abort("reticulate could not report a Python executable.")
  the$python <- py
  py
}

python_source_dir <- function() {
  d <- system.file("python", package = "dragonfarm")
  if (!nzchar(d)) cli::cli_abort("Bundled Python sources not found. Is dragonfarm installed correctly?")
  d
}

python_env <- function() {
  c(
    "current",
    PYTHONPATH = python_source_dir(),
    DRAGONFARM_MANAGED = "1",
    PYTHONUNBUFFERED = "1",
    PYTHONIOENCODING = "utf-8",
    HF_HUB_DISABLE_PROGRESS_BARS = "1",
    TQDM_DISABLE = "1",
    TOKENIZERS_PARALLELISM = "false"
  )
}

# Run a dragonfarm Python module to completion and return the processx result.
run_python <- function(module, args = character(), timeout = Inf, echo = FALSE) {
  py <- dragon_python()
  processx::run(
    py, c("-m", module, args),
    env = python_env(), error_on_status = FALSE, timeout = timeout,
    echo = echo, windows_hide_window = TRUE
  )
}

python_failure_message <- function(res, what) {
  err <- trimws(res$stderr)
  tail <- paste(utils::tail(strsplit(err, "\n")[[1]], 15), collapse = "\n")
  cli::cli_abort(c(
    "{what} failed (exit status {res$status}).",
    "i" = "Last lines of Python output:",
    " " = tail
  ))
}

#' Check the Python environment and hardware
#'
#' Prepares the Python environment if needed, then reports the interpreter,
#' library versions, the compute device that training will use, available
#' GPU memory, and whether a Hugging Face token is configured. Run this first
#' on a new machine.
#'
#' @return Invisibly, a list of the collected facts.
#' @export
#' @examples
#' \dontrun{
#' dragon_check()
#' }
dragon_check <- function() {
  cli::cli_h1("dragonfarm environment check")
  result <- list(ok = FALSE)

  py <- tryCatch(dragon_python(), error = function(e) {
    cli::cli_alert_danger("Python environment could not be prepared: {conditionMessage(e)}")
    NULL
  })
  if (is.null(py)) return(invisible(result))
  result$python <- py
  cli::cli_alert_success("Python: {.path {py}}")

  res <- processx::run(py, c("-m", "dragonfarm.check"), env = python_env(),
                       error_on_status = FALSE, windows_hide_window = TRUE)
  if (res$status != 0) {
    cli::cli_alert_danger("Importing the Python libraries failed.")
    cli::cli_verbatim(utils::tail(strsplit(res$stderr, "\n")[[1]], 12))
    result$error <- res$stderr
    return(invisible(result))
  }
  info <- jsonlite::fromJSON(res$stdout, simplifyVector = TRUE)
  result <- c(result, info)
  the$hardware <- info

  cli::cli_alert_success("torch {info$torch} \u00b7 transformers {info$transformers} \u00b7 peft {info$peft}")
  dev <- info$device
  if (identical(dev, "cuda")) {
    cli::cli_alert_success("Device: CUDA {info$cuda_version} \u00b7 {info$device_name} \u00b7 {round(info$vram_gb, 1)} GB \u00b7 bf16 {if (isTRUE(info$bf16)) 'yes' else 'no'}")
  } else if (identical(dev, "mps")) {
    cli::cli_alert_success("Device: Apple MPS")
  } else {
    cli::cli_alert_warning("Device: CPU only. Training works but is slow; stick to models of 360M parameters or fewer.")
    diagnosis <- cpu_diagnosis(info$torch_cuda_build, nvidia_driver_version())
    result$cpu_reason <- diagnosis$reason
    cli::cli_bullets(diagnosis$lines)
  }
  if (hf_token_present()) {
    cli::cli_alert_success("Hugging Face token found (needed for gated models such as Gemma and Llama).")
  } else {
    cli::cli_alert_info("No Hugging Face token. Open models work; gated ones need {.envvar HF_TOKEN}.")
  }
  result$ok <- TRUE
  invisible(result)
}

# Cached hardware info for the app; runs the check quietly if needed.
hardware_info <- function() {
  if (!is.null(the$hardware)) return(the$hardware)
  py <- tryCatch(dragon_python(quiet = TRUE), error = function(e) NULL)
  if (is.null(py)) return(NULL)
  res <- processx::run(py, c("-m", "dragonfarm.check"), env = python_env(),
                       error_on_status = FALSE, windows_hide_window = TRUE)
  if (res$status != 0) return(NULL)
  the$hardware <- jsonlite::fromJSON(res$stdout, simplifyVector = TRUE)
  the$hardware
}
