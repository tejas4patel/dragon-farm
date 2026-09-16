# Launch the dragon-farm app

A Shiny app that walks through the same steps as the R API: drop in a
dataset, drag its columns into prompt and response slots, pick a model,
train in the background, watch the loss curve, try the result, talk to
it with context, and run the whole post-training loop as a pipeline.
Every run started here is a normal run directory, and the Monitor panel
shows the R code that reproduces it.

## Usage

``` r
dragon_app(runs_dir = dragon_runs_dir(), ...)
```

## Arguments

- runs_dir:

  Directory where runs are stored and listed.

- ...:

  Passed to
  [`shiny::shinyApp()`](https://rdrr.io/pkg/shiny/man/shinyApp.html) as
  `options`.

## Value

A Shiny app object. Printing it runs the app.

## Examples

``` r
if (FALSE) { # \dontrun{
dragon_app()
} # }
```
