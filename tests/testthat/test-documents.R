# Document sets: validation, loading, printing, and chunk access without Python
# (the fake set comes from helper-documents.R). Building a real set from files
# runs under DRAGONFARM_INTEGRATION=true.

test_that("dragon_documents validates its inputs before touching Python", {
  expect_error(dragon_documents(character()), "paths")
  expect_error(dragon_documents(c("a.md", NA)), "paths")
  expect_error(dragon_documents(file.path(tempdir(), "definitely-missing.pdf")), "not found")
  expect_error(dragon_documents(tempdir(), max_words = 5), "max_words")
  expect_error(dragon_documents(tempdir(), max_words = 100, min_words = 200), "min_words")
})

test_that("a saved set loads, prints, lists, and exposes its chunks", {
  f <- write_fake_set()
  docs <- dragon_documents_load(f$dir)
  expect_s3_class(docs, "dragon_documents")
  expect_equal(docs$name, "kb")
  expect_equal(length(docs$manifest$sources), 3L)

  by_name <- dragon_documents_load("kb", runs_dir = f$root)
  expect_equal(by_name$dir, docs$dir)

  out <- cli::cli_fmt(print(docs))
  expect_true(any(grepl("policy.pdf: 2 chunks", out)))
  expect_true(any(grepl("changelog, down-weighted", out)))
  expect_true(any(grepl("failed: RuntimeError", out)))
  expect_true(any(grepl("index: none", out)))

  ch <- dragon_chunks(docs)
  expect_equal(nrow(ch), 3L)
  expect_equal(ch$section, c("Returns", "Warranty", "1.1.0"))
  expect_equal(ch$weight, c(1, 1, 0.7))
  expect_true(ch$quoted[2]); expect_false(ch$quoted[1])
  expect_equal(dragon_chunks(f$dir)$id, ch$id)

  lst <- dragon_documents_list(f$root)
  expect_equal(nrow(lst), 1L)
  expect_equal(lst$name, "kb"); expect_equal(lst$chunks, 3L); expect_false(lst$indexed)
  expect_equal(nrow(dragon_documents_list(tempfile())), 0L)
})

test_that("loading something that is not a set fails clearly", {
  expect_error(dragon_documents_load(tempdir()), "not a document set")
  expect_error(dragon_chunks(42), "dragon_documents")
})

test_that("a document set is built from real files", {
  skip_if_not(identical(Sys.getenv("DRAGONFARM_INTEGRATION"), "true"), "set DRAGONFARM_INTEGRATION=true")
  skip_on_cran()
  src <- tempfile("src-"); dir.create(src)
  writeLines(c("# Returns", "", paste(rep("Any device can be returned within 30 days of delivery for a full refund.", 8), collapse = " "),
               "", "## Warranty", "", paste(rep("Every device carries a 2-year limited warranty from the delivery date.", 8), collapse = " ")),
             file.path(src, "policy.md"))
  writeLines(c("question,answer", "How long is the warranty?,Two years."), file.path(src, "faq.csv"))
  runs_dir <- tempfile("runs-")
  docs <- dragon_documents(src, name = "test set", runs_dir = runs_dir, index = FALSE)
  expect_equal(docs$name, "test-set")
  expect_null(docs$manifest$index)
  ch <- dragon_chunks(docs)
  expect_true(all(c("policy.md", "faq.csv") %in% ch$source))
  expect_true(any(grepl("30 days", ch$text)))
  again <- dragon_documents(src, name = "test set", runs_dir = runs_dir, index = FALSE)
  expect_equal(dragon_chunks(again)$id, ch$id)
})
