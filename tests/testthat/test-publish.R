test_that("dragon_publish validates the repo id and requires a token", {
  run <- dragon_run(fixture_with_samples())
  testthat::local_mocked_bindings(hf_token_present = function() FALSE)
  expect_error(dragon_publish(run, "not-a-valid-repo"), "username/name")
  expect_error(dragon_publish(run, "user/name"), "HF_TOKEN")
})

test_that("dragon_publish (merged) merges first if needed, then uploads the merged dir", {
  run <- dragon_run(fixture_with_samples())
  calls <- list()
  testthat::local_mocked_bindings(
    hf_token_present = function() TRUE,
    dragon_merge = function(run, out_dir = NULL) {
      calls[["merge"]] <<- run$id
      dir <- run_path(run, "merged")
      dir.create(dir, showWarnings = FALSE)
      writeLines("{}", file.path(dir, "config.json"))
      dir
    },
    run_python = function(module, args = character(), ...) {
      calls[["module"]] <<- module
      calls[["args"]] <<- args
      list(status = 0L, stdout = "https://huggingface.co/user/name\n", stderr = "")
    }
  )
  url <- dragon_publish(run, "user/name")
  expect_equal(url, "https://huggingface.co/user/name")
  expect_equal(calls$merge, run$id)   # no merged/ existed yet, so it merged first
  expect_equal(calls$module, "dragonfarm.publish")
  expect_equal(calls$args[c(1, 3)], c("--dir", "--repo"))
  expect_true("user/name" %in% calls$args)
  expect_false("--private" %in% calls$args)

  # a second call, now that merged/ exists, should not merge again
  calls2 <- list()
  testthat::local_mocked_bindings(
    hf_token_present = function() TRUE,
    dragon_merge = function(...) { calls2[["merge"]] <<- TRUE; cli::cli_abort("should not be called") },
    run_python = function(module, args = character(), ...) {
      calls2[["args"]] <<- args
      list(status = 0L, stdout = "", stderr = "")
    }
  )
  url2 <- dragon_publish(run, "user/name2", private = TRUE, commit_message = "hello")
  expect_null(calls2$merge)
  expect_true("--private" %in% calls2$args)
  expect_true("hello" %in% calls2$args)
  expect_equal(url2, "https://huggingface.co/user/name2")
})

test_that("dragon_publish (adapter) uploads the adapter directory and surfaces python failures", {
  run <- dragon_run(fixture_with_samples())
  target <- resolve_target(run)
  calls <- list()
  testthat::local_mocked_bindings(
    hf_token_present = function() TRUE,
    run_python = function(module, args = character(), ...) {
      calls[["args"]] <<- args
      list(status = 0L, stdout = "", stderr = "")
    }
  )
  dragon_publish(run, "user/adapter-only", what = "adapter")
  dir_arg <- calls$args[which(calls$args == "--dir") + 1]
  expect_equal(normalizePath(dir_arg, winslash = "/"), normalizePath(target$adapter, winslash = "/"))

  testthat::local_mocked_bindings(
    hf_token_present = function() TRUE,
    run_python = function(...) list(status = 1L, stdout = "", stderr = "boom: no network")
  )
  expect_error(dragon_publish(run, "user/adapter-only", what = "adapter"), "boom")
})
