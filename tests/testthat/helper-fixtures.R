fixture_path <- function(...) testthat::test_path("fixtures", ...)

# Copy the finished-run fixture into a temp dir so tests can mutate it.
copy_fixture_run <- function() {
  dst <- file.path(tempfile("run-"), "20260913-101500-smollm2")
  dir.create(dst, recursive = TRUE)
  file.copy(list.files(fixture_path("run1"), full.names = TRUE), dst, recursive = TRUE)
  dst
}

# Same as copy_fixture_run(), opened as a dragon_run, with eval samples so
# eval-only steps (evaluate, judge) have something to score.
fixture_with_samples <- function(dir = copy_fixture_run()) {
  cfg <- dragonfarm:::read_json(file.path(dir, "config.json"))
  cfg$data$n_eval <- 2L
  dragonfarm:::write_json(cfg, file.path(dir, "config.json"))
  dragon_run(dir)
}

toy_df <- function(n = 30) {
  data.frame(
    subject = paste("Subject", seq_len(n)),
    body = paste("Body text", seq_len(n)),
    reply = paste("Reply", seq_len(n)),
    stringsAsFactors = FALSE
  )
}
