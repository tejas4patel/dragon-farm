#' Preference optimization with DPO or ORPO
#'
#' The second stage of post-training. Where [dragon_train()] teaches a model
#' what a good reply looks like, this teaches it which of two replies is
#' better, from a dataset mapped with [dragon_map_pairs()].
#'
#' Two methods are available:
#'
#' * `"dpo"`, Direct Preference Optimization. Pushes the model's implicit
#'   reward for the chosen reply above the rejected one, relative to a
#'   reference model. With LoRA the reference is the same model with the
#'   adapter switched off, so it costs no extra memory.
#' * `"orpo"`, Odds Ratio Preference Optimization. Combines the supervised
#'   loss on the chosen reply with an odds-ratio penalty on the rejected one.
#'   Needs no reference model and works from a base model that has not been
#'   fine-tuned yet.
#'
#' `beta` controls how hard the model is pushed: the KL strength for DPO,
#' the odds-ratio weight for ORPO. `0.1` is a sensible start for both.
#'
#' Pass a finished run as `model` to continue from it. Its adapters are
#' folded into the weights before this stage adds its own, which is the
#' usual sequence: [dragon_train()] first, then `dragon_prefer()` on top.
#'
#' @inheritParams dragon_train
#' @param dataset A dataset mapped with [dragon_map_pairs()].
#' @param method `"dpo"` or `"orpo"`.
#' @param beta Preference strength. Typical values are 0.05 to 0.5.
#' @param args Training settings. The defaults use a lower learning rate than
#'   [dragon_train()], which preference methods need.
#' @return A `dragon_run` object.
#' @export
#' @examples
#' \dontrun{
#' sft <- dragon_dataset("tickets.csv") |>
#'   dragon_map(prompt = "question", response = "answer") |>
#'   dragon_train("Qwen/Qwen2.5-0.5B-Instruct", wait = TRUE)
#'
#' dpo <- dragon_dataset("preferences.csv") |>
#'   dragon_map_pairs(prompt = "question", chosen = "better", rejected = "worse") |>
#'   dragon_prefer(sft, method = "dpo", beta = 0.1, wait = TRUE)
#'
#' dragon_evaluate(dpo)
#' dragon_generate(dpo, "My thermostat keeps dropping off Wi-Fi.")
#' }
dragon_prefer <- function(dataset, model, method = c("dpo", "orpo"), beta = 0.1,
                          lora = dragon_lora(), args = dragon_train_args(learning_rate = 5e-5, epochs = 2),
                          hardware = dragon_hardware(), name = NULL, run_dir = NULL,
                          runs_dir = dragon_runs_dir(), n_samples = 10,
                          revision = NULL, trust_remote_code = FALSE, wait = FALSE) {
  method <- match.arg(method)
  check_number(beta, "beta", min = 1e-4, max = 10)
  prep <- prepare_run(dataset, model, lora, args, hardware, name, run_dir, runs_dir, n_samples,
                      revision = revision, trust_remote_code = trust_remote_code,
                      stage = "prefer", prefer = list(method = method, beta = beta))
  files <- prep$files
  cpu_hint(hardware)
  run <- launch_trainer(prep$run_dir)
  cli::cli_alert_success("Launched {toupper(method)} run {.strong {run$id}} ({files$n_train} pairs, {files$n_eval} held out).")
  cli::cli_text("Check on it with {.code dragon_status(run)}, {.code dragon_progress(run)}, or {.code dragon_wait(run)}.")
  if (wait) dragon_wait(run) else run
}
