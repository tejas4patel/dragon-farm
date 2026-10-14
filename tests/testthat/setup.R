# Machine-independent defaults for the whole suite.
withr::local_options(dragonfarm.scan_workers = FALSE, .local_envir = testthat::teardown_env())
