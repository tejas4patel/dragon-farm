test_that("runs_change_signature changes when any file under the directory changes", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "run-1"))
  writeLines("{}", file.path(dir, "run-1", "status.json"))

  sig1 <- runs_change_signature(dir)

  # A file other than status.json (e.g. the adapter, written after training
  # finishes) must also be enough to change the signature -- this is exactly
  # the case that a checkFunc watching only status.json's own mtime missed.
  Sys.sleep(0.01)
  dir.create(file.path(dir, "run-1", "adapter"))
  writeLines("{}", file.path(dir, "run-1", "adapter", "adapter_config.json"))
  sig2 <- runs_change_signature(dir)

  expect_false(identical(sig1, sig2))
})

test_that("runs_change_signature changes when a run is renamed (archived/restored)", {
  # A rename does not touch mtimes, only paths -- exactly what dragon_archive_run()
  # and dragon_unarchive_run() do, and what test-monitor.R exercises end to end.
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "run-1"))
  writeLines("{}", file.path(dir, "run-1", "status.json"))

  sig1 <- runs_change_signature(dir)
  file.rename(file.path(dir, "run-1"), file.path(dir, "archived-run-1"))
  sig2 <- runs_change_signature(dir)

  expect_false(identical(sig1, sig2))
})

test_that("runs_change_signature is stable when nothing has changed", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "run-1"))
  writeLines("{}", file.path(dir, "run-1", "status.json"))

  expect_identical(runs_change_signature(dir), runs_change_signature(dir))
})

test_that("runs_change_signature handles an empty or missing directory", {
  dir <- withr::local_tempdir()
  expect_identical(runs_change_signature(dir), "")
  expect_identical(runs_change_signature(file.path(dir, "does-not-exist")), "")
})

test_that("runs_change_signature does not walk deeper than a run's own files", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "run-1", "checkpoints", "step-10"), recursive = TRUE)
  writeLines("{}", file.path(dir, "run-1", "status.json"))
  writeLines("x", file.path(dir, "run-1", "checkpoints", "step-10", "weights.bin"))
  sig <- runs_change_signature(dir)
  expect_false(grepl("weights.bin", sig, fixed = TRUE))
  expect_true(grepl("status.json", sig, fixed = TRUE))
  expect_true(grepl("checkpoints", sig, fixed = TRUE))
})

test_that("a model id that does not exist gets a plain message and a suggestion", {
  raw <- paste("OSError: Qwen/Qwen2.5-3B-Instuct is not a local folder and is not a valid model identifier listed on",
               "'https://huggingface.co/models' If this is a private repository, make sure to pass a token")
  msg <- dragonfarm:::explain_error(raw)
  expect_match(msg, "There is no model called \"Qwen/Qwen2.5-3B-Instuct\"", fixed = TRUE)
  expect_match(msg, "Did you mean \"Qwen/Qwen2.5-3B-Instruct\"?", fixed = TRUE)
  far <- dragonfarm:::explain_error("OSError: nobody/nothing-like-it is not a local folder and is not a valid model identifier")
  expect_false(grepl("Did you mean", far))
  expect_equal(dragonfarm:::explain_error("CUDA out of memory"), "CUDA out of memory")
})
