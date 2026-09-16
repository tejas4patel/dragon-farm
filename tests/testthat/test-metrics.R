m <- dragonfarm::dragon_metrics()

test_that("exact and contains normalize case, whitespace, and trailing punctuation", {
  expect_equal(m$exact(c("Paris.", " PARIS ", "Lyon"), c("paris", "Paris", "Paris"), ""), c(1, 1, 0))
  expect_equal(m$contains(c("The capital is Paris.", "Nope", ""), c("paris", "paris", "x"), ""), c(1, 0, 0))
  expect_equal(m$contains("anything", "", ""), 0)
})

test_that("token F1 gives partial credit", {
  expect_equal(m$token_f1("the cat sat", "the cat sat", ""), 1)
  expect_equal(m$token_f1("dog", "cat", ""), 0)
  f1 <- m$token_f1("the cat sat on the mat", "a cat sat on a mat", "")
  expect_gt(f1, 0.5)
  expect_lt(f1, 1)
  expect_equal(m$token_f1("", "", ""), 1)
  expect_equal(m$token_f1("", "cat", ""), 0)
  # repeated tokens are counted with multiplicity
  expect_equal(m$token_f1("a a", "a", ""), 2 * 1 * 0.5 / 1.5)
})

test_that("json_valid unwraps fences and rejects prose", {
  expect_equal(m$json_valid(c('{"a": 1}', "```json\n{\"a\": [1, 2]}\n```", "not json", NA), "", ""), c(1, 1, 0, 0))
})

test_that("numeric compares the last number with tolerance", {
  expect_equal(m$numeric(c("The total is $1,234.50", "42 then 43", "none"), c("1234.5", "43", "1"), ""), c(1, 1, 0))
  expect_equal(m$numeric("3.0000001", "3", ""), 1)
  expect_equal(m$numeric("3.1", "3", ""), 0)
})

test_that("length_ratio and regex metrics behave", {
  expect_equal(m$length_ratio(c("abcd", "ab"), c("ab", ""), ""), c(2, NA))
  starts <- dragon_metric_regex("^T-\\d{4}")
  expect_equal(starts(c("T-0001: fixed", "t-0002", "no id"), "", ""), c(1, 1, 0))
  expect_equal(dragon_metric_regex("T-", ignore_case = FALSE)("t-1", "", ""), 0)
})

test_that("metric selection resolves names, functions, and rejects unknowns", {
  expect_named(dragonfarm:::resolve_metrics(TRUE), names(m))
  expect_named(dragonfarm:::resolve_metrics(c("exact", "numeric")), c("exact", "numeric"))
  expect_length(dragonfarm:::resolve_metrics(NULL), 0)
  custom <- dragonfarm:::resolve_metrics(list(short = function(g, r, p) as.numeric(nchar(g) < 5), em = "exact"))
  expect_named(custom, c("short", "em"))
  expect_error(dragonfarm:::resolve_metrics("nope"), "Unknown metric")
  expect_error(dragonfarm:::resolve_metrics(list(function(g, r, p) 1)), "named list")
})

test_that("compute_metrics adds columns and a summary", {
  samples <- data.frame(prompt = c("q1", "q2"), reference = c("Paris", "4"),
                        generated = c("paris", "The answer is 5"), stringsAsFactors = FALSE)
  res <- dragonfarm:::compute_metrics(samples, c("exact", "numeric"))
  expect_equal(res$per_sample$exact, c(1, 0))
  expect_equal(res$per_sample$numeric, c(0, 0))
  expect_equal(res$summary[["exact"]], 0.5)
  bad <- list(wrong = function(g, r, p) 1)
  expect_error(dragonfarm:::compute_metrics(samples, bad), "returned 1 values")
  empty <- dragonfarm:::compute_metrics(samples[0, ], TRUE)
  expect_length(empty$summary, 0)
})

# The fixture run saved 2 sample generations; tell its config that 2 rows were
# held out so metrics can be computed from disk without loading the model.
fixture_run_with_full_samples <- function(dir = copy_fixture_run()) {
  cfg <- dragonfarm:::read_json(file.path(dir, "config.json"))
  cfg$data$n_eval <- 2L
  dragonfarm:::write_json(cfg, file.path(dir, "config.json"))
  dragon_run(dir)
}

test_that("dragon_evaluate computes metrics from saved samples when they cover the held-out set", {
  run <- fixture_run_with_full_samples()
  ev <- dragon_evaluate(run, metrics = c("exact", "token_f1", "length_ratio"))
  expect_named(ev$metrics, c("exact", "token_f1", "length_ratio"))
  expect_true(file.exists(file.path(run$dir, "metrics.json")))
  st <- dragon_status(run)
  expect_equal(st$metrics$exact, ev$metrics[["exact"]])
  expect_true("token_f1" %in% names(ev$samples))
  msgs <- testthat::capture_messages(print(ev))
  expect_true(any(grepl("token_f1", msgs)))
})

test_that("dragon_compare gathers runs and their measurements", {
  runs <- tempfile("runs-")
  dir.create(runs)
  a <- file.path(runs, "20260913-101500-smollm2")
  dir.create(a)
  file.copy(list.files(fixture_path("run1"), full.names = TRUE), a, recursive = TRUE)
  ra <- fixture_run_with_full_samples(a)
  dragon_evaluate(ra, metrics = "exact")
  st <- dragonfarm:::read_json(file.path(a, "status.json"))
  st$judge <- list(mode = "pairwise", win_rate = 0.75, n = 8)
  dragonfarm:::write_json(st, file.path(a, "status.json"))
  ds <- dragon_map(dragon_dataset(toy_df(30)), "subject", "reply")
  rb <- suppressMessages(dragon_bundle(ds, "HuggingFaceTB/SmolLM2-135M-Instruct", runs_dir = runs))

  cmp <- dragon_compare(runs_dir = runs)
  expect_s3_class(cmp, "dragon_comparison")
  expect_equal(nrow(cmp), 2)
  row <- cmp[cmp$id == ra$id, ]
  expect_equal(row$eval_loss, 1.644)
  expect_equal(row$judge, 0.75)
  expect_equal(row$judge_n, 8L)
  expect_true("exact" %in% names(cmp))
  expect_true(is.na(cmp[cmp$id == rb$id, "eval_loss"]))
  expect_equal(cmp[cmp$id == rb$id, "state"], "bundled")

  two <- dragon_compare(ra, rb$dir)
  expect_equal(two$id, c(ra$id, rb$id))
  expect_output(print(two), ra$id)
  expect_equal(nrow(dragon_compare(runs_dir = tempfile())), 0)
})
