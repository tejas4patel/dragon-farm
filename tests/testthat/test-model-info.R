test_that("each task has a four-size comparison", {
  for (task in c("answer", "questions", "train")) {
    df <- dragonfarm:::model_comparison(task)
    expect_equal(nrow(df), 4L)
    expect_match(df$Model[4], "^7B")
    expect_true(ncol(df) >= 3)
  }
  expect_error(dragonfarm:::model_comparison("nope"))
})

test_that("the info icon is a focusable popover trigger with the table inside", {
  html <- paste(as.character(dragonfarm:::model_info_icon("answer")), collapse = "")
  expect_match(html, 'class="df-info"', fixed = TRUE)
  expect_match(html, 'tabindex="0"', fixed = TRUE)
  expect_match(html, "aria-label=\"Answering from documents, by model size: show the comparison\"", fixed = TRUE)
  expect_match(html, "bslib-popover", fixed = TRUE)
  expect_match(html, "Wrong or empty (of 55)", fixed = TRUE)
  expect_match(html, "7B, 4-bit", fixed = TRUE)
})

test_that("every model choice in the app carries the icon for its task", {
  has <- function(ui, task) {
    html <- paste(as.character(ui), collapse = "")
    grepl("df-info", html, fixed = TRUE) && grepl(dragonfarm:::model_comparison_text[[task]][["title"]], html, fixed = TRUE)
  }
  expect_true(has(dragonfarm:::mod_documents_ui("documents"), "answer"))      # Answered by
  expect_true(has(dragonfarm:::mod_documents_ui("documents"), "questions"))   # Written by
  expect_true(has(dragonfarm:::mod_model_ui("model"), "train"))
  expect_true(has(dragonfarm:::mod_chat_ui("chat"), "answer"))
  expect_true(has(dragonfarm:::mod_tryit_ui("tryit"), "train"))
})
