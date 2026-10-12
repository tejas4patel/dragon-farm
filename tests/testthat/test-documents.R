# Document sets: validation, loading, printing, and chunk access without Python.
# Building a real set from files runs under DRAGONFARM_INTEGRATION=true.

write_fake_set <- function(root = tempfile("docs-"), name = "kb") {
  dir <- file.path(root, "documents", name)
  dir.create(dir, recursive = TRUE)
  manifest <- list(
    schema_version = 1L, name = name, created_at = "2026-10-12T10:00:00Z", updated_at = "2026-10-12T10:00:00Z",
    chunking = list(max_words = 170L, min_words = 35L),
    sources = list(
      list(locator = "/x/policy.pdf", kind = "file", name = "policy.pdf", reader = ".pdf", sha256 = "abc", bytes = 10L,
           n_chunks = 2L, n_words = 300L, changelog_like = FALSE, error = NULL, read_at = NULL),
      list(locator = "/x/NEWS.md", kind = "file", name = "NEWS.md", reader = ".md", sha256 = "def", bytes = 10L,
           n_chunks = 1L, n_words = 120L, changelog_like = TRUE, error = NULL, read_at = NULL),
      list(locator = "/x/bad.docx", kind = "file", name = "bad.docx", reader = ".docx", sha256 = NULL, bytes = NULL,
           n_chunks = 0L, n_words = 0L, changelog_like = FALSE, error = "RuntimeError: needs python-docx", read_at = NULL)
    ),
    n_chunks = 3L, index = NULL
  )
  dragonfarm:::write_json(manifest, file.path(dir, "manifest.json"))
  chunks <- list(
    list(id = "abc-000", source_id = "abc", source = "policy.pdf", section = "Returns", text = "Thirty days.", n_words = 150L, quoted = FALSE, code = FALSE, weight = 1),
    list(id = "abc-001", source_id = "abc", source = "policy.pdf", section = "Warranty", text = "Two years.", n_words = 150L, quoted = TRUE, code = FALSE, weight = 1),
    list(id = "def-000", source_id = "def", source = "NEWS.md", section = "1.1.0", text = "Changed.", n_words = 120L, quoted = FALSE, code = FALSE, weight = 0.7)
  )
  dragonfarm:::write_jsonl(chunks, file.path(dir, "chunks.jsonl"))
  list(root = root, dir = dir)
}

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
  docs <- dragon_documents(src, name = "test set", runs_dir = runs_dir)
  expect_equal(docs$name, "test-set")
  ch <- dragon_chunks(docs)
  expect_true(all(c("policy.md", "faq.csv") %in% ch$source))
  expect_true(any(grepl("30 days", ch$text)))
  again <- dragon_documents(src, name = "test set", runs_dir = runs_dir)
  expect_equal(dragon_chunks(again)$id, ch$id)
})
