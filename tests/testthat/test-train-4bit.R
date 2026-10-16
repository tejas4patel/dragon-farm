test_that("model sizes are read from model ids as in the Python package", {
  expect_equal(dragonfarm:::model_size_b("Qwen/Qwen2.5-7B-Instruct"), 7)
  expect_equal(dragonfarm:::model_size_b("Qwen/Qwen2.5-0.5B-Instruct"), 0.5)
  expect_equal(dragonfarm:::model_size_b("HuggingFaceTB/SmolLM2-135M-Instruct"), 0.135)
  expect_equal(dragonfarm:::model_size_b("meta-llama/Llama-3.2-1B-Instruct"), 1)
  expect_true(is.na(dragonfarm:::model_size_b("org/model-name")))
  expect_true(is.na(dragonfarm:::model_size_b(NULL)))
})

test_that("training suggests 4-bit when bf16 weights would crowd the GPU", {
  gpu8 <- list(device = "cuda", vram_gb = 7.996)
  gpu24 <- list(device = "cuda", vram_gb = 24)
  expect_true(dragonfarm:::suggest_train_4bit("Qwen/Qwen2.5-7B-Instruct", gpu8))
  expect_true(dragonfarm:::suggest_train_4bit("Qwen/Qwen2.5-3B-Instruct", gpu8))
  expect_false(dragonfarm:::suggest_train_4bit("Qwen/Qwen2.5-1.5B-Instruct", gpu8))
  expect_false(dragonfarm:::suggest_train_4bit("Qwen/Qwen2.5-3B-Instruct", gpu24))
  expect_true(is.na(dragonfarm:::suggest_train_4bit("Qwen/Qwen2.5-7B-Instruct", list(device = "cpu"))))
  expect_true(is.na(dragonfarm:::suggest_train_4bit("org/model-name", gpu8)))
  # Hardware not detected yet: only a model that cannot fit anyway is flagged.
  expect_true(dragonfarm:::suggest_train_4bit("Qwen/Qwen2.5-7B-Instruct", NULL))
  expect_true(is.na(dragonfarm:::suggest_train_4bit("Qwen/Qwen2.5-0.5B-Instruct", NULL)))
})

test_that("the train module warns when 4-bit is ticked without an NVIDIA GPU", {
  state <- shiny::reactiveValues(dataset = NULL, mapped = NULL, model = list(id = "Qwen/Qwen2.5-7B-Instruct"),
                                 run = NULL, hardware = list(device = "cpu"))
  shiny::testServer(dragonfarm:::mod_train_server, args = list(state = state, nav_to = function(p) NULL), {
    session$setInputs(four_bit = TRUE)
    expect_match(paste(output$four_bit_hint$html), "needs an NVIDIA GPU")
    state$hardware <- list(device = "cuda", vram_gb = 8)
    session$setInputs(four_bit = TRUE)
    expect_match(paste(output$four_bit_hint$html), "LoRA adapter trains in full precision")
    session$setInputs(four_bit = FALSE)
    expect_null(output$four_bit_hint)
  })
})

test_that("4-bit runs use batch size 1 and keep the effective batch", {
  expect_equal(dragonfarm:::batch_for_4bit(4, 4), list(batch_size = 1L, grad_accum = 16L))
  expect_equal(dragonfarm:::batch_for_4bit(1, 16), list(batch_size = 1L, grad_accum = 16L))
  expect_equal(dragonfarm:::batch_for_4bit(NA, 8), list(batch_size = 1L, grad_accum = 8L))
})

test_that("model sizes get a dragon life stage, and every preset card shows one", {
  stage <- function(id) dragonfarm:::dragon_stage(dragonfarm:::model_size_b(id))
  expect_equal(stage("HuggingFaceTB/SmolLM2-135M-Instruct"), "Egg")
  expect_equal(stage("Qwen/Qwen2.5-0.5B-Instruct"), "Hatchling")
  expect_equal(stage("Qwen/Qwen2.5-1.5B-Instruct"), "Drake")
  expect_equal(stage("Qwen/Qwen2.5-3B-Instruct"), "Wyvern")
  expect_equal(stage("Qwen/Qwen2.5-7B-Instruct"), "Elder")
  expect_equal(stage("org/no-size-here"), "")
  expect_true(all(nzchar(vapply(dragon_presets()$id, stage, ""))))
})
