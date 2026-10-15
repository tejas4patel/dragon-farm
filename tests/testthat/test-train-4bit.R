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
