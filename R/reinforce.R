#' Map columns for reinforcement learning
#'
#' For [dragon_reinforce()]. Each row is a prompt the model will practise
#' on, with an optional reference answer that reward functions such as
#' `"exact"` and `"numeric"` compare against. Every other column travels
#' along as `fields`, available to custom reward functions.
#'
#' @inheritParams dragon_map
#' @param reference Optional column name or template for the reference
#'   answer.
#' @return The dataset with the mapping attached.
#' @export
#' @examples
#' df <- data.frame(question = c("12 * 12?", "Capital of Peru?"), answer = c("144", "Lima"))
#' ds <- dragon_map_prompts(dragon_dataset(df), prompt = "question", reference = "answer")
#' dragon_preview(ds, n = 1)
dragon_map_prompts <- function(dataset, prompt, reference = NULL, system = NULL) {
  check_dataset(dataset)
  cols <- names(dataset$data)
  dataset$mapping <- list(
    kind = "prompts",
    prompt = as_template(prompt, cols, "prompt"),
    reference = if (!is.null(reference)) as_template(reference, cols, "reference"),
    system = if (!is.null(system)) as_template(system, cols, "system", allow_constant = TRUE)
  )
  dataset
}

# Rows of the "prompts" format: prompt messages, optional reference, and the
# row's other columns as string fields for custom rewards.
dataset_prompts <- function(dataset, idx = NULL) {
  check_dataset(dataset, mapped = TRUE, kind = "prompts")
  d <- dataset$data
  if (!is.null(idx)) d <- d[idx, , drop = FALSE]
  if (!nrow(d)) return(list())
  m <- dataset$mapping
  prompt <- render_template(m$prompt, d)
  reference <- if (!is.null(m$reference)) render_template(m$reference, d)
  system <- if (!is.null(m$system)) render_template(m$system, d)
  lapply(seq_len(nrow(d)), function(i) {
    msgs <- list()
    if (!is.null(system) && nzchar(trimws(system[i]))) {
      msgs[[length(msgs) + 1]] <- list(role = "system", content = system[i])
    }
    msgs[[length(msgs) + 1]] <- list(role = "user", content = prompt[i])
    fields <- lapply(as.list(d[i, , drop = FALSE]), function(v) {
      if (is.atomic(v) && length(v) == 1 && !is.na(v)) as.character(v) else NULL
    })
    fields <- fields[!vapply(fields, is.null, logical(1))]
    list(prompt = msgs, reference = if (!is.null(reference)) reference[i] else NULL,
         fields = if (length(fields)) fields else empty_object())
  })
}

prompt_as_messages <- function(row) {
  msgs <- row$prompt
  if (!is.null(row$reference)) msgs <- c(msgs, list(list(role = "reference", content = row$reference)))
  list(messages = msgs)
}

#' Verifiable rewards for reinforcement learning
#'
#' A reward scores one completion between 0 and 1. [dragon_reinforce()] takes
#' one or more, sums them by `weight`, and pushes the model towards higher
#' totals. These built-ins are verifiable: they check facts about the text
#' rather than asking a model's opinion, which is what makes reinforcement
#' learning work on small models.
#'
#' * `"exact"`: normalized exact match with the row's reference.
#' * `"contains"`: the reference appears in the completion.
#' * `"numeric"`: the last number in the completion equals the reference's.
#' * `"regex"`: the completion matches `pattern`.
#' * `"json"`: the completion is valid JSON, with `keys` present if given
#'   (partial credit per key).
#' * `"length"`: 1 within `min_chars` to `max_chars`, falling to 0 beyond.
#' * `"keyword"`: any (or all) of `words` appear.
#' * `"custom"`: a Python `file` defining `reward(prompt, completion,
#'   reference, row)` that returns a number. The file is copied into the run
#'   so the run stays self-contained.
#'
#' @param type Which reward.
#' @param weight Multiplier when rewards are summed.
#' @param name Label used in progress rows and evaluation. Defaults to the type.
#' @param pattern Regular expression, for `"regex"`.
#' @param case_sensitive Whether `pattern` is case-sensitive.
#' @param keys Required top-level keys, for `"json"`.
#' @param min_chars,max_chars Bounds, for `"length"`. Give at least one.
#' @param words Words to look for, for `"keyword"`.
#' @param mode `"any"` or `"all"` of `words`.
#' @param file Python file, for `"custom"`.
#' @param fn Name of the function inside `file`.
#' @return A `dragon_reward` object.
#' @export
#' @examples
#' dragon_reward("exact")
#' dragon_reward("regex", pattern = "^T-\\d{4}", weight = 2)
#' dragon_reward("length", max_chars = 400, weight = 0.5)
#' dragon_reward("json", keys = c("id", "status"))
dragon_reward <- function(type = c("exact", "contains", "numeric", "regex", "json", "length", "keyword", "custom"),
                          weight = 1, name = NULL, pattern = NULL, case_sensitive = FALSE, keys = NULL,
                          min_chars = NULL, max_chars = NULL, words = NULL, mode = c("any", "all"),
                          file = NULL, fn = "reward") {
  type <- match.arg(type)
  check_number(weight, "weight", min = 0)
  spec <- list(type = type, weight = weight)
  switch(type,
    regex = {
      check_string(pattern, "pattern")
      spec$pattern <- pattern
      spec$case_sensitive <- isTRUE(case_sensitive)
    },
    json = {
      if (!is.null(keys)) spec$keys <- as.list(as.character(keys))
    },
    length = {
      if (is.null(min_chars) && is.null(max_chars)) cli::cli_abort("A {.val length} reward needs {.arg min_chars} or {.arg max_chars}.")
      check_number(min_chars, "min_chars", min = 0, integer = TRUE, allow_null = TRUE)
      check_number(max_chars, "max_chars", min = 1, integer = TRUE, allow_null = TRUE)
      spec$min_chars <- min_chars
      spec$max_chars <- max_chars
    },
    keyword = {
      if (!is.character(words) || !length(words)) cli::cli_abort("A {.val keyword} reward needs {.arg words}.")
      spec$words <- as.list(words)
      spec$mode <- match.arg(mode)
    },
    custom = {
      check_string(file, "file")
      if (!file.exists(file)) cli::cli_abort("Reward file {.path {file}} does not exist.")
      check_string(fn, "fn")
      spec$file <- normalizePath(file, winslash = "/")
      spec[["function"]] <- fn
    }
  )
  if (!is.null(name)) {
    check_string(name, "name")
    spec$name <- name
  }
  structure(spec, class = "dragon_reward")
}

#' @export
print.dragon_reward <- function(x, ...) {
  extras <- setdiff(names(x), c("type", "weight", "name"))
  detail <- if (length(extras)) paste(vapply(extras, function(k) paste0(k, " = ", paste(unlist(x[[k]]), collapse = ",")), character(1)), collapse = ", ") else ""
  cli::cli_text("{.cls dragon_reward} {.strong {x$name %||% x$type}} (type {x$type}, weight {x$weight}{if (nzchar(detail)) paste0('; ', detail) else ''})")
  invisible(x)
}

# One reward or a list of them, as plain lists for config.json.
as_reward_specs <- function(rewards) {
  if (inherits(rewards, "dragon_reward")) rewards <- list(rewards)
  if (!is.list(rewards) || !length(rewards) || !all(vapply(rewards, inherits, logical(1), "dragon_reward"))) {
    cli::cli_abort("{.arg rewards} must be a {.fn dragon_reward} or a list of them.")
  }
  lapply(rewards, function(r) unclass(r))
}

# Copy custom reward files into the run so it is self-contained (and bundles).
localize_rewards <- function(specs, run_dir) {
  dir <- file.path(run_dir, "rewards")
  lapply(specs, function(s) {
    if (identical(s$type, "custom")) {
      dir.create(dir, recursive = TRUE, showWarnings = FALSE)
      target <- file.path(dir, basename(s$file))
      file.copy(s$file, target, overwrite = TRUE)
      s$file <- paste0("rewards/", basename(s$file))
    }
    s
  })
}

#' Reinforcement learning with verifiable rewards (GRPO)
#'
#' The third stage of post-training. For every prompt the model writes
#' several completions, each is scored by the rewards, and the model is
#' nudged towards the completions that beat their group's average. A KL
#' penalty against the model it started from keeps it from drifting. This is
#' Group Relative Policy Optimization, the method behind recent reasoning
#' models, in its plain on-policy form.
#'
#' It works well when the reward is something you can check: a correct
#' number, valid JSON with the right keys, a required format, a length
#' budget, a test that passes. It works poorly as a substitute for
#' preference data on vague goals such as "be more helpful"; use
#' [dragon_prefer()] for those.
#'
#' Pass a finished run as `model` to continue from it, which is the usual
#' order: [dragon_train()], optionally [dragon_prefer()], then this.
#'
#' @inheritParams dragon_train
#' @param dataset A dataset mapped with [dragon_map_prompts()].
#' @param rewards A [dragon_reward()] or a list of them.
#' @param group_size Completions sampled per prompt. 4 to 8 is typical; more
#'   gives a better baseline at more cost per step.
#' @param beta Weight of the KL penalty towards the starting model. Higher
#'   is more conservative.
#' @param temperature Sampling temperature for the completions. Must be
#'   above zero so the group varies.
#' @param max_new_tokens Length cap for each sampled completion.
#' @param args Training settings. `batch_size` is prompts per step (so
#'   `batch_size * group_size` completions), `epochs` or `max_steps` set the
#'   length, and `save_steps` the checkpoint interval. The defaults use a
#'   small learning rate, which RL needs.
#' @return A `dragon_run` object.
#' @export
#' @examples
#' \dontrun{
#' math <- dragon_dataset("arithmetic.csv") |>
#'   dragon_map_prompts(prompt = "question", reference = "answer")
#' rl <- dragon_reinforce(
#'   math, sft,
#'   rewards = list(dragon_reward("numeric"), dragon_reward("length", max_chars = 300, weight = 0.2)),
#'   group_size = 6, wait = TRUE
#' )
#' dragon_evaluate(rl)     # mean reward on held-out prompts, per reward
#' }
dragon_reinforce <- function(dataset, model, rewards, group_size = 4, beta = 0.04, temperature = 1.0,
                             max_new_tokens = 128, lora = dragon_lora(),
                             args = dragon_train_args(learning_rate = 1e-5, epochs = 1, batch_size = 4,
                                                      grad_accum = 1, save_steps = 20),
                             hardware = dragon_hardware(), name = NULL, run_dir = NULL,
                             runs_dir = dragon_runs_dir(), n_samples = 10,
                             revision = NULL, trust_remote_code = FALSE, wait = FALSE) {
  specs <- as_reward_specs(rewards)
  check_number(group_size, "group_size", min = 2, max = 64, integer = TRUE)
  check_number(beta, "beta", min = 0, max = 10)
  check_number(temperature, "temperature", min = 0.05, max = 3)
  check_number(max_new_tokens, "max_new_tokens", min = 1, integer = TRUE)
  reinforce <- list(rewards = specs, group_size = as.integer(group_size), beta = beta,
                    temperature = temperature, max_new_tokens = as.integer(max_new_tokens))
  prep <- prepare_run(dataset, model, lora, args, hardware, name, run_dir, runs_dir, n_samples,
                      revision = revision, trust_remote_code = trust_remote_code,
                      stage = "reinforce", reinforce = reinforce)
  files <- prep$files
  cpu_hint(hardware)
  run <- launch_trainer(prep$run_dir)
  cli::cli_alert_success("Launched GRPO run {.strong {run$id}} ({files$n_train} prompts, {files$n_eval} held out, {length(specs)} reward{?s}).")
  cli::cli_text("Check on it with {.code dragon_status(run)}, {.code dragon_progress(run)}, or {.code dragon_wait(run)}.")
  if (wait) dragon_wait(run) else run
}

# R code for a reward spec, for dragon_code().
reward_code <- function(spec) {
  fmt <- fmt_arg
  parts <- c(fmt(spec$type))
  if (!is.null(spec$weight) && spec$weight != 1) parts <- c(parts, sprintf("weight = %s", fmt(spec$weight)))
  if (!is.null(spec$name)) parts <- c(parts, sprintf("name = %s", fmt(spec$name)))
  if (!is.null(spec$pattern)) parts <- c(parts, sprintf("pattern = %s", fmt(spec$pattern)))
  if (isTRUE(spec$case_sensitive)) parts <- c(parts, "case_sensitive = TRUE")
  if (!is.null(spec$keys)) parts <- c(parts, sprintf("keys = %s", fmt(unlist(spec$keys))))
  if (!is.null(spec$min_chars)) parts <- c(parts, sprintf("min_chars = %s", fmt(spec$min_chars)))
  if (!is.null(spec$max_chars)) parts <- c(parts, sprintf("max_chars = %s", fmt(spec$max_chars)))
  if (!is.null(spec$words)) parts <- c(parts, sprintf("words = %s", fmt(unlist(spec$words))))
  if (!is.null(spec$mode) && !identical(spec$mode, "any")) parts <- c(parts, sprintf("mode = %s", fmt(spec$mode)))
  if (!is.null(spec$file)) parts <- c(parts, sprintf("file = %s", fmt(spec$file)))
  if (!is.null(spec[["function"]]) && !identical(spec[["function"]], "reward")) parts <- c(parts, sprintf("fn = %s", fmt(spec[["function"]])))
  sprintf("dragon_reward(%s)", paste(parts, collapse = ", "))
}
