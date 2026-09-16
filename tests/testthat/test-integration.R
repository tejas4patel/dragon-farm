# End-to-end test against real Python. Skipped unless DRAGONFARM_INTEGRATION=true.
# Trains SmolLM2-135M for 6 steps on 40 rows (CPU is fine), then generates.

test_that("a tiny run trains, evaluates, generates, and merges", {
  skip_if_not(identical(Sys.getenv("DRAGONFARM_INTEGRATION"), "true"), "set DRAGONFARM_INTEGRATION=true")
  skip_on_cran()

  ds <- dragon_dataset(dragon_example_data())
  ds$data <- ds$data[1:40, ]
  ds <- dragon_map(ds, prompt = "{subject}\n\n{body}", response = "reply") |>
    dragon_split(eval_frac = 0.1, seed = 1)

  runs_dir <- file.path(tempfile("runs-"))
  run <- dragon_train(
    ds, "HuggingFaceTB/SmolLM2-135M-Instruct",
    lora = dragon_lora(r = 4, alpha = 8),
    args = dragon_train_args(max_steps = 6, batch_size = 2, grad_accum = 1, max_seq_len = 512,
                             logging_steps = 1, save_steps = 3),
    runs_dir = runs_dir, n_samples = 2, wait = TRUE
  )
  st <- dragon_status(run)
  expect_equal(st$state, "succeeded")
  expect_equal(st$total_steps, 6)
  expect_gt(st$trainable_params, 0)

  pr <- dragon_progress(run)
  expect_gte(nrow(pr), 6)
  expect_true(any(!is.na(pr$loss)))
  expect_true(file.exists(file.path(run$dir, "adapter", "adapter_config.json")))
  expect_true(file.exists(file.path(run$dir, "checkpoints", "checkpoint-6")))

  ev <- dragon_evaluate(run)
  expect_true(is.numeric(ev$eval_loss))
  expect_equal(nrow(ev$samples), 2)

  out <- dragon_generate(run, "My Ember thermostat keeps dropping off Wi-Fi.", max_new_tokens = 20, temperature = 0)
  expect_type(out, "character")
  expect_length(out, 1)

  code <- dragon_code(run)
  expect_match(code, "SmolLM2-135M")

  merged <- dragon_merge(run)
  expect_true(file.exists(file.path(merged, "config.json")))
  expect_true(any(grepl("safetensors$", list.files(merged))))
  out2 <- dragon_generate(merged, "Hello", max_new_tokens = 5, temperature = 0)
  expect_length(out2, 1)
})

test_that("cancel stops a run and leaves a checkpoint", {
  skip_if_not(identical(Sys.getenv("DRAGONFARM_INTEGRATION"), "true"), "set DRAGONFARM_INTEGRATION=true")
  skip_on_cran()

  ds <- dragon_dataset(dragon_example_data())
  ds <- dragon_map(ds, prompt = "subject", response = "reply")
  run <- dragon_train(
    ds, "HuggingFaceTB/SmolLM2-135M-Instruct",
    args = dragon_train_args(max_steps = 200, batch_size = 1, grad_accum = 1, max_seq_len = 256,
                             logging_steps = 1, save_steps = 2),
    runs_dir = tempfile("runs-"), n_samples = 0
  )
  # Wait until at least one step has been logged, then cancel.
  for (i in 1:600) {
    if (nrow(dragon_progress(run)) >= 3) break
    st <- dragon_status(run)
    if (st$state == "failed") stop(st$error)
    Sys.sleep(1)
  }
  dragon_cancel(run, timeout = 300)
  st <- dragon_status(run)
  expect_equal(st$state, "cancelled")
  expect_true(file.exists(file.path(run$dir, "adapter", "adapter_config.json")))
})


test_that("a preference stage chains from a fine-tuned run, evaluates, generates, and merges", {
  skip_if_not(identical(Sys.getenv("DRAGONFARM_INTEGRATION"), "true"), "set DRAGONFARM_INTEGRATION=true")
  skip_on_cran()

  runs_dir <- tempfile("runs-")
  base_ds <- dragon_dataset(dragon_example_data())
  base_ds$data <- base_ds$data[1:40, ]
  sft <- dragon_train(
    dragon_map(base_ds, prompt = "subject", response = "reply") |> dragon_split(0.1, seed = 1),
    "HuggingFaceTB/SmolLM2-135M-Instruct",
    lora = dragon_lora(r = 4, alpha = 8),
    args = dragon_train_args(max_steps = 3, batch_size = 2, grad_accum = 1, max_seq_len = 256,
                             logging_steps = 1, save_steps = 3),
    runs_dir = runs_dir, n_samples = 0, wait = TRUE
  )
  expect_equal(dragon_status(sft)$state, "succeeded")

  # Pairs: the real reply is chosen, another ticket's reply is rejected.
  pairs <- base_ds$data
  pairs$other <- pairs$reply[c(2:nrow(pairs), 1)]
  pairs_ds <- dragon_map_pairs(dragon_dataset(pairs), prompt = "subject", chosen = "reply", rejected = "other") |>
    dragon_split(0.1, seed = 1)

  for (method in c("dpo", "orpo")) {
    run <- dragon_prefer(
      pairs_ds, sft, method = method, beta = 0.1,
      lora = dragon_lora(r = 4, alpha = 8),
      args = dragon_train_args(max_steps = 3, batch_size = 2, grad_accum = 1, max_seq_len = 256,
                               logging_steps = 1, save_steps = 3, learning_rate = 5e-5),
      runs_dir = runs_dir, n_samples = 1, wait = TRUE
    )
    st <- dragon_status(run)
    expect_equal(st$state, "succeeded")
    expect_equal(st$stage, "prefer")
    expect_true(is.numeric(st$pref_accuracy))
    expect_true(file.exists(file.path(run$dir, "base_adapters", "1", "adapter_config.json")))
    pr <- dragon_progress(run)
    expect_true(any(!is.na(pr$pref_acc)))
    ev <- dragon_evaluate(run)
    expect_equal(ev$method, method)
    expect_true(ev$pref_accuracy >= 0 && ev$pref_accuracy <= 1)
    expect_true("rejected" %in% names(ev$samples))
    expect_match(dragon_code(run), "dragon_prefer(", fixed = TRUE)
    if (method == "dpo") {
      out <- dragon_generate(run, "My Ember thermostat keeps dropping off Wi-Fi.", max_new_tokens = 12, temperature = 0)
      expect_length(out, 1)
      before <- dragon_generate(run, "Hello", max_new_tokens = 5, temperature = 0, base = TRUE)
      expect_length(before, 1)
      merged <- dragon_merge(run)
      info <- dragonfarm:::read_json(file.path(merged, "dragonfarm.json"))
      expect_length(info$base_adapters, 1)
      expect_length(dragon_generate(merged, "Hi", max_new_tokens = 5, temperature = 0), 1)
    }
  }
})


test_that("metrics and a judge run over a finished run", {
  skip_if_not(identical(Sys.getenv("DRAGONFARM_INTEGRATION"), "true"), "set DRAGONFARM_INTEGRATION=true")
  skip_on_cran()

  ds <- dragon_dataset(dragon_example_data())
  ds$data <- ds$data[1:40, ]
  run <- dragon_train(
    dragon_map(ds, prompt = "subject", response = "reply") |> dragon_split(0.1, seed = 1),
    "HuggingFaceTB/SmolLM2-135M-Instruct",
    lora = dragon_lora(r = 4, alpha = 8),
    args = dragon_train_args(max_steps = 2, batch_size = 2, grad_accum = 1, max_seq_len = 256,
                             logging_steps = 1, save_steps = 2),
    runs_dir = tempfile("runs-"), n_samples = 1, wait = TRUE
  )
  ev <- dragon_evaluate(run, metrics = c("exact", "token_f1", "length_ratio"))
  expect_equal(nrow(ev$samples), 4)            # every held-out row, not just the 1 sample saved by training
  expect_named(ev$metrics, c("exact", "token_f1", "length_ratio"))
  expect_true(all(ev$metrics >= 0))

  # A deterministic judge that always prefers the shorter reply exercises the full
  # generate-both-sides path without an API key.
  shorter <- function(prompts) {
    vapply(prompts, function(p) {
      a <- sub(".*Reply A:\n(.*?)\n\nReply B:.*", "\\1", p)
      b <- sub(".*Reply B:\n(.*?)\n\nRespond with JSON.*", "\\1", p)
      w <- if (nchar(a) < nchar(b)) "A" else if (nchar(b) < nchar(a)) "B" else "tie"
      sprintf('{"winner": "%s", "reason": "shorter"}', w)
    }, character(1), USE.NAMES = FALSE)
  }
  j <- suppressMessages(dragon_judge(run, against = "base", n = 3, judge = shorter, max_new_tokens = 24))
  expect_equal(j$mode, "pairwise")
  expect_equal(j$summary$n, 3)
  expect_equal(j$summary$position_consistency, 1)
  expect_equal(dragon_status(run)$judge$n, 3)
  cmp <- dragon_compare(run)
  expect_equal(cmp$judge_n, 3L)
  expect_true("token_f1" %in% names(cmp))

  # Close the loop: sample from the run, score with a length-based judge, train DPO on the pairs.
  by_length <- function(prompts) {
    vapply(prompts, function(p) {
      reply <- sub(".*Reply to rate:\n(.*?)\n\nRespond with JSON.*", "\\1", p)
      sprintf('{"score": %d, "reason": "shorter is better"}', max(1, 10 - nchar(reply) %/% 12))
    }, character(1), USE.NAMES = FALSE)
  }
  prompts <- dragon_prompts(run, "train", n = 6)
  expect_length(prompts, 6)
  pairs <- suppressMessages(dragon_synthesize_pairs(prompts, student = run, judge = by_length, n_samples = 3,
                                                    min_gap = 0.5, temperature = 1.0, max_new_tokens = 24,
                                                    runs_dir = dirname(run$dir)))
  expect_equal(dragonfarm:::mapping_kind(pairs), "pairs")
  expect_gte(nrow(pairs$data), 1)
  expect_true(all(pairs$data$chosen_score > pairs$data$rejected_score))
  dpo <- dragon_prefer(
    pairs, run, method = "dpo",
    lora = dragon_lora(r = 4, alpha = 8),
    args = dragon_train_args(max_steps = 2, batch_size = 1, grad_accum = 1, max_seq_len = 256, logging_steps = 1, save_steps = 2),
    runs_dir = dirname(run$dir), n_samples = 0, wait = TRUE
  )
  expect_equal(dragon_status(dpo)$state, "succeeded")
  expect_equal(dragonfarm:::run_config(dpo)$model$base_run, run$id)
  expect_match(dragon_code(dpo), "synth/", fixed = TRUE)
})
