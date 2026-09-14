mod_tryit_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    bslib::layout_columns(
      col_widths = c(5, 7),
      bslib::card(
        bslib::card_header("Ask the model"),
        shiny::selectInput(ns("run"), "Run", choices = character(), width = "100%"),
        shiny::textInput(ns("system"), "System prompt (optional)", width = "100%"),
        shiny::textAreaInput(ns("prompt"), "Prompt", rows = 5, width = "100%",
                             placeholder = "My Ember thermostat keeps dropping off Wi-Fi."),
        bslib::layout_columns(
          col_widths = c(6, 6),
          shiny::numericInput(ns("max_new_tokens"), "Max new tokens", value = 200, min = 1, step = 10),
          shiny::numericInput(ns("temperature"), "Temperature", value = 0.3, min = 0, max = 2, step = 0.1)
        ),
        shiny::checkboxInput(ns("compare"), "Also show the base model's reply", value = TRUE),
        shiny::actionButton(ns("go"), "Generate", class = "btn-primary"),
        shiny::p(class = "text-muted small mt-2", "Each request loads the model in a fresh process, so expect a few seconds of delay.")
      ),
      bslib::layout_columns(
        col_widths = c(6, 6),
        bslib::card(bslib::card_header("Fine-tuned"), shiny::uiOutput(ns("tuned"))),
        bslib::card(bslib::card_header("Base model"), shiny::uiOutput(ns("base")))
      )
    ),
    bslib::card(
      bslib::card_header("Export"),
      bslib::layout_columns(
        col_widths = c(8, 4),
        shiny::textInput(ns("merge_dir"), "Merged model directory", placeholder = "leave blank for <run>/merged", width = "100%"),
        shiny::actionButton(ns("merge"), "Merge and save", class = "btn-outline-primary", style = "margin-top: 32px")
      ),
      shiny::uiOutput(ns("merge_result"))
    )
  )
}

mod_tryit_server <- function(id, state, runs_dir) {
  shiny::moduleServer(id, function(input, output, session) {
    runs <- shiny::reactivePoll(3000, session,
      checkFunc = function() {
        dirs <- list.dirs(runs_dir, recursive = FALSE)
        paste(dirs, file.info(file.path(dirs, "status.json"))$mtime, collapse = "|")
      },
      valueFunc = function() {
        df <- dragon_runs(runs_dir)
        df[file.exists(file.path(df$dir, "adapter", "adapter_config.json")), , drop = FALSE]
      }
    )
    shiny::observe({
      df <- runs()
      selected <- shiny::isolate(input$run)
      if (!is.null(state$run) && state$run$id %in% df$id && (is.null(selected) || !nzchar(selected))) selected <- state$run$id
      labels <- if (nrow(df)) sprintf("%s  [%s]", df$id, df$state) else character()
      shiny::updateSelectInput(session, "run", choices = stats::setNames(df$id, labels),
                               selected = if (!is.null(selected) && selected %in% df$id) selected else df$id[1])
    })

    run <- shiny::reactive({
      shiny::req(input$run)
      dragon_run(file.path(runs_dir, input$run))
    })

    replies <- shiny::reactiveValues(tuned = NULL, base = NULL)

    shiny::observeEvent(input$go, {
      prompt <- trimws(input$prompt %||% "")
      if (!nzchar(prompt)) {
        shiny::showNotification("Type a prompt first.", type = "warning")
        return()
      }
      r <- run()
      sys <- if (nzchar(trimws(input$system %||% ""))) input$system
      replies$tuned <- NULL
      replies$base <- NULL
      shiny::withProgress(message = "Generating with the fine-tuned model", value = 0.3, {
        replies$tuned <- tryCatch(
          dragon_generate(r, prompt, system = sys, max_new_tokens = input$max_new_tokens, temperature = input$temperature),
          error = function(e) { notify_error(e); "(failed)" }
        )
        if (isTRUE(input$compare)) {
          shiny::incProgress(0.4, message = "Generating with the base model")
          replies$base <- tryCatch(
            dragon_generate(r, prompt, system = sys, max_new_tokens = input$max_new_tokens, temperature = input$temperature, base = TRUE),
            error = function(e) { notify_error(e); "(failed)" }
          )
        }
      })
    })

    reply_ui <- function(text) {
      if (is.null(text)) return(shiny::p(class = "hint", "Nothing generated yet."))
      shiny::div(class = "bubble assistant", shiny::div(class = "content", text))
    }
    output$tuned <- shiny::renderUI(reply_ui(replies$tuned))
    output$base <- shiny::renderUI({
      if (!isTRUE(input$compare)) return(shiny::p(class = "hint", "Comparison is off."))
      reply_ui(replies$base)
    })

    merged <- shiny::reactiveVal(NULL)
    shiny::observeEvent(input$merge, {
      r <- run()
      out <- if (nzchar(trimws(input$merge_dir %||% ""))) input$merge_dir else NULL
      shiny::withProgress(message = "Merging adapter into the base model", {
        res <- tryCatch(dragon_merge(r, out), error = function(e) { notify_error(e); NULL })
        merged(res)
      })
    })
    output$merge_result <- shiny::renderUI({
      m <- merged()
      if (is.null(m)) return(NULL)
      shiny::p(class = "text-success small", "Merged model saved to ", shiny::code(m),
               ". It loads with plain transformers and needs nothing from dragonfarm.")
    })
  })
}
