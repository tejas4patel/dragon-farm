# dragon_ask(), dragon_retrieve() shaping, and chat-with-documents, with the
# worker and backend mocked. The real path runs under DRAGONFARM_INTEGRATION=true.

fake_hits <- function(n = 3) {
  data.frame(
    n = seq_len(n), id = sprintf("abc-%03d", seq_len(n) - 1), source = c("policy.pdf", "policy.pdf", "NEWS.md")[seq_len(n)],
    section = c("Returns", "Warranty", "1.1.0")[seq_len(n)],
    text = c("Any device can be returned within 30 days.", "Every device has a 2-year warranty.", "Changed things.")[seq_len(n)],
    score = c(0.8, 0.6, 0.4)[seq_len(n)], similarity = c(0.8, 0.6, 0.57)[seq_len(n)], weight = c(1, 1, 0.7)[seq_len(n)],
    stringsAsFactors = FALSE
  )
}

test_that("the documents prompt numbers excerpts and the parser reads citations back", {
  p <- dragonfarm:::documents_prompt("How long is the return window?", fake_hits())
  expect_match(p, "\\[1\\] policy.pdf . Returns\nAny device can be returned within 30 days.", perl = TRUE)
  expect_match(p, "\\[3\\] NEWS.md . 1.1.0")
  expect_match(p, "Question: How long is the return window\\?$")
  expect_match(dragonfarm:::documents_prompt("q", fake_hits(0)), "No excerpts were found")

  expect_equal(dragonfarm:::parse_citations("Thirty days [1]. Also [1, 3] and [2][3].", 3), 1:3)
  expect_equal(dragonfarm:::parse_citations("Thirty days [1]. See [9].", 3), 1L)
  expect_equal(dragonfarm:::parse_citations("No citations here.", 3), integer())
  expect_equal(dragonfarm:::parse_citations("", 3), integer())
  expect_match(dragonfarm:::documents_system(), "only the numbered excerpts")
  expect_match(dragonfarm:::documents_system("Answer in French."), "Answer in French\\.$")
})

test_that("dragon_ask retrieves, asks the backend with the excerpts, and marks cited sources", {
  f <- write_fake_set()
  docs <- dragon_documents_load(f$dir)
  seen <- NULL
  testthat::local_mocked_bindings(
    dragon_retrieve = function(docs, query, k = 4) fake_hits(),
    default_answer_model = function() "Qwen/Qwen2.5-1.5B-Instruct",
    worker_start = function(backend = NULL) invisible(NULL),
    worker_request = function(req, on_token = NULL, timeout = 3600) {
      seen <<- req
      list(outputs = list("You can return it within 30 days [1]. The warranty is two years [2]."))
    }
  )
  ans <- dragon_ask(docs, "How long is the return window?")
  expect_s3_class(ans, "dragon_answer")
  expect_equal(ans$model, "Qwen/Qwen2.5-1.5B-Instruct")
  expect_equal(seen$model, "Qwen/Qwen2.5-1.5B-Instruct")
  expect_equal(seen$temperature, 0)
  expect_equal(seen$conversations[[1]][[1]]$role, "system")
  expect_match(seen$conversations[[1]][[2]]$content, "\\[2\\] policy.pdf . Warranty")
  expect_equal(ans$sources$cited, c(TRUE, TRUE, FALSE))
  out <- capture.output(print(ans))
  expect_true(any(grepl("^\\[1\\]\\* policy.pdf", out)))
  expect_true(any(grepl("^\\[3\\]  NEWS.md", out)))

  ans2 <- dragon_ask(docs, "q", model = "my/model", system = "Answer in French.")
  expect_equal(seen$model, "my/model")
  expect_match(seen$conversations[[1]][[1]]$content, "Answer in French")
  expect_error(dragon_ask(docs, ""), "question")
  expect_error(dragon_ask(docs, "q", backend = "nope"), "backend")
})

test_that("dragon_retrieve shapes worker hits into a data frame", {
  f <- write_fake_set()
  docs <- dragon_documents_load(f$dir)
  docs$manifest$index <- list(model = "stub")   # pretend it is indexed
  testthat::local_mocked_bindings(
    worker_start = function(backend = NULL) invisible(NULL),
    worker_request = function(req, on_token = NULL, timeout = 3600) {
      expect_equal(req$op, "retrieve"); expect_equal(req$k, 2L)
      list(hits = lapply(req$queries, function(q) list(list(id = "abc-001", score = 0.9, similarity = 0.9),
                                                       list(id = "def-000", score = 0.35, similarity = 0.5))))
    }
  )
  h <- dragon_retrieve(docs, "warranty", k = 2)
  expect_equal(h$n, 1:2)
  expect_equal(h$section, c("Warranty", "1.1.0"))
  expect_equal(h$weight, c(1, 0.7))
  expect_null(h$query)
  h2 <- dragon_retrieve(docs, c("a", "b"), k = 2)
  expect_equal(nrow(h2), 4L)
  expect_equal(unique(h2$query), c("a", "b"))
  expect_error(dragon_retrieve(docs, character()), "query")
})

test_that("a chat with documents sends excerpts to the model but keeps plain history", {
  f <- write_fake_set()
  docs <- dragon_documents_load(f$dir)
  sent <- list()
  testthat::local_mocked_bindings(
    dragon_retrieve = function(docs, query, k = 4) fake_hits(2),
    default_answer_model = function() "Qwen/Qwen2.5-1.5B-Instruct",
    worker_start = function(backend = NULL) invisible(NULL),
    worker_request = function(req, on_token = NULL, timeout = 3600) {
      sent[[length(sent) + 1]] <<- req$conversations[[1]]
      list(outputs = list("Thirty days [1]."))
    }
  )
  ch <- dragon_chat(documents = docs)          # no x: falls back to the recommended model
  ch$say("How long is the return window?")
  convo <- sent[[1]]
  expect_equal(convo[[1]]$role, "system")
  expect_match(convo[[1]]$content, "numbered excerpts")
  expect_match(convo[[2]]$content, "\\[1\\] policy.pdf")
  expect_equal(ch$history()[[1]]$content, "How long is the return window?")   # plain, not the wrapped prompt
  expect_equal(ch$sources()$cited, c(TRUE, FALSE))
  ch$say("And the warranty?")
  convo2 <- sent[[2]]
  expect_equal(convo2[[2]]$content, "How long is the return window?")   # earlier turns stay plain in the context
  expect_match(convo2[[4]]$content, "Question: And the warranty\\?$")
})

test_that("documents are indexed and asked for real", {
  skip_if_not(identical(Sys.getenv("DRAGONFARM_INTEGRATION"), "true"), "set DRAGONFARM_INTEGRATION=true")
  skip_on_cran()
  src <- tempfile("src-"); dir.create(src)
  writeLines(c("# Returns", "", paste(rep("Any device can be returned within 30 days of delivery for a full refund.", 6), collapse = " "),
               "", "# Warranty", "", paste(rep("Every device carries a 2-year limited warranty counted from the delivery date.", 6), collapse = " "),
               "", "# Wi-Fi", "", paste(rep("Wi-Fi drops come from band steering on mesh routers; use the 2.4 GHz band.", 6), collapse = " ")),
             file.path(src, "policy.md"))
  runs_dir <- tempfile("runs-")
  docs <- dragon_documents(src, name = "ask-test", runs_dir = runs_dir)
  expect_false(is.null(docs$manifest$index))
  h <- dragon_retrieve(docs, "How long is the warranty?", k = 2)
  expect_equal(h$section[1], "Warranty")
  ans <- dragon_ask(docs, "How long is the warranty?", model = "HuggingFaceTB/SmolLM2-135M-Instruct", k = 2, max_new_tokens = 40)
  expect_true(nzchar(ans$answer))
  expect_equal(nrow(ans$sources), 2L)
  dragon_worker_stop()
})

test_that("a reply that is only a citation is asked again once", {
  expect_true(dragonfarm:::citation_only("[1]"))
  expect_true(dragonfarm:::citation_only("[1], [2]"))
  expect_true(dragonfarm:::citation_only(""))
  expect_false(dragonfarm:::citation_only("Thirty days [1]."))
  expect_false(dragonfarm:::citation_only("2 years [2]"))

  f <- write_fake_set()
  docs <- dragon_documents_load(f$dir)
  replies <- list("[1]", "You can return it within 30 days [1].")
  seen <- list()
  testthat::local_mocked_bindings(
    dragon_retrieve = function(docs, query, k = 4) fake_hits(),
    default_answer_model = function() "Qwen/Qwen2.5-3B-Instruct",
    worker_start = function(backend = NULL) invisible(NULL),
    worker_request = function(req, on_token = NULL, timeout = 3600) {
      seen[[length(seen) + 1]] <<- req
      out <- replies[[1]]; replies <<- replies[-1]
      list(outputs = list(out))
    }
  )
  ans <- dragon_ask(docs, "How long is the return window?")
  expect_equal(ans$answer, "You can return it within 30 days [1].")
  expect_length(seen, 2)
  retry <- seen[[2]]$conversations[[1]]
  expect_equal(vapply(retry, `[[`, "", "role"), c("system", "user", "assistant", "user"))
  expect_equal(retry[[3]]$content, "[1]")
  expect_equal(ans$sources$cited, c(TRUE, FALSE, FALSE))

  # A second citation-only reply keeps the first, and nothing loops.
  replies <- list("[2]", "[1]")
  seen <- list()
  ans2 <- dragon_ask(docs, "q")
  expect_equal(ans2$answer, "[2]")
  expect_length(seen, 2)

  # A normal reply is not asked again.
  replies <- list("Two years [2].")
  seen <- list()
  dragon_ask(docs, "q")
  expect_length(seen, 1)
})
