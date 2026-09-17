test_that("launch_trainer stops the local inference worker first, if one is running", {
  # Two heavy Python/CUDA processes starting at once has crashed a fresh
  # trainer on Windows; stopping an already-loaded worker first avoids the
  # most common way that happens. Stand in for the Python interpreter with
  # Rscript so no real training is attempted.
  stopped <- FALSE
  testthat::local_mocked_bindings(
    dragon_python = function(quiet = FALSE) file.path(R.home("bin"), "Rscript"),
    worker_alive = function() TRUE,
    dragon_worker_stop = function() { stopped <<- TRUE; invisible(TRUE) }
  )
  run_dir <- tempfile("run-")
  dir.create(run_dir)
  run <- dragonfarm:::launch_trainer(run_dir)
  withr::defer(if (run$process$is_alive()) run$process$kill())
  expect_true(stopped)
  expect_s3_class(run, "dragon_run")
})

test_that("launch_trainer leaves the worker alone when none is running", {
  stopped <- FALSE
  testthat::local_mocked_bindings(
    dragon_python = function(quiet = FALSE) file.path(R.home("bin"), "Rscript"),
    worker_alive = function() FALSE,
    dragon_worker_stop = function() { stopped <<- TRUE; invisible(TRUE) }
  )
  run_dir <- tempfile("run-")
  dir.create(run_dir)
  run <- dragonfarm:::launch_trainer(run_dir)
  withr::defer(if (run$process$is_alive()) run$process$kill())
  expect_false(stopped)
})
