test_that("the Data module loads the example dataset, a picked file, and reports its summary", {
  state <- shiny::reactiveValues(dataset = NULL, mapped = "leftover")
  navigated <- character()
  shiny::testServer(dragonfarm:::mod_data_server, args = list(state = state, nav_to = function(panel) navigated <<- c(navigated, panel)), {
    expect_null(state$dataset)
    summary_html <- as.character(output$summary$html)
    expect_match(summary_html, "No dataset loaded yet.", fixed = TRUE)

    session$setInputs(example = 1)
    expect_s3_class(state$dataset, "dragon_dataset")
    expect_true(nrow(state$dataset$data) > 0)
    expect_null(state$mapped)   # picking a new dataset clears any earlier mapping
    summary_html <- as.character(output$summary$html)
    expect_match(summary_html, "support_tickets.jsonl (example)", fixed = TRUE)
    expect_match(summary_html, "Next: map columns", fixed = TRUE)

    preview <- output$preview
    expect_true(!is.null(preview))

    session$setInputs(`next` = 1)
    expect_equal(navigated, "map")
  })
})

test_that("the Data module surfaces a bad file instead of crashing", {
  state <- shiny::reactiveValues(dataset = NULL, mapped = NULL)
  bad <- tempfile(fileext = ".csv")
  writeLines(character(), bad)   # an empty file: not a usable dataset
  shiny::testServer(dragonfarm:::mod_data_server, args = list(state = state, nav_to = function(panel) NULL), {
    session$setInputs(file = data.frame(name = "empty.csv", datapath = bad, stringsAsFactors = FALSE))
    expect_null(state$dataset)
  })
})
