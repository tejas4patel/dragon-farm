test_that("lora settings validate", {
  l <- dragon_lora(r = 8, alpha = 16)
  expect_s3_class(l, "dragon_lora")
  expect_identical(l$r, 8L)
  expect_error(dragon_lora(r = 0), "between")
  expect_error(dragon_lora(r = 2.5), "whole number")
  expect_error(dragon_lora(dropout = 1), "between")
  expect_error(dragon_lora(target_modules = 3), "target_modules")
})

test_that("train args validate and keep extras", {
  a <- dragon_train_args(epochs = 1, max_steps = 10, foo = "bar")
  expect_identical(a$max_steps, 10L)
  expect_equal(a$extra$foo, "bar")
  expect_error(dragon_train_args(learning_rate = 5), "between")
  expect_error(dragon_train_args(batch_size = 0), "between")
  expect_error(dragon_train_args(epochs = "x"), "single number")
  plain <- dragon_train_args()
  expect_equal(length(plain$extra), 0)
})

test_that("hardware settings validate", {
  expect_equal(dragon_hardware()$device, "auto")
  expect_error(dragon_hardware(device = "tpu"))
})

test_that("config round-trips through JSON", {
  files <- list(train = "data/train.jsonl", eval = "data/eval.jsonl", n_train = 38L, n_eval = 2L)
  cfg <- dragonfarm:::build_config(
    "r1", "HuggingFaceTB/SmolLM2-135M-Instruct", files,
    dragon_lora(r = 4, target_modules = c("q_proj", "v_proj")),
    dragon_train_args(epochs = 1, max_steps = 6, gradient_checkpointing = TRUE, lr_scheduler_type = "linear"),
    dragon_hardware(device = "cpu"), n_samples = 3
  )
  f <- tempfile(fileext = ".json")
  dragonfarm:::write_json(cfg, f)
  txt <- paste(readLines(f), collapse = "\n")
  expect_match(txt, '"schema_version": 1')
  expect_match(txt, '"revision": null')
  expect_match(txt, '"q_proj"')
  expect_match(txt, '"lr_scheduler_type": "linear"')
  back <- dragonfarm:::read_json(f)
  objs <- dragonfarm:::config_to_objects(back)
  expect_equal(objs$lora$target_modules, c("q_proj", "v_proj"))
  expect_identical(objs$args$max_steps, 6L)
  expect_true(objs$args$gradient_checkpointing)
  expect_equal(objs$hardware$device, "cpu")
})

test_that("empty extra serializes as an object", {
  cfg <- dragonfarm:::build_config(
    "r1", "m", list(train = "t", eval = NULL, n_train = 1L, n_eval = 0L),
    dragon_lora(), dragon_train_args(), dragon_hardware(), 0
  )
  txt <- as.character(jsonlite::toJSON(cfg, auto_unbox = TRUE, null = "null"))
  expect_match(txt, '"extra":\\{\\}')
  expect_match(txt, '"eval":null')
})

test_that("presets are well formed", {
  p <- dragon_presets()
  expect_true(all(c("id", "params", "gated", "min_vram_gb") %in% names(p)))
  expect_true(any(p$gated))
  expect_equal(dragonfarm:::preset_for("Qwen/Qwen2.5-0.5B-Instruct")$params, "0.5B")
  expect_null(dragonfarm:::preset_for("nobody/nothing"))
})
