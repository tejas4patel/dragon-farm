#' Launch the dragon-farm app
#'
#' A Shiny app that walks through the same steps as the R API: drop in a
#' dataset, drag its columns into prompt and response slots, pick a model,
#' train in the background, watch the loss curve, try the result, talk to it
#' with context, and run the whole post-training loop as a pipeline.
#' Every run started here is a normal run directory, and the Monitor panel
#' shows the R code that reproduces it.
#'
#' @param runs_dir Directory where runs are stored and listed.
#' @param ... Passed to [shiny::shinyApp()] as `options`.
#' @return A Shiny app object. Printing it runs the app.
#' @export
#' @examples
#' \dontrun{
#' dragon_app()
#' }
dragon_app <- function(runs_dir = dragon_runs_dir(), ...) {
  options(dragonfarm.runs_dir = runs_dir)
  # Imported results zips carry a LoRA adapter, typically tens of megabytes.
  options(shiny.maxRequestSize = 1024 * 1024^2)
  dir.create(runs_dir, recursive = TRUE, showWarnings = FALSE)
  shiny::addResourcePath("dragonfarm", system.file("app", "www", package = "dragonfarm"))

  ui <- bslib::page_navbar(
    title = shiny::tags$span(shiny::tags$span(class = "brand-mark", "\u25b2"), "dragon-farm"),
    id = "nav",
    theme = bslib::bs_theme(
      version = 5, preset = "shiny",
      primary = "#2F6F8F", "navbar-bg" = "#1B2230",
      base_font = bslib::font_collection("IBM Plex Sans", "Segoe UI", "sans-serif"),
      heading_font = bslib::font_collection("IBM Plex Serif", "Georgia", "serif"),
      code_font = bslib::font_collection("IBM Plex Mono", "Consolas", "monospace")
    ),
    header = shiny::tags$head(
      shiny::tags$link(rel = "stylesheet", href = paste0("dragonfarm/dragonfarm.css?v=", css_version())),
      shiny::tags$link(rel = "stylesheet",
                       href = "https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Serif:wght@600&family=IBM+Plex+Mono&display=swap")
    ),
    bslib::nav_panel("1 Data", value = "data", mod_data_ui("data")),
    bslib::nav_panel("2 Map", value = "map", mod_mapping_ui("map")),
    bslib::nav_panel("3 Model", value = "model", mod_model_ui("model")),
    bslib::nav_panel("4 Train", value = "train", mod_train_ui("train")),
    bslib::nav_panel("5 Monitor", value = "monitor", mod_monitor_ui("monitor")),
    bslib::nav_panel("6 Try it", value = "tryit", mod_tryit_ui("tryit")),
    bslib::nav_panel("7 Chat", value = "chat", mod_chat_ui("chat")),
    bslib::nav_panel("8 Pipeline", value = "pipeline", mod_pipeline_ui("pipeline")),
    bslib::nav_spacer(),
    bslib::nav_item(shiny::uiOutput("hw_badge", inline = TRUE))
  )

  server <- function(input, output, session) {
    state <- shiny::reactiveValues(dataset = NULL, mapped = NULL, model = NULL, run = NULL, hardware = NULL, cloud = NULL)
    nav_to <- function(panel) bslib::nav_select("nav", panel, session = session)

    mod_data_server("data", state, nav_to)
    mod_mapping_server("map", state, nav_to)
    mod_model_server("model", state, nav_to)
    mod_train_server("train", state, nav_to, runs_dir)
    mod_monitor_server("monitor", state, runs_dir)
    mod_tryit_server("tryit", state, runs_dir)
    mod_chat_server("chat", state, runs_dir)
    mod_pipeline_server("pipeline", state, runs_dir)

    output$hw_badge <- shiny::renderUI({
      hw <- state$hardware
      if (is.null(hw)) return(shiny::tags$span(class = "hw-badge muted", "hardware not checked"))
      label <- switch(hw$device, cuda = sprintf("GPU %s \u00b7 %.0f GB", hw$device_name, hw$vram_gb),
                      mps = "Apple GPU", "CPU only")
      shiny::tags$span(class = paste("hw-badge", hw$device), label)
    })
  }

  shiny::shinyApp(ui, server, options = list(...))
}

# Cache-busting token for the stylesheet: the file's modification time, so a
# changed file is always refetched by browsers that cached the old one.
css_version <- function() {
  f <- system.file("app", "www", "dragonfarm.css", package = "dragonfarm")
  if (!nzchar(f)) return(utils::packageVersion("dragonfarm"))
  as.integer(file.info(f)$mtime)
}

# Shared helpers for modules ------------------------------------------------

chat_preview_ui <- function(rows) {
  if (!length(rows)) return(NULL)
  shiny::tagList(lapply(seq_along(rows), function(i) {
    msgs <- rows[[i]]$messages
    shiny::div(class = "chat-row",
      shiny::div(class = "chat-row-label", sprintf("Row %d", i)),
      lapply(msgs, function(m) {
        shiny::div(class = paste("bubble", m$role),
          shiny::span(class = "role", m$role),
          shiny::div(class = "content", m$content)
        )
      })
    )
  }))
}

state_pill <- function(state) {
  shiny::span(class = paste("pill", state), state)
}

notify_error <- function(e, session = shiny::getDefaultReactiveDomain()) {
  msg <- conditionMessage(e)
  shiny::showNotification(msg, type = "error", duration = 12, session = session)
}

# Long actions in the app (evaluate, judge, build pairs, merge) run as
# one-step background pipelines so the session stays responsive. A watcher
# polls the record and hands the finished record back to the module.
app_task_start <- function(run, step, runs_dir, name) {
  suppressMessages(dragon_pipeline(run, list(step), runs_dir = runs_dir, name = name, background = TRUE))
}

app_task_watch <- function(handle, on_done, interval = 2000, session = shiny::getDefaultReactiveDomain()) {
  obs <- shiny::observe({
    rec <- tryCatch(dragon_pipeline_status(handle), error = function(e) NULL)
    if (is.null(rec) || rec$status %in% c("queued", "running")) {
      shiny::invalidateLater(interval, session)
      return()
    }
    obs$destroy()
    tryCatch(on_done(rec), error = function(e) notify_error(e, session))
  }, domain = session)
  invisible(obs)
}

task_error <- function(rec) {
  errs <- Filter(Negate(is.null), c(list(rec$error), lapply(rec$steps, function(s) s$error)))
  if (length(errs)) errs[[1]] else "no details were recorded"
}

task_status_ui <- function(t, what) {
  if (is.null(t)) return(NULL)
  if (t$state %in% c("queued", "running")) {
    return(shiny::p(class = "hint task-running",
      sprintf("%s is running in the background as %s. Keep using the app; the result appears here, and the Pipeline panel lists it.", what, t$id)))
  }
  if (!identical(t$state, "succeeded")) {
    return(shiny::p(class = "text-danger small", sprintf("%s %s: %s", what, t$state, t$error %||% "")))
  }
  NULL
}
