# Question sets: load, save (review decisions), list, dataset building, and
# printing, with retrieval mocked. Real generation runs under DRAGONFARM_INTEGRATION=true.

# write_fake_questions() lives in helper-questions.R

test_that("question sets load, print, list, and save review decisions", {
  f <- write_fake_set()
  path <- write_fake_questions(f$dir)
  qa <- dragon_questions_load(path)
  expect_s3_class(qa, "dragon_questions")
  expect_equal(nrow(qa), 3L)
  expect_equal(qa$keep, c(TRUE, FALSE, TRUE))
  expect_equal(attr(qa, "documents"), normalizePath(f$dir, winslash = "/"))
  out <- cli::cli_fmt(print(qa))
  expect_true(any(grepl("3 questions", out)))
  expect_true(any(grepl("2 kept \\(67%\\)", out)))
  expect_true(any(grepl("refers to the passage \\(1\\)", out)))

  # a subset prints as a plain table, not as a summary of a question set
  sub_out <- capture.output(print(qa[!qa$keep, c("question", "reason")]))
  expect_true(any(grepl("refers to the passage", sub_out)))
  expect_false(any(grepl("kept", sub_out)))

  lst <- dragon_questions_list(f$dir)
  expect_equal(nrow(lst), 1L)
  expect_equal(lst$kept, 2L); expect_equal(lst$generator, "Qwen/Qwen2.5-7B-Instruct")

  # a person rescues the rejected pair and drops a kept one
  qa$keep[2] <- TRUE; qa$keep[3] <- FALSE
  qa2 <- dragon_questions_save(qa)
  expect_equal(qa2$keep, c(TRUE, TRUE, FALSE))
  expect_equal(qa2$decided_by, c("filter", "person", "person"))
  expect_equal(dragon_questions_load(path)$keep, c(TRUE, TRUE, FALSE))
  expect_error(dragon_questions_load(file.path(f$dir, "nope.jsonl")), "does not exist")
  expect_error(dragon_questions_save(data.frame()), "dragon_questions")
})

test_that("the training dataset puts retrieved excerpts in front of each kept question", {
  f <- write_fake_set()
  qa <- dragon_questions_load(write_fake_questions(f$dir))
  asked <- NULL
  testthat::local_mocked_bindings(dragon_retrieve = function(docs, query, k = 4) {
    asked <<- list(query = query, k = k)
    do.call(rbind, lapply(query, function(q) data.frame(
      query = q, n = 1:2, id = c("abc-000", "abc-001"), source = "policy.pdf", section = c("Returns", "Warranty"),
      text = c("Thirty days.", "Two years."), score = c(0.9, 0.5), similarity = c(0.9, 0.5), weight = 1, stringsAsFactors = FALSE)))
  })
  ds <- dragon_questions_dataset(qa, k = 2)
  expect_s3_class(ds, "dragon_dataset")
  expect_equal(asked$query, c("How long is the return window?", "How long is the warranty?"))
  expect_equal(asked$k, 2)
  expect_equal(nrow(ds$data), 2L)
  expect_match(ds$mapping$response, "answer")
  expect_match(ds$mapping$prompt, "^Documentation excerpts:")
  expect_match(ds$data$context[1], "\\[1\\] policy.pdf . Returns\nThirty days.")
  rows <- dragonfarm:::dataset_messages(ds)
  expect_match(rows[[1]]$messages[[1]]$content, "Question: How long is the return window\\?$")
  # the answer cites the excerpt its pair was written from, as dragon_ask() would
  expect_equal(rows[[1]]$messages[[2]]$content, "Thirty days from delivery. [1]")
  expect_equal(dragon_questions_dataset(qa, k = 2, cite = FALSE)$data$answer[1], "Thirty days from delivery.")
  qa$keep[] <- FALSE
  expect_error(dragon_questions_dataset(qa), "No kept questions")
})

test_that("a pair whose source chunk was not retrieved gets that chunk as its last excerpt", {
  f <- write_fake_set()
  qa <- dragon_questions_load(write_fake_questions(f$dir))
  testthat::local_mocked_bindings(dragon_retrieve = function(docs, query, k = 4) {
    do.call(rbind, lapply(query, function(q) data.frame(
      query = q, n = 1:2, id = c("zzz-998", "zzz-999"), source = "other.pdf", section = "", text = c("Unrelated one.", "Unrelated two."),
      score = c(0.4, 0.3), similarity = c(0.4, 0.3), weight = 1, stringsAsFactors = FALSE)))
  })
  ds <- dragon_questions_dataset(qa, k = 2)
  ctx <- ds$data$context[1]
  expect_match(ctx, "^\\[1\\] other.pdf")
  expect_true(grepl("Unrelated one.", ctx, fixed = TRUE))
  expect_false(grepl("Unrelated two.", ctx))            # the weakest hit made room
  expect_match(ctx, "\\[2\\] policy.pdf")           # for the chunk the pair came from
  expect_match(ds$data$answer[1], " \\[2\\]$")
})

test_that("dragon_questions validates and refuses an empty selection for a teacher", {
  f <- write_fake_set()
  expect_error(dragon_questions(f$dir, n_per_chunk = 0), "n_per_chunk")
  testthat::local_mocked_bindings(
    run_python = function(module, args, ...) list(status = 0L, stdout = "[]", stderr = ""),
    as_llm = function(x, ...) function(prompts) rep("Q1: a?\nA1: b", length(prompts))
  )
  expect_error(dragon_questions(f$dir, generator = function(p) p), "No chunks")
})

test_that("a teacher's replies go through the same parser and filters", {
  f <- write_fake_set()
  calls <- list()
  testthat::local_mocked_bindings(
    run_python = function(module, args, ...) {
      calls[[length(calls) + 1]] <<- args
      if (identical(args[1], "prompts")) {
        return(list(status = 0L, stderr = "", stdout = jsonlite::toJSON(list(list(chunk_id = "abc-000", prompt = "write two")), auto_unbox = TRUE)))
      }
      out <- args[which(args == "--out") + 1]
      dragonfarm:::write_jsonl(list(list(id = "p0001", chunk_id = "abc-000", source = "policy.pdf", section = "Returns",
                                         question = "How long?", answer = "Thirty days.", keep = TRUE, reason = NULL, decided_by = "filter")), out)
      list(status = 0L, stderr = "", stdout = '{"n_pairs": 1, "n_kept": 1, "unparsed": 0}')
    }
  )
  teacher <- function(prompts) rep("Q1: How long?\nA1: Thirty days.", length(prompts))
  qa <- dragon_questions(f$dir, generator = teacher, n_per_chunk = 2)
  expect_equal(nrow(qa), 1L)
  expect_true(qa$keep)
  expect_equal(calls[[1]][1:3], c("prompts", "--dir", normalizePath(f$dir, winslash = "/")))
  expect_true("--per-chunk" %in% calls[[1]] && "2" %in% calls[[1]])
  expect_equal(calls[[2]][1], "filter")
  expect_true(file.exists(attr(qa, "path")))
})

test_that("questions are written by a local model for real", {
  skip_if_not(identical(Sys.getenv("DRAGONFARM_INTEGRATION"), "true"), "set DRAGONFARM_INTEGRATION=true")
  skip_on_cran()
  src <- tempfile("src-"); dir.create(src)
  writeLines(c("# Returns", "", paste(rep("Any device can be returned within 30 days of delivery for a full refund.", 6), collapse = " ")),
             file.path(src, "policy.md"))
  docs <- dragon_documents(src, name = "q-test", runs_dir = tempfile("runs-"), index = FALSE)
  job <- dragon_questions(docs, generator = "HuggingFaceTB/SmolLM2-135M-Instruct", n_per_chunk = 2, wait = FALSE, max_new_tokens = 120)
  expect_s3_class(job, "dragon_questions_job")
  qa <- dragon_questions_wait(job)
  expect_s3_class(qa, "dragon_questions")
  expect_true(file.exists(attr(qa, "path")))
  expect_equal(dragon_questions_progress(job)$state, "done")
  expect_equal(nrow(dragon_questions_list(docs)), 1L)
})
