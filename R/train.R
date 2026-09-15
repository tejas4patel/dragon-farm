#' Fine-tune a model with LoRA
#'
#' Writes a run directory, then launches the trainer as a background Python
#' process. Returns immediately unless `wait = TRUE`. The run survives the R
#' session; reopen it later with [dragon_run()].
#'
#' @param dataset A mapped `dragon_dataset` (see [dragon_map()]).
#' @param model A Hugging Face model id such as
#'   `"HuggingFaceTB/SmolLM2-135M-Instruct"`, or a local model directory.
#'   See [dragon_presets()].
#' @param lora LoRA settings from [dragon_lora()].
#' @param args Training settings from [dragon_train_args()].
#' @param hardware Hardware settings from [dragon_hardware()].
#' @param name Short label used in the run id. Defaults to the model name.
#' @param run_dir Exact directory to use. Defaults to a timestamped directory
#'   under `runs_dir`.
#' @param runs_dir Parent directory for runs. See [dragon_runs_dir()].
#' @param n_samples Number of held-out rows to generate sample replies for
#'   at the end of training.
#' @param revision Model revision (branch, tag, or commit) on the Hub.
#' @param trust_remote_code Allow the model repository to run custom code.
#' @param wait Block until training finishes.
#' @return A `dragon_run` object.
#' @export
#' @examples
#' \dontrun{
#' run <- dragon_dataset(dragon_example_data()) |>
#'   dragon_map(prompt = "{subject}\n\n{body}", response = "reply") |>
#'   dragon_train("HuggingFaceTB/SmolLM2-135M-Instruct", wait = TRUE)
#' dragon_generate(run, "My order arrived damaged.")
#' }
dragon_train <- function(dataset, model, lora = dragon_lora(), args = dragon_train_args(),
                         hardware = dragon_hardware(), name = NULL, run_dir = NULL,
                         runs_dir = dragon_runs_dir(), n_samples = 10,
                         revision = NULL, trust_remote_code = FALSE, wait = FALSE) {
  prep <- prepare_run(dataset, model, lora, args, hardware, name, run_dir, runs_dir, n_samples,
                      revision = revision, trust_remote_code = trust_remote_code)
  files <- prep$files
  cpu_hint(hardware)
  run <- launch_trainer(prep$run_dir)
  cli::cli_alert_success("Launched run {.strong {run$id}} ({files$n_train} training rows, {files$n_eval} held out).")
  cli::cli_text("Check on it with {.code dragon_status(run)}, {.code dragon_progress(run)}, or {.code dragon_wait(run)}.")
  if (wait) dragon_wait(run) else run
}

# Validate the inputs and write a run directory without launching anything.
# Shared by dragon_train() and dragon_bundle(). Returns list(run_dir, files).
prepare_run <- function(dataset, model, lora, args, hardware, name, run_dir, runs_dir, n_samples,
                        revision = NULL, trust_remote_code = FALSE, state = "queued",
                        check_token = TRUE) {
  check_dataset(dataset, mapped = TRUE)
  check_string(model, "model")
  if (!inherits(lora, "dragon_lora")) cli::cli_abort("{.arg lora} must come from {.fn dragon_lora}.")
  if (!inherits(args, "dragon_train_args")) cli::cli_abort("{.arg args} must come from {.fn dragon_train_args}.")
  if (!inherits(hardware, "dragon_hardware")) cli::cli_abort("{.arg hardware} must come from {.fn dragon_hardware}.")
  check_number(n_samples, "n_samples", min = 0, integer = TRUE)

  preset <- preset_for(model)
  if (!is.null(preset) && preset$gated && !hf_token_present() && !isTRUE(getOption("dragonfarm.skip_token_check"))) {
    if (check_token) {
      cli::cli_abort(c(
        "{.val {model}} is a gated model and no Hugging Face token was found.",
        "i" = "Accept the license on huggingface.co, then set {.envvar HF_TOKEN} before training.",
        "i" = "Set {.code options(dragonfarm.skip_token_check = TRUE)} if the token is configured another way."
      ))
    } else {
      cli::cli_alert_warning("{.val {model}} is gated. The cloud notebook needs a Hugging Face token stored as a secret named {.envvar HF_TOKEN}.")
    }
  }

  if (is.null(run_dir)) {
    run_dir <- file.path(runs_dir, make_run_id(name %||% basename(model)))
  }
  if (file.exists(file.path(run_dir, "config.json"))) {
    cli::cli_abort("{.path {run_dir}} already holds a run. Pick another {.arg run_dir} or use {.fn dragon_resume}.")
  }
  dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
  run_dir <- normalizePath(run_dir, winslash = "/")

  files <- write_dataset_files(dataset, run_dir)
  cfg <- build_config(basename(run_dir), model, files, lora, args, hardware, n_samples,
                      revision = revision, trust_remote_code = trust_remote_code)
  write_json(cfg, file.path(run_dir, "config.json"))
  write_json(
    list(source = dataset$source, name = dataset$name, mapping = dataset$mapping,
         split = list(eval_frac = dataset$split$eval_frac, seed = dataset$split$seed)),
    file.path(run_dir, "dataset.json")
  )
  write_json(list(state = state, created_at = now_iso(), pid = NULL), file.path(run_dir, "status.json"))
  writeLines(character(), file.path(run_dir, "log.txt"))
  list(run_dir = run_dir, files = files)
}

# One line pointing at cloud GPUs when this machine is already known to be
# CPU-only (from an earlier dragon_check() or the app's hardware probe).
cpu_hint <- function(hardware) {
  hw <- the$hardware
  if (is.null(hw) || !identical(hw$device, "cpu") || !identical(hardware$device, "auto")) return(invisible(FALSE))
  cli::cli_alert_info("No GPU on this machine, so training runs on the CPU. For a cloud GPU, use {.fn dragon_bundle} and {.fn dragon_remote} instead.")
  invisible(TRUE)
}

launch_trainer <- function(run_dir, resume = FALSE) {
  py <- dragon_python()
  log <- file.path(run_dir, "log.txt")
  args <- c("-m", "dragonfarm.train", "--run-dir", run_dir)
  if (resume) args <- c(args, "--resume")
  p <- processx::process$new(
    py, args,
    stdout = log, stderr = "2>&1",
    env = python_env(),
    cleanup = FALSE, cleanup_tree = FALSE,
    windows_hide_window = TRUE
  )
  new_run(run_dir, p)
}

#' Resume a run from its latest checkpoint
#'
#' Useful after a cancel or a crash. Continues with the same configuration.
#'
#' @param run A `dragon_run`.
#' @param wait Block until training finishes.
#' @return A `dragon_run` object.
#' @export
dragon_resume <- function(run, wait = FALSE) {
  run <- dragon_run(run)
  st <- dragon_status(run)
  if (st$state %in% c("queued", "running")) cli::cli_abort("Run {.strong {run$id}} is still {st$state}.")
  ck <- list.dirs(run_path(run, "checkpoints"), recursive = FALSE)
  if (!length(ck)) cli::cli_alert_warning("No checkpoint found; training restarts from the beginning.")
  unlink(run_path(run, "cancel.request"))
  st$state <- "queued"
  st$error <- NULL
  st$finished_at <- NULL
  write_json(st, run_path(run, "status.json"))
  cat(sprintf("\n[dragonfarm] ---- resumed %s ----\n", now_iso()), file = run_path(run, "log.txt"), append = TRUE)
  run <- launch_trainer(run$dir, resume = TRUE)
  cli::cli_alert_success("Resumed run {.strong {run$id}}.")
  if (wait) dragon_wait(run) else run
}
