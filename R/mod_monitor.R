mod_monitor_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    bslib::layout_columns(
      col_widths = c(4, 8),
      bslib::card(
        bslib::card_header("Runs"),
        shiny::selectInput(ns("run"), NULL, choices = character(), width = "100%"),
        shiny::uiOutput(ns("facts")),
        shiny::actionButton(ns("cancel"), "Cancel run", class = "btn-outline-danger"),
        shiny::actionButton(ns("resume"), "Resume from checkpoint", class = "btn-outline-secondary"),
        shiny::hr(),
        shiny::fileInput(ns("import"), "Import cloud results (dragonfarm-results-*.zip)", accept = ".zip", width = "100%"),
        shiny::uiOutput(ns("import_hint"))
      ),
      bslib::card(
        bslib::card_header("Loss"),
        plotly::plotlyOutput(ns("loss"), height = "320px")
      )
    ),
    bslib::layout_columns(
      col_widths = c(6, 6),
      bslib::card(
        bslib::card_header("Trainer log"),
        shiny::verbatimTextOutput(ns("log"), placeholder = TRUE)
      ),
      bslib::card(
        bslib::card_header("R code for this run"),
        shiny::verbatimTextOutput(ns("code"), placeholder = TRUE)
      )
    ),
    bslib::layout_columns(
      col_widths = c(4, 8),
      bslib::card(
        bslib::card_header("Task metrics"),
        shiny::p(class = "hint", "Generates a reply for every held-out row and scores it with deterministic checks: exact match, token overlap, JSON validity, numeric answers, and length."),
        shiny::checkboxGroupInput(ns("metric_names"), NULL,
                                  choices = c("exact", "contains", "token_f1", "json_valid", "numeric", "length_ratio"),
                                  selected = c("exact", "token_f1", "length_ratio"), inline = TRUE),
        shiny::actionButton(ns("run_metrics"), "Evaluate held-out rows", class = "btn-outline-primary"),
        shiny::uiOutput(ns("metrics_out"))
      ),
      bslib::card(
        bslib::card_header("Compare runs"),
        shiny::p(class = "hint", "Every run in this directory with whatever has been measured for it: loss, preference accuracy, task metrics, and the latest judge result from the Try it panel."),
        shiny::div(class = "table-wrap", shiny::tableOutput(ns("compare")))
      )
    )
  )
}

mod_monitor_server <- function(id, state, runs_dir) {
  shiny::moduleServer(id, function(input, output, session) {
    runs <- shiny::reactivePoll(3000, session,
      checkFunc = function() {
        dirs <- list.dirs(runs_dir, recursive = FALSE)
        paste(dirs, file.info(file.path(dirs, "status.json"))$mtime, collapse = "|")
      },
      valueFunc = function() dragon_runs(runs_dir)
    )

    shiny::observe({
      df <- runs()
      selected <- shiny::isolate(input$run)
      if (!is.null(state$run) && state$run$id %in% df$id && !identical(selected, state$run$id)) {
        selected <- state$run$id
      }
      labels <- if (nrow(df)) sprintf("%s  [%s]", df$id, df$state) else character()
      shiny::updateSelectInput(session, "run", choices = stats::setNames(df$id, labels),
                               selected = if (!is.null(selected) && selected %in% df$id) selected else df$id[1])
    })
    shiny::observeEvent(state$run, {
      shiny::updateSelectInput(session, "run", selected = state$run$id)
    })

    # NULL when nothing is selected. Poll check functions must never throw
    # (a req() inside one closes the session), so they use this rather than run().
    current_run <- shiny::reactive({
      id <- input$run
      if (is.null(id) || !nzchar(id)) return(NULL)
      dir <- file.path(runs_dir, id)
      if (!file.exists(file.path(dir, "config.json"))) return(NULL)
      # Reuse the live handle when this is the run we launched, so a crash is detected quickly.
      if (!is.null(state$run) && identical(state$run$id, id)) state$run else dragon_run(dir)
    })
    run <- shiny::reactive({
      r <- current_run()
      shiny::req(r)
      r
    })

    file_sig <- function(path) {
      if (!file.exists(path)) return("")
      info <- file.info(path)
      paste(info$mtime, info$size)
    }
    run_file_sig <- function(name) {
      r <- current_run()
      if (is.null(r)) return("")
      paste(r$id, file_sig(file.path(r$dir, name)))
    }
    progress <- shiny::reactivePoll(1000, session,
      checkFunc = function() run_file_sig("progress.jsonl"),
      valueFunc = function() { r <- current_run(); if (is.null(r)) dragon_progress_empty() else dragon_progress(r) }
    )
    status <- shiny::reactivePoll(1000, session,
      checkFunc = function() paste(run_file_sig("status.json"), as.numeric(Sys.time()) %/% 5),
      valueFunc = function() { r <- current_run(); if (is.null(r)) list(state = "none") else dragon_status(r) }
    )
    logs <- shiny::reactivePoll(1500, session,
      checkFunc = function() run_file_sig("log.txt"),
      valueFunc = function() { r <- current_run(); if (is.null(r)) character() else dragon_logs(r, 40) }
    )

    output$facts <- shiny::renderUI({
      r <- run()
      st <- status()
      cfg <- run_config(r)
      pr <- progress()
      last_loss <- if (nrow(pr) && any(!is.na(pr$loss))) sprintf("%.3f", utils::tail(pr$loss[!is.na(pr$loss)], 1)) else "-"
      step <- if (nrow(pr)) max(pr$step, na.rm = TRUE) else 0
      eta <- if (nrow(pr) && any(!is.na(pr$eta_s))) {
        s <- utils::tail(pr$eta_s[!is.na(pr$eta_s)], 1)
        sprintf("%d min %02d s", s %/% 60, round(s %% 60))
      } else "-"
      shiny::tagList(
        shiny::div(class = "kv", shiny::span("State"), state_pill(st$state)),
        shiny::div(class = "kv", shiny::span("Model"), shiny::code(cfg$model$id)),
        shiny::div(class = "kv", shiny::span("Stage"), shiny::strong(
          if (identical(cfg$stage, "prefer")) sprintf("%s, beta %s", toupper(cfg$prefer$method), cfg$prefer$beta) else "fine-tune")),
        if (!is.null(cfg$model$base_run)) shiny::div(class = "kv", shiny::span("Continues"), shiny::code(cfg$model$base_run)),
        shiny::div(class = "kv", shiny::span("Device"), shiny::strong(st$device %||% "-")),
        shiny::div(class = "kv", shiny::span("Step"), shiny::strong(sprintf("%d / %s", as.integer(step), st$total_steps %||% "?"))),
        shiny::div(class = "kv", shiny::span("Loss"), shiny::strong(last_loss)),
        shiny::div(class = "kv", shiny::span("ETA"), shiny::strong(eta)),
        if (!is.null(st$pref_accuracy)) shiny::div(class = "kv", shiny::span("Pref. accuracy"), shiny::strong(sprintf("%.0f%% (margin %.3f)", 100 * st$pref_accuracy, st$reward_margin))),
        if (!is.null(st$eval_loss) && is.null(st$pref_accuracy)) shiny::div(class = "kv", shiny::span("Eval loss"), shiny::strong(sprintf("%.3f (ppl %.2f)", st$eval_loss, st$perplexity))),
        if (!is.null(st$error)) shiny::pre(class = "error-box", st$error)
      )
    })

    output$loss <- plotly::renderPlotly({
      pr <- progress()
      train <- pr[!is.na(pr$loss), , drop = FALSE]
      ev <- pr[!is.na(pr$eval_loss), , drop = FALSE]
      p <- plotly::plot_ly()
      if (!nrow(train) && !nrow(ev)) {
        # An empty scatter trace keeps plotly quiet about a plot with no data.
        p <- plotly::add_trace(p, x = numeric(), y = numeric(), type = "scatter", mode = "lines", showlegend = FALSE)
      }
      if (nrow(train)) {
        p <- plotly::add_trace(p, x = train$step, y = train$loss, type = "scatter", mode = "lines",
                               name = "train loss", line = list(color = "#2F6F8F", width = 2))
      }
      if (nrow(ev)) {
        p <- plotly::add_trace(p, x = ev$step, y = ev$eval_loss, type = "scatter", mode = "markers+lines",
                               name = "eval loss", marker = list(color = "#B8702A", size = 9),
                               line = list(color = "#B8702A", dash = "dot"))
      }
      if (!nrow(train) && !nrow(ev)) {
        p <- plotly::layout(p, annotations = list(text = "Waiting for the first logged step", showarrow = FALSE, x = 0.5, y = 0.5, xref = "paper", yref = "paper"))
      }
      plotly::config(plotly::layout(p,
        xaxis = list(title = "step", zeroline = FALSE),
        yaxis = list(title = "loss", zeroline = FALSE, rangemode = "tozero"),
        margin = list(l = 50, r = 20, t = 10, b = 40),
        legend = list(orientation = "h", x = 0, y = 1.1),
        paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)"
      ), displayModeBar = FALSE)
    })

    output$log <- shiny::renderText(paste(logs(), collapse = "\n"))
    output$code <- shiny::renderText({
      r <- run()
      tryCatch(dragon_code(r), error = function(e) conditionMessage(e))
    })

    shiny::observeEvent(input$cancel, {
      r <- run()
      st <- status()
      if (!st$state %in% c("queued", "running")) {
        shiny::showNotification("This run is not running.", type = "warning")
        return()
      }
      writeLines(now_iso(), file.path(r$dir, "cancel.request"))
      shiny::showNotification("Cancel requested. The trainer saves a checkpoint and stops after the current step.", type = "message")
    })

    shiny::observeEvent(input$resume, {
      r <- run()
      res <- tryCatch(dragon_resume(r), error = function(e) { notify_error(e); NULL })
      if (!is.null(res)) {
        state$run <- res
        shiny::showNotification(sprintf("Resumed %s.", res$id), type = "message")
      }
    })

    shiny::observeEvent(input$run_metrics, {
      r <- run()
      chosen <- input$metric_names
      if (!length(chosen)) {
        shiny::showNotification("Pick at least one metric.", type = "warning")
        return()
      }
      shiny::withProgress(message = "Generating replies for the held-out rows", detail = "This loads the model once and can take a minute", {
        res <- tryCatch(dragon_evaluate(r, metrics = chosen), error = function(e) { notify_error(e); NULL })
        if (!is.null(res)) shiny::showNotification("Metrics saved to the run.", type = "message")
      })
    })

    output$metrics_out <- shiny::renderUI({
      st <- status()
      m <- st$metrics
      if (is.null(m) || !length(m)) return(NULL)
      shiny::tagList(lapply(names(m), function(nm) {
        shiny::div(class = "kv", shiny::span(nm), shiny::strong(formatC(as.numeric(m[[nm]]), digits = 3, format = "fg")))
      }))
    })

    output$compare <- shiny::renderTable({
      runs()
      status()
      cmp <- tryCatch(dragon_compare(runs_dir = runs_dir), error = function(e) NULL)
      if (is.null(cmp) || !nrow(cmp)) return(data.frame(note = "No runs yet."))
      df <- as.data.frame(cmp)
      df$model <- basename(df$model)
      df$from <- ifelse(is.na(df$from), "", df$from)
      df$method <- ifelse(is.na(df$method), "", df$method)
      df$run <- df$id
      df$id <- NULL
      keep <- vapply(df, function(col) is.character(col) || any(!is.na(col)), logical(1))
      df <- df[, c("run", setdiff(names(df)[keep], "run")), drop = FALSE]
      df
    }, spacing = "xs", width = "100%", na = "", digits = 3)

    output$import_hint <- shiny::renderUI({
      st <- status()
      if (!identical(st$state, "bundled")) return(NULL)
      shiny::p(class = "hint", "This run was bundled for a cloud GPU. Train it there, then drop the results zip above.")
    })

    shiny::observeEvent(input$import, {
      r <- run()
      f <- input$import
      shiny::req(f)
      res <- tryCatch(dragon_import(r, f$datapath), error = function(e) { notify_error(e); NULL })
      if (!is.null(res)) {
        st <- dragon_status(res)
        shiny::showNotification(sprintf("Imported results for %s (%s).", res$id, st$state), type = "message")
      }
    })
  })
}
