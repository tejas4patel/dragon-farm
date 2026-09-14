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
