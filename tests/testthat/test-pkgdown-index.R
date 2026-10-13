# The site's reference index (_pkgdown.yml) lists topics explicitly, and the
# site build fails when an exported topic is missing. pkgdown has no
# "everything else" selector that does not duplicate topics, so this test is
# the early warning: it fails here, before a push, rather than in the deploy.

test_that("every documented, non-internal topic is in the pkgdown reference index", {
  root <- testthat::test_path("..", "..")
  yml <- file.path(root, "_pkgdown.yml")
  skip_if_not(file.exists(yml), "_pkgdown.yml is not part of the installed package")
  lines <- readLines(yml, warn = FALSE)
  ref <- lines[seq(which(lines == "reference:"), which(lines == "articles:") - 1)]
  entries <- ref[grepl("^[[:space:]]*-[[:space:]]*[A-Za-z_.]+[[:space:]]*$", ref)]
  listed <- trimws(sub("^[[:space:]]*-[[:space:]]*", "", entries))

  rd_files <- list.files(file.path(root, "man"), pattern = "[.]Rd$", full.names = TRUE)
  missing <- character()
  for (f in rd_files) {
    rd <- readLines(f, warn = FALSE)
    if (any(grepl("keyword{internal}", rd, fixed = TRUE))) next
    topic <- sub("[.]Rd$", "", basename(f))
    alias_lines <- rd[startsWith(rd, "\\alias{")]
    aliases <- sub("^\\\\alias\\{(.*)\\}$", "\\1", alias_lines)
    if (!any(c(topic, aliases) %in% listed)) missing <- c(missing, topic)
  }
  expect_equal(missing, character(), info = "add these topics to a section of _pkgdown.yml")
})
