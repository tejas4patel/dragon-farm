# A reply that arrives after R stopped waiting for it (a timeout, an
# interrupt) used to be taken as the answer to the next request, shifting
# every later answer by one question. Requests now carry an id and lines for
# another id are skipped.

fake_worker <- function(reply) {
  env <- new.env()
  env$out <- character()
  env$sent <- list()
  env$write_input <- function(x) {
    req <- jsonlite::fromJSON(rawToChar(x), simplifyVector = FALSE)
    env$sent[[length(env$sent) + 1]] <- req
    env$out <- c(env$out, reply(req))
    raw(0)
  }
  env$poll_io <- function(ms) invisible(NULL)
  env$read_output <- function() {
    if (!length(env$out)) return("")
    o <- paste0(paste(env$out, collapse = "\n"), "\n")
    env$out <- character()
    o
  }
  env$is_alive <- function() TRUE
  env
}

with_fake_worker <- function(p, code) {
  state <- dragonfarm:::the
  old <- list(worker = state$worker, buf = state$worker_buf, seq = state$worker_seq)
  on.exit({ state$worker <- old$worker; state$worker_buf <- old$buf; state$worker_seq <- old$seq })
  state$worker <- p
  state$worker_buf <- ""
  force(code)
}

test_that("a late reply to an earlier request is not taken as the answer", {
  p <- fake_worker(function(req) c(
    sprintf('{"ok": true, "outputs": ["stale answer"], "id": %d}', req$id - 1L),
    sprintf('{"ok": false, "error": "stale error", "id": %d}', req$id - 1L),
    sprintf('{"ok": true, "outputs": ["answer %d"], "id": %d}', req$id, req$id)
  ))
  with_fake_worker(p, {
    r1 <- dragonfarm:::worker_request(list(op = "generate"))
    r2 <- dragonfarm:::worker_request(list(op = "generate"))
    expect_equal(r1$outputs[[1]], paste("answer", p$sent[[1]]$id))
    expect_equal(r2$outputs[[1]], paste("answer", p$sent[[2]]$id))
    expect_false(identical(p$sent[[1]]$id, p$sent[[2]]$id))
  })
})

test_that("streamed tokens for another request are not passed on", {
  p <- fake_worker(function(req) c(
    sprintf('{"ok": true, "token": "old", "id": %d}', req$id - 1L),
    sprintf('{"ok": true, "token": "new", "id": %d}', req$id),
    sprintf('{"ok": true, "done": true, "output": "new", "id": %d}', req$id)
  ))
  with_fake_worker(p, {
    seen <- character()
    r <- dragonfarm:::worker_request(list(op = "generate", stream = TRUE), on_token = function(t) seen <<- c(seen, t))
    expect_equal(seen, "new")
    expect_equal(r$output, "new")
  })
})

test_that("replies without an id are still accepted", {
  p <- fake_worker(function(req) '{"ok": true, "pong": true}')
  with_fake_worker(p, expect_true(dragonfarm:::worker_request(list(op = "ping"))$pong))
})
