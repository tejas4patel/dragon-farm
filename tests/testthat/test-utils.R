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
