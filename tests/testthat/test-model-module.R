test_that("the Model module tracks the chosen model and its trust_remote_code flag", {
  state <- shiny::reactiveValues(model = NULL, hardware = NULL)
  navigated <- character()
  shiny::testServer(dragonfarm:::mod_model_server, args = list(state = state, nav_to = function(panel) navigated <<- c(navigated, panel)), {
    session$setInputs(preset = "Qwen/Qwen2.5-0.5B-Instruct")
    expect_equal(state$model, list(id = "Qwen/Qwen2.5-0.5B-Instruct", trust_remote_code = FALSE))

    session$setInputs(trust = TRUE)
    expect_true(state$model$trust_remote_code)

    # a custom model id overrides the preset radio button
    session$setInputs(custom = "  org/my-model  ")
    expect_equal(state$model$id, "org/my-model")
    session$setInputs(custom = "")
    expect_equal(state$model$id, "Qwen/Qwen2.5-0.5B-Instruct")

    session$setInputs(`next` = 1)
    expect_equal(navigated, "train")
  })
})

test_that("the Model module reports hardware once detected, and a gated-model warning without a token", {
  testthat::local_mocked_bindings(
    hardware_info = function() list(device = "cuda", device_name = "Fake GPU", vram_gb = 6, torch = "2.4.0", transformers = "4.46.0"),
    hf_token_present = function() FALSE
  )
  state <- shiny::reactiveValues(model = NULL, hardware = NULL)
  shiny::testServer(dragonfarm:::mod_model_server, args = list(state = state, nav_to = function(panel) NULL), {
    hint <- as.character(output$hardware$html)
    expect_match(hint, "Not checked yet", fixed = TRUE)

    session$setInputs(detect = 1)
    expect_equal(state$hardware$device_name, "Fake GPU")
    hw_html <- as.character(output$hardware$html)
    expect_match(hw_html, "Fake GPU", fixed = TRUE)

    session$setInputs(preset = "google/gemma-3-1b-it")
    verdict <- as.character(output$verdict$html)
    expect_match(verdict, "This model is gated", fixed = TRUE)
    expect_match(verdict, "Fits on this GPU", fixed = TRUE)   # 6 GB fits gemma-3-1b-it's minimum

    session$setInputs(preset = "Qwen/Qwen2.5-1.5B-Instruct")
    verdict2 <- as.character(output$verdict$html)
    expect_match(verdict2, "Needs about", fixed = TRUE)   # 1.5B needs more than this fake 6 GB card
  })
})

test_that("the Model module warns about a CPU-only machine for a model that needs real VRAM", {
  testthat::local_mocked_bindings(
    hardware_info = function() list(device = "cpu", device_name = "CPU", torch = "2.4.0", transformers = "4.46.0")
  )
  state <- shiny::reactiveValues(model = NULL, hardware = NULL)
  shiny::testServer(dragonfarm:::mod_model_server, args = list(state = state, nav_to = function(panel) NULL), {
    session$setInputs(detect = 1, preset = "Qwen/Qwen2.5-1.5B-Instruct")
    verdict <- as.character(output$verdict$html)
    expect_match(verdict, "slow to train on a CPU", fixed = TRUE)
  })
})

test_that("a failed hardware detection notifies instead of crashing", {
  testthat::local_mocked_bindings(hardware_info = function() stop("no python here"))
  state <- shiny::reactiveValues(model = NULL, hardware = NULL)
  shiny::testServer(dragonfarm:::mod_model_server, args = list(state = state, nav_to = function(panel) NULL), {
    session$setInputs(detect = 1)
    expect_null(state$hardware)
  })
})
