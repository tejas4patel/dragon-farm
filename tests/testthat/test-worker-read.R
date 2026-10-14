# Replies from the inference worker arrive as raw text in pieces; a reply
# longer than processx's line buffer (a retrieval for a few hundred
# questions) used to come back split, no piece parsed as JSON, and R waited
# for a complete line that never came.

fake_output <- function(pieces) {
  env <- new.env()
  env$pieces <- pieces
  env$read_output <- function() {
    if (!length(env$pieces)) return("")
    out <- env$pieces[[1]]
    env$pieces <- env$pieces[-1]
    out
  }
  env
}

test_that("a long line split across reads is reassembled before parsing", {
  state <- dragonfarm:::the; state$worker_buf <- ""
  big <- paste(rep("x", 70000), collapse = "")
  p <- fake_output(list(paste0('{"ok": true, "big": "', substr(big, 1, 30000)),
                        substr(big, 30001, 70000),
                        '"}\n{"ok": true, "token": "a"}\n'))
  expect_equal(dragonfarm:::worker_lines(p), character())
  expect_equal(dragonfarm:::worker_lines(p), character())
  lines <- dragonfarm:::worker_lines(p)
  expect_length(lines, 2)
  expect_equal(nchar(jsonlite::fromJSON(lines[1])$big), 70000)
  expect_equal(jsonlite::fromJSON(lines[2])$token, "a")
  expect_equal(dragonfarm:::the$worker_buf, "")
})

test_that("a partial trailing line waits for the rest", {
  state <- dragonfarm:::the; state$worker_buf <- ""
  p <- fake_output(list('{"ok": true}\n{"ok": tr', 'ue, "n": 2}\n'))
  expect_equal(dragonfarm:::worker_lines(p), '{"ok": true}')
  expect_equal(dragonfarm:::the$worker_buf, '{"ok": tr')
  expect_equal(dragonfarm:::worker_lines(p), '{"ok": true, "n": 2}')
  expect_equal(dragonfarm:::worker_lines(p), character())
})
