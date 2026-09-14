fixture_path <- function(...) testthat::test_path("fixtures", ...)

# Copy the finished-run fixture into a temp dir so tests can mutate it.
copy_fixture_run <- function() {
  dst <- file.path(tempfile("run-"), "20260913-101500-smollm2")
  dir.create(dst, recursive = TRUE)
  file.copy(list.files(fixture_path("run1"), full.names = TRUE), dst, recursive = TRUE)
  dst
}

toy_df <- function(n = 30) {
  data.frame(
    subject = paste("Subject", seq_len(n)),
    body = paste("Body text", seq_len(n)),
    reply = paste("Reply", seq_len(n)),
    stringsAsFactors = FALSE
  )
}
