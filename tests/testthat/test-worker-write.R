# Large requests to the inference worker must arrive whole. processx's
# write_input() is non-blocking: it returns the part of the input that did
# not fit in the pipe, and a 300-question retrieval request used to stop
# short of its newline, leaving R and the worker each waiting for the other.

fake_pipe <- function(capacity) {
  env <- new.env()
  env$received <- raw()
  env$polls <- 0L
  env$write_input <- function(bytes) {
    if (is.character(bytes)) bytes <- charToRaw(bytes)
    take <- min(capacity, length(bytes))
    if (take == 0) return(invisible(bytes))
    env$received <- c(env$received, bytes[seq_len(take)])
    invisible(bytes[-seq_len(take)])
  }
  env$poll_io <- function(ms) { env$polls <- env$polls + 1L; invisible(NULL) }
  env
}

test_that("a request larger than the pipe buffer is written completely", {
  p <- fake_pipe(1000)
  text <- paste0(paste(rep("x", 25000), collapse = ""), "\n")
  dragonfarm:::worker_write(p, text)
  expect_equal(rawToChar(p$received), text)
  expect_equal(p$polls, 25L)
})

test_that("a small request needs one write and no polling", {
  p <- fake_pipe(4096)
  dragonfarm:::worker_write(p, "{\"op\": \"quit\"}\n")
  expect_equal(rawToChar(p$received), "{\"op\": \"quit\"}\n")
  expect_equal(p$polls, 0L)
})

test_that("a pipe that never drains gives a clear error instead of spinning", {
  p <- fake_pipe(0)
  expect_error(dragonfarm:::worker_write(p, "hello\n", timeout = 0.2), "within 0.2 seconds")
})
