fixture_with_samples <- function(dir = copy_fixture_run()) {
  cfg <- dragonfarm:::read_json(file.path(dir, "config.json"))
  cfg$data$n_eval <- 2L
  dragonfarm:::write_json(cfg, file.path(dir, "config.json"))
  dragon_run(dir)
}

test_that("step constructors validate their inputs", {
  ds <- dragon_map(dragon_dataset(toy_df()), "subject", "reply")
  pairs <- dragon_map_pairs(dragon_dataset(data.frame(q = "a", g = "b", b = "c")), "q", "g", "b")
  expect_s3_class(dragon_step_train(ds), "dragon_step")
  expect_error(dragon_step_train(pairs), "dragon_map")
  expect_equal(dragon_step_prefer()$method, "dpo")
  expect_error(dragon_step_prefer(ds), "dragon_map_pairs")
  expect_error(dragon_step_synthesize_pairs(), "judge")
  expect_equal(dragon_step_synthesize_pairs(judge = function(p) p, n = 10)$n, 10)
  expect_error(dragon_step_judge(), "judge")
  expect_equal(dragon_step_evaluate("exact")$metrics, "exact")
  expect_error(dragon_step_evaluate("nope"), "Unknown")
  prompts <- dragon_map_prompts(dragon_dataset(data.frame(q = "a")), "q")
  rl <- dragon_step_reinforce(prompts, rewards = dragon_reward("json"))
  expect_equal(rl$rewards[[1]]$type, "json")
  expect_error(dragon_step_reinforce(ds, rewards = dragon_reward("json")), "dragon_map_prompts")
  expect_error(dragonfarm:::check_steps(list("train")), "dragon_step")
  expect_length(dragonfarm:::check_steps(dragon_step_evaluate()), 1)
  msgs <- testthat::capture_messages(print(dragon_step_evaluate()))
  expect_true(any(grepl("evaluate", msgs)))
})

test_that("a pipeline runs steps in order, records progress, and compares its runs", {
  runs <- tempfile("runs-")
  dir.create(runs)
  parent_dir <- file.path(runs, "20260913-101500-smollm2")
  dir.create(parent_dir)
  file.copy(list.files(fixture_path("run1"), full.names = TRUE), parent_dir, recursive = TRUE)
  run <- fixture_with_samples(parent_dir)

  p <- suppressMessages(dragon_pipeline(run, list(dragon_step_evaluate(metrics = c("exact", "token_f1"))), runs_dir = runs, name = "eval only"))
  expect_s3_class(p, "dragon_pipeline")
  expect_equal(p$status, "succeeded")
  expect_match(p$id, "-eval-only$")
  expect_equal(p$steps[[1]]$state, "succeeded")
  expect_named(p$results[[1]]$metrics, c("exact", "token_f1"))
  expect_true(file.exists(p$path))
  rec <- dragon_pipeline_status(p$id, runs_dir = runs)
  expect_equal(rec$status, "succeeded")
  expect_equal(rec$steps[[1]]$type, "evaluate")
  msgs <- testthat::capture_messages(print(rec))
  expect_true(any(grepl("succeeded", msgs)))
  expect_true(any(grepl("evaluate", testthat::capture_messages(print(p)))))
  expect_equal(dragon_status(run)$metrics$exact, p$results[[1]]$metrics$exact)
})

test_that("a failing step is recorded and the error propagates", {
  runs <- tempfile("runs-")
  err <- tryCatch(
    suppressMessages(dragon_pipeline("HuggingFaceTB/SmolLM2-135M-Instruct", list(dragon_step_prefer()), runs_dir = runs)),
    error = function(e) e
  )
  expect_s3_class(err, "error")
  expect_match(conditionMessage(err), "failed at step 1")
  recs <- list.files(file.path(runs, "pipelines"), pattern = "\\.json$", full.names = TRUE)
  expect_length(recs, 1)
  rec <- dragonfarm:::read_json(recs[1])
  expect_equal(rec$status, "failed")
  expect_equal(rec$steps[[1]]$state, "failed")
  expect_match(rec$steps[[1]]$error, "no pairs")
  expect_error(dragon_pipeline_status("nope", runs_dir = runs), "No pipeline record")
  expect_error(dragon_pipeline("x/y", list()), "dragon_step")
})

test_that("background pipelines serialize their spec and build a loader script", {
  run <- fixture_with_samples()
  spec <- dragonfarm:::strip_handles(list(model = run, steps = list(dragon_step_evaluate())))
  expect_null(spec$model$process)
  expect_s3_class(spec$model, "dragon_run")
  script <- dragonfarm:::pipeline_script(tempfile(fileext = ".rds"))
  expect_match(script, "run_pipeline_file", fixed = TRUE)
  expect_match(script, "dragonfarm", fixed = TRUE)
})

test_that("lineage ordering nests children under parents", {
  o <- dragonfarm:::lineage_order(c("a", "b", "c", "d"), c(NA, "a", "b", NA))
  expect_equal(o$id, c("a", "b", "c", "d"))
  expect_equal(o$depth, c(0L, 1L, 2L, 0L))
  o2 <- dragonfarm:::lineage_order(c("x", "y"), c("gone", "x"))
  expect_equal(o2$id, c("x", "y"))
  expect_equal(o2$depth, c(0L, 1L))
})

test_that("the pipeline module refuses to start without inputs and lists records", {
  runs <- tempfile("runs-")
  dir.create(file.path(runs, "pipelines"), recursive = TRUE)
  dragonfarm:::write_json(list(id = "p1", status = "succeeded", steps = list(list(type = "train", state = "succeeded", run = "r1"))),
                          file.path(runs, "pipelines", "p1.json"))
  state <- shiny::reactiveValues(dataset = NULL, mapped = NULL, model = NULL, run = NULL)
  shiny::testServer(dragonfarm:::mod_pipeline_server, args = list(state = state, runs_dir = runs), {
    session$setInputs(judge_kind = "local", judge_model = "org/m", pair_prompts = 10, judge_n = 4)
    expect_length(problems(), 2)
    state$mapped <- dragon_map(dragon_dataset(toy_df()), "subject", "reply")
    state$model <- list(id = "x/y")
    expect_length(problems(), 0)
    recs <- records()
    expect_length(recs, 1)
    expect_equal(recs[[1]]$id, "p1")
  })
})
