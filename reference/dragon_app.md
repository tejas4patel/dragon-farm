# Launch the dragonfarm app

A Shiny app that walks through the same steps as the R API. The default
route starts from documents: drop in files or web pages, ask questions
of them with cited sources, then pick a model, train in the background,
watch the loss curve, try the result, talk to it with context, and run
the whole post-training loop as a pipeline. The table route (a dataset
of prompt and response rows, mapped by dragging columns) is one link
away, or the start with `route = "table"`. Every run started here is a
normal run directory, and the Monitor panel shows the R code that
reproduces it.

## Usage

``` r
dragon_app(runs_dir = dragon_runs_dir(), route = c("documents", "table"), ...)
```

## Arguments

- runs_dir:

  Directory where runs are stored and listed.

- route:

  Which tabs lead: `"documents"` (Documents, Model, Train, Monitor, Try
  it, Chat, Pipeline) or `"table"` (Data, Map, Model, ...). Either can
  be switched to from inside the app.

- ...:

  Passed to
  [`shiny::shinyApp()`](https://rdrr.io/pkg/shiny/man/shinyApp.html) as
  `options`.

## Value

A Shiny app object. Printing it runs the app.

## Examples

``` r
if (interactive()) {
dragon_app()
dragon_app(route = "table")
}
```
