# A saved document set written by hand (no Python), for tests of loading,
# printing, retrieval shaping, and asking.
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
