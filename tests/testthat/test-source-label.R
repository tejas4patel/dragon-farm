# Where an excerpt came from, as answers, footnotes, and prompts show it.
# PDFs carry a page; other sources do not.

test_that("source labels include the page when there is one", {
  lab <- dragonfarm:::source_label(c("report.pdf", "report.pdf", "notes.md", "faq.html"),
                                   c("Risk Factors", "", "Setup", NA),
                                   c(12L, 3L, NA, NA))
  expect_equal(lab, c("report.pdf, p. 12 › Risk Factors", "report.pdf, p. 3", "notes.md › Setup", "faq.html"))
  expect_equal(dragonfarm:::source_label("a.md", "S"), "a.md › S")
})

test_that("a printed answer shows the page of each source", {
  ans <- structure(list(question = "q", answer = "Net sales were $249.6 billion [1].",
                        sources = data.frame(n = 1:2, source = "report.pdf", section = c("", "Net Sales"),
                                             page = c(3L, 22L), text = c("a", "b"), cited = c(TRUE, FALSE),
                                             stringsAsFactors = FALSE),
                        model = "m", documents = "d"), class = "dragon_answer")
  out <- capture.output(print(ans))
  expect_true(any(grepl("[1]* report.pdf, p. 3", out, fixed = TRUE)))
  expect_true(any(grepl("[2]  report.pdf, p. 22 › Net Sales", out, fixed = TRUE)))
})
