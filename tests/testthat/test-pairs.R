pairs_df <- function(n = 30) {
  data.frame(
    q = paste("Question", seq_len(n)),
    good = paste("Good answer", seq_len(n)),
    bad = paste("Bad answer", seq_len(n)),
    stringsAsFactors = FALSE
  )
}

pairs_ds <- function(n = 30) {
  dragon_map_pairs(dragon_dataset(pairs_df(n)), prompt = "q", chosen = "good", rejected = "bad")
}

test_that("dragon_map_pairs maps columns and templates", {
  ds <- pairs_ds()
  expect_equal(ds$mapping$kind, "pairs")
  expect_equal(dragonfarm:::mapping_kind(ds), "pairs")
  rows <- dragonfarm:::dataset_pairs(ds, 1:2)
  expect_length(rows, 2)
  expect_equal(rows[[1]]$prompt[[1]]$role, "user")
  expect_equal(rows[[1]]$prompt[[1]]$content, "Question 1")
  expect_equal(rows[[1]]$chosen, "Good answer 1")
  expect_equal(rows[[2]]$rejected, "Bad answer 2")

  ds2 <- dragon_map_pairs(dragon_dataset(pairs_df()), prompt = "Q: {q}", chosen = "good", rejected = "bad",
                          system = "Be brief.")
  r <- dragonfarm:::dataset_pairs(ds2, 1)[[1]]
  expect_equal(vapply(r$prompt, `[[`, character(1), "role"), c("system", "user"))
  expect_equal(r$prompt[[2]]$content, "Q: Question 1")

  expect_error(dragon_map_pairs(dragon_dataset(pairs_df()), prompt = "q", chosen = "nope", rejected = "bad"), "not found")
  expect_equal(dragonfarm:::mapping_kind(dragon_map(dragon_dataset(toy_df()), "subject", "reply")), "messages")
  expect_null(dragonfarm:::mapping_kind(dragon_dataset(toy_df())))
})

test_that("pairs print and preview", {
  ds <- pairs_ds()
  msgs <- testthat::capture_messages(print(ds))
  expect_true(any(grepl("Chosen", msgs)))
  expect_true(any(grepl("Rejected", msgs)))
  rows <- suppressMessages(dragon_preview(ds, n = 1))
  roles <- vapply(rows[[1]]$messages, `[[`, character(1), "role")
  expect_equal(roles, c("user", "chosen", "rejected"))
})

test_that("training files for pairs carry prompt, chosen, and rejected", {
  ds <- pairs_ds(40)
  dir <- tempfile("run-")
  files <- dragonfarm:::write_dataset_files(ds, dir)
  expect_equal(files$format, "pairs")
  expect_equal(files$n_train + files$n_eval, 40)
  train <- dragonfarm:::read_jsonl(file.path(dir, "data", "train.jsonl"))
  expect_setequal(names(train[[1]]), c("prompt", "chosen", "rejected"))
  expect_equal(train[[1]]$prompt[[1]]$role, "user")
  sft <- dragonfarm:::write_dataset_files(dragon_map(dragon_dataset(toy_df(40)), "subject", "reply"), tempfile("run-"))
  expect_equal(sft$format, "messages")
})

test_that("stages refuse the wrong kind of dataset before touching Python", {
  runs <- tempfile("runs-")
  expect_error(dragon_train(pairs_ds(), "x/y", runs_dir = runs), "dragon_prefer")
  expect_error(dragon_prefer(dragon_map(dragon_dataset(toy_df()), "subject", "reply"), "x/y", runs_dir = runs),
               "dragon_map_pairs")
  expect_error(dragon_prefer(pairs_ds(), "x/y", beta = 0, runs_dir = runs), "between")
  expect_error(dragon_prefer(pairs_ds(), "x/y", method = "ppo", runs_dir = runs))
  expect_error(dragon_train(dragon_dataset(toy_df()), "x/y", runs_dir = runs), "dragon_map")
})

test_that("a bundled preference run records its stage, method, and format", {
  runs <- tempfile("runs-")
  run <- suppressMessages(dragon_bundle(pairs_ds(40), "HuggingFaceTB/SmolLM2-135M-Instruct", runs_dir = runs, method = "orpo", beta = 0.2))
  cfg <- dragonfarm:::run_config(run)
  expect_equal(cfg$stage, "prefer")
  expect_equal(cfg$prefer$method, "orpo")
  expect_equal(cfg$prefer$beta, 0.2)
  expect_equal(cfg$data$format, "pairs")
  expect_null(cfg$model$base_run)
  expect_match(run$id, "-orpo$")
  df <- dragon_runs(runs)
  expect_equal(df$stage, "prefer")
  expect_equal(df$method, "orpo")
  code <- dragon_code(run)
  expect_match(code, "dragon_map_pairs(", fixed = TRUE)
  expect_match(code, "dragon_prefer(", fixed = TRUE)
  expect_match(code, 'method = "orpo"', fixed = TRUE)
  expect_match(code, "beta = 0.2", fixed = TRUE)

  sft <- suppressMessages(dragon_bundle(pairs_ds(40), "HuggingFaceTB/SmolLM2-135M-Instruct", runs_dir = runs))
  expect_equal(dragonfarm:::run_config(sft)$prefer$method, "dpo")
})

test_that("a run can start from a finished run: adapters are copied and recorded", {
  runs <- tempfile("runs-")
  dir.create(runs)
  parent_dir <- file.path(runs, "20260913-101500-smollm2")
  dir.create(parent_dir)
  file.copy(list.files(fixture_path("run1"), full.names = TRUE), parent_dir, recursive = TRUE)
  parent <- dragon_run(parent_dir)

  child <- suppressMessages(dragon_bundle(pairs_ds(40), parent, runs_dir = runs, method = "dpo"))
  cfg <- dragonfarm:::run_config(child)
  expect_equal(cfg$model$id, "HuggingFaceTB/SmolLM2-135M-Instruct")
  expect_equal(cfg$model$base_run, parent$id)
  expect_equal(unlist(cfg$model$base_adapters), "base_adapters/1")
  expect_true(file.exists(file.path(child$dir, "base_adapters", "1", "adapter_config.json")))
  expect_match(child$id, "smollm2-135m-instruct-dpo$")

  code <- dragon_code(child)
  expect_match(code, "dragon_run(", fixed = TRUE)
  expect_match(code, parent$id, fixed = TRUE)

  # the bundle zip carries the earlier adapter so the cloud side can chain too
  files <- zip::zip_list(dragonfarm:::bundle_paths(child)$zip)$filename
  expect_true("run/base_adapters/1/adapter_config.json" %in% files)

  # generation and merge would apply both adapters in order
  target <- dragonfarm:::resolve_target(parent)
  expect_length(target$base_adapters, 0)

  # a grandchild inherits the whole chain
  fake_adapter <- file.path(child$dir, "adapter")
  dir.create(fake_adapter)
  file.copy(file.path(parent_dir, "adapter", "adapter_config.json"), fake_adapter)
  grandchild <- suppressMessages(dragon_bundle(pairs_ds(40), child, runs_dir = runs))
  expect_equal(unlist(dragonfarm:::run_config(grandchild)$model$base_adapters), c("base_adapters/1", "base_adapters/2"))
  expect_equal(dragonfarm:::run_config(grandchild)$model$base_run, child$id)
  t2 <- dragonfarm:::resolve_target(grandchild_with_adapter <- {
    dir.create(file.path(grandchild$dir, "adapter"))
    file.copy(file.path(parent_dir, "adapter", "adapter_config.json"), file.path(grandchild$dir, "adapter"))
    grandchild
  })
  expect_length(t2$base_adapters, 2)
})

test_that("starting from a run without an adapter is refused", {
  runs <- tempfile("runs-")
  bundled <- suppressMessages(dragon_bundle(pairs_ds(40), "HuggingFaceTB/SmolLM2-135M-Instruct", runs_dir = runs))
  expect_error(suppressMessages(dragon_bundle(pairs_ds(40), bundled, runs_dir = runs)), "no adapter")
})

test_that("progress frames carry preference columns", {
  pr <- dragonfarm:::dragon_progress_empty()
  expect_true(all(c("pref_acc", "reward_margin", "eval_pref_acc") %in% names(pr)))
})

test_that("the mapping module handles preference pairs", {
  state <- shiny::reactiveValues(dataset = dragon_dataset(pairs_df(5)), mapped = NULL)
  shiny::testServer(dragonfarm:::mod_mapping_server, args = list(state = state, nav_to = function(p) NULL), {
    session$setInputs(mode = "pairs", prompt_tpl = "q", chosen_tpl = "good", rejected_tpl = "bad", system_tpl = "")
    m <- mapped()
    expect_s3_class(m, "dragon_dataset")
    expect_equal(dragonfarm:::mapping_kind(m), "pairs")
    session$setInputs(rejected_tpl = "")
    expect_null(mapped())
    session$setInputs(mode = "messages", response_tpl = "good")
    expect_equal(dragonfarm:::mapping_kind(mapped()), "messages")
  })
})

test_that("the train module launches a preference bundle with the chosen method", {
  runs <- tempfile("runs-")
  withr::local_options(dragonfarm.runs_dir = runs)
  ds <- dragon_dataset(pairs_df(30))
  state <- shiny::reactiveValues(
    dataset = ds, mapped = dragon_map_pairs(ds, "q", "good", "bad"),
    model = list(id = "HuggingFaceTB/SmolLM2-135M-Instruct", trust_remote_code = FALSE),
    run = NULL, hardware = NULL, cloud = NULL
  )
  shiny::testServer(dragonfarm:::mod_train_server, args = list(state = state, nav_to = function(p) NULL, runs_dir = runs), {
    session$setInputs(epochs = 1, learning_rate = 5e-5, rank = 8, max_seq_len = 256, batch_size = 2, grad_accum = 1,
                      alpha = 16, dropout = 0.05, max_steps = NA, eval_frac = 0.1, save_steps = 10, seed = 1,
                      device = "auto", dtype = "auto", grad_ckpt = FALSE, name = "", provider = "kaggle",
                      method = "orpo", beta = 0.3, base_run = "")
    expect_true(is_pairs())
    session$setInputs(bundle = 1)
    expect_s3_class(state$run, "dragon_run")
    cfg <- dragonfarm:::run_config(state$run)
    expect_equal(cfg$stage, "prefer")
    expect_equal(cfg$prefer$method, "orpo")
    expect_equal(cfg$prefer$beta, 0.3)
  })
})

test_that("runs started in the same second get distinct directories", {
  runs <- tempfile("runs-")
  a <- suppressMessages(dragon_bundle(pairs_ds(30), "HuggingFaceTB/SmolLM2-135M-Instruct", runs_dir = runs))
  b <- suppressMessages(dragon_bundle(pairs_ds(30), "HuggingFaceTB/SmolLM2-135M-Instruct", runs_dir = runs))
  expect_false(identical(a$dir, b$dir))
  expect_equal(nrow(dragon_runs(runs)), 2)
})
