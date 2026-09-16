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


test_that("a GRPO stage trains with verifiable rewards, evaluates, and generates", {
  skip_if_not(identical(Sys.getenv("DRAGONFARM_INTEGRATION"), "true"), "set DRAGONFARM_INTEGRATION=true")
  skip_on_cran()

  a <- 1:40
  math <- data.frame(question = sprintf("What is %d + %d? Answer with just the number.", a, a),
                     answer = as.character(2 * a), stringsAsFactors = FALSE)
  ds <- dragon_map_prompts(dragon_dataset(math), prompt = "question", reference = "answer") |>
    dragon_split(0.1, seed = 1)
  py <- tempfile("digits-", fileext = ".py")
  writeLines(c("def reward(prompt, completion, reference, row):",
               "    return 1.0 if any(ch.isdigit() for ch in completion) else 0.0"), py)

  run <- dragon_reinforce(
    ds, "HuggingFaceTB/SmolLM2-135M-Instruct",
    rewards = list(dragon_reward("numeric"), dragon_reward("length", max_chars = 40, weight = 0.5),
                   dragon_reward("custom", file = py, name = "has_digit")),
    group_size = 3, temperature = 1.0, max_new_tokens = 12,
    lora = dragon_lora(r = 4, alpha = 8),
    args = dragon_train_args(max_steps = 3, batch_size = 2, grad_accum = 1, max_seq_len = 128,
                             save_steps = 3, learning_rate = 1e-5),
    runs_dir = tempfile("runs-"), n_samples = 2, wait = TRUE
  )
  st <- dragon_status(run)
  expect_equal(st$state, "succeeded")
  expect_equal(st$stage, "reinforce")
  expect_equal(st$total_steps, 3)
  expect_true(is.numeric(st$reward_mean))
  expect_named(st$reward_breakdown, c("numeric", "length", "has_digit"))

  pr <- dragon_progress(run)
  expect_equal(nrow(pr), 3)
  expect_true(all(!is.na(pr$reward)))
  expect_true(all(!is.na(pr$kl)))
  expect_true("reward_has_digit" %in% names(pr))
  expect_true(file.exists(file.path(run$dir, "checkpoints", "checkpoint-3")))
  expect_true(file.exists(file.path(run$dir, "adapter", "adapter_config.json")))

  ev <- dragon_evaluate(run)
  expect_true(is.numeric(ev$reward_mean))
  expect_equal(ev$eval_prompts, 4)
  expect_true("reward" %in% names(ev$samples))
  expect_length(dragon_generate(run, "What is 2 + 2?", max_new_tokens = 8, temperature = 0), 1)
  expect_match(dragon_code(run), "dragon_reinforce(", fixed = TRUE)
  expect_equal(dragon_compare(run)$reward, st$reward_mean)
})


test_that("a pipeline chains fine-tune, self-made pairs, DPO, judge, and metrics", {
  skip_if_not(identical(Sys.getenv("DRAGONFARM_INTEGRATION"), "true"), "set DRAGONFARM_INTEGRATION=true")
  skip_on_cran()

  ds <- dragon_dataset(dragon_example_data())
  ds$data <- ds$data[1:30, ]
  ds <- dragon_map(ds, prompt = "subject", response = "reply") |> dragon_split(0.1, seed = 1)
  scorer <- function(prompts) {
    vapply(prompts, function(p) {
      if (grepl("Reply A:", p, fixed = TRUE)) {
        a <- sub(".*Reply A:\n(.*?)\n\nReply B:.*", "\\1", p)
        b <- sub(".*Reply B:\n(.*?)\n\nRespond with JSON.*", "\\1", p)
        w <- if (nchar(a) < nchar(b)) "A" else if (nchar(b) < nchar(a)) "B" else "tie"
        sprintf('{"winner": "%s", "reason": "shorter"}', w)
      } else {
        reply <- sub(".*Reply to rate:\n(.*?)\n\nRespond with JSON.*", "\\1", p)
        sprintf('{"score": %d, "reason": "shorter"}', max(1, 10 - nchar(reply) %/% 12))
      }
    }, character(1), USE.NAMES = FALSE)
  }
  small <- dragon_train_args(max_steps = 2, batch_size = 2, grad_accum = 1, max_seq_len = 192, logging_steps = 1, save_steps = 2)
  runs <- tempfile("runs-")
  p <- suppressMessages(dragon_pipeline(
    "HuggingFaceTB/SmolLM2-135M-Instruct",
    list(
      dragon_step_train(ds, lora = dragon_lora(r = 4, alpha = 8), args = small, n_samples = 0),
      dragon_step_synthesize_pairs(prompts = "train", n = 4, judge = scorer, n_samples_per_prompt = 3,
                                   min_gap = 0.5, temperature = 1.0, max_new_tokens = 20),
      dragon_step_prefer(lora = dragon_lora(r = 4, alpha = 8), args = small, n_samples = 0),
      dragon_step_judge(against = "base", judge = scorer, n = 2),
      dragon_step_evaluate(metrics = c("token_f1", "length_ratio"))
    ),
    runs_dir = runs, name = "loop"
  ))
  expect_equal(p$status, "succeeded")
  expect_length(p$runs, 2)
  expect_equal(vapply(p$steps, `[[`, character(1), "state"), rep("succeeded", 5))
  expect_equal(dragonfarm:::run_config(p$runs[[2]])$model$base_run, p$runs[[1]]$id)
  expect_true(p$results[[2]]$pairs >= 1)
  expect_equal(p$results[[4]]$mode, "pairwise")
  cmp <- dragon_compare(p)
  expect_equal(nrow(cmp), 2)
  expect_equal(cmp$stage, c("sft", "prefer"))
  rec <- dragon_pipeline_status(p$id, runs_dir = runs)
  expect_equal(rec$status, "succeeded")
})


test_that("the local worker keeps the model loaded and chat keeps context", {
  skip_if_not(identical(Sys.getenv("DRAGONFARM_INTEGRATION"), "true"), "set DRAGONFARM_INTEGRATION=true")
  skip_on_cran()

  dragon_worker_stop()
  model <- "HuggingFaceTB/SmolLM2-135M-Instruct"
  t1 <- system.time(a <- dragon_generate(model, "Say hi.", max_new_tokens = 8, temperature = 0))[["elapsed"]]
  t2 <- system.time(b <- dragon_generate(model, c("Say hi.", "Say bye."), max_new_tokens = 8, temperature = 0))[["elapsed"]]
  expect_length(a, 1)
  expect_length(b, 2)
  expect_lt(t2, t1)                  # second call skips the model load
  expect_true(dragonfarm:::worker_alive())

  chat <- dragon_chat(model, system = "Answer in one short sentence.", temperature = 0, max_new_tokens = 24)
  first <- chat$say("My name is Tejas.")
  second <- chat$say("What is my name?")
  expect_true(nzchar(first) && nzchar(second))
  expect_length(chat$history(), 4)

  pieces <- character()
  streamed <- chat$say("Count to three.", on_token = function(p) pieces <<- c(pieces, p))
  expect_gt(length(pieces), 0)
  expect_equal(trimws(paste(pieces, collapse = "")), streamed)

  dragon_worker_stop()
  expect_false(dragonfarm:::worker_alive())
  one <- dragon_generate(model, "Hi", max_new_tokens = 4, temperature = 0, backend = dragon_backend_local(keep_loaded = FALSE))
  expect_length(one, 1)
  expect_false(dragonfarm:::worker_alive())
})
