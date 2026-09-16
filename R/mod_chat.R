mod_chat_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::layout_columns(
    col_widths = c(4, 8),
    bslib::card(
      bslib::card_header("Who answers"),
      shiny::selectInput(ns("source"), "Backend", width = "100%",
        choices = c("A run on this machine" = "run", "Ollama on this machine" = "ollama", "OpenAI-compatible server" = "server")),
      shiny::conditionalPanel(
        condition = sprintf("input['%s'] == 'run'", ns("source")),
        shiny::selectInput(ns("run"), "Run", choices = character(), width = "100%"),
        shiny::checkboxInput(ns("base"), "Talk to what it started from instead", value = FALSE)
      ),
      shiny::conditionalPanel(
        condition = sprintf("input['%s'] == 'ollama'", ns("source")),
        shiny::textInput(ns("ollama_model"), "Ollama model name", placeholder = "dragonfarm-20260914-support", width = "100%"),
        shiny::textInput(ns("ollama_url"), "Ollama URL", value = "http://localhost:11434", width = "100%")
      ),
      shiny::conditionalPanel(
        condition = sprintf("input['%s'] == 'server'", ns("source")),
        shiny::textInput(ns("server_url"), "Server URL (ending in /v1)", placeholder = "https://host/v1", width = "100%"),
        shiny::textInput(ns("server_model"), "Model name on the server", width = "100%"),
        shiny::passwordInput(ns("server_key"), "API key (optional)", width = "100%")
      ),
      shiny::textAreaInput(ns("system"), "System prompt (optional)", rows = 3, width = "100%",
                           placeholder = "You are a concise support agent for a smart-home company."),
      bslib::layout_columns(
        col_widths = c(6, 6),
        shiny::numericInput(ns("temperature"), "Temperature", value = 0.7, min = 0, max = 2, step = 0.1),
        shiny::numericInput(ns("max_new_tokens"), "Max new tokens", value = 256, min = 1, step = 16)
      ),
      shiny::div(class = "cloud-actions",
        shiny::actionButton(ns("new"), "New conversation", class = "btn-outline-secondary"),
        shiny::downloadButton(ns("save"), "Save transcript", class = "btn-outline-primary")
      ),
      shiny::p(class = "hint", "The whole conversation is sent on every turn, so the model keeps context. The local worker keeps the model loaded between turns.")
    ),
    bslib::card(
      bslib::card_header(shiny::uiOutput(ns("title"), inline = TRUE)),
      shiny::div(class = "chat-thread", shiny::uiOutput(ns("thread"))),
      shiny::div(class = "chat-compose",
        shiny::textAreaInput(ns("text"), NULL, rows = 2, width = "100%", placeholder = "Type a message"),
        shiny::actionButton(ns("send"), "Send", class = "btn-primary")
      )
    )
  )
}

mod_chat_server <- function(id, state, runs_dir) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    runs <- shiny::reactivePoll(4000, session,
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
      labels <- if (nrow(df)) sprintf("%s  [%s]", df$id, df$stage) else character()
      shiny::updateSelectInput(session, "run", choices = stats::setNames(df$id, labels),
                               selected = if (!is.null(selected) && selected %in% df$id) selected else df$id[1])
    })

    # The conversation is rebuilt when the backend or settings change; the
    # history is kept in a plain list so it survives that.
    history <- shiny::reactiveVal(list())
    chat_obj <- shiny::reactiveVal(NULL)

    backend <- shiny::reactive({
      switch(input$source %||% "run",
        ollama = if (nzchar(trimws(input$ollama_model %||% ""))) dragon_backend_ollama(trimws(input$ollama_model), url = input$ollama_url %||% "http://localhost:11434"),
        server = if (nzchar(trimws(input$server_url %||% "")) && nzchar(trimws(input$server_model %||% "")))
                   dragon_backend_server(trimws(input$server_url), trimws(input$server_model), api_key = input$server_key %||% ""),
        dragon_backend_local()
      )
    })

    build_chat <- function() {
      b <- backend()
      if (is.null(b)) return(NULL)
      x <- NULL
      if (!is_server_backend(b)) {
        shiny::req(input$run)
        x <- dragon_run(file.path(runs_dir, input$run))
      }
      sys <- if (nzchar(trimws(input$system %||% ""))) input$system
      ch <- dragon_chat(x, system = sys, backend = b, max_new_tokens = input$max_new_tokens %||% 256,
                        temperature = input$temperature %||% 0.7, base = isTRUE(input$base), runs_dir = runs_dir)
      ch$messages <- history()
      ch
    }

    output$title <- shiny::renderUI({
      b <- backend()
      if (is.null(b)) return("Conversation")
      what <- if (is_server_backend(b)) b$model else input$run %||% ""
      shiny::span("Conversation with ", shiny::code(what), shiny::span(class = "text-muted small", paste0("  via ", backend_label(b))))
    })

    shiny::observeEvent(input$send, {
      text <- trimws(input$text %||% "")
      if (!nzchar(text)) return()
      ch <- tryCatch(build_chat(), error = function(e) { notify_error(e); NULL })
      if (is.null(ch)) {
        shiny::showNotification("Pick a backend first: a run, an Ollama model, or a server.", type = "warning")
        return()
      }
      shiny::updateTextAreaInput(session, "text", value = "")
      history(c(history(), list(list(role = "user", content = text))))
      shiny::withProgress(message = "Thinking", value = 0.5, {
        reply <- tryCatch(ch$say(text), error = function(e) { notify_error(e); NULL })
      })
      if (is.null(reply)) {
        h <- history()
        history(h[seq_len(length(h) - 1)])   # drop the unanswered user turn
        return()
      }
      history(ch$history())
      chat_obj(ch)
    })

    shiny::observeEvent(input$new, {
      history(list())
      chat_obj(NULL)
    })

    # Per-reply verdicts shown as badges; the record itself goes to feedback.jsonl.
    verdicts <- shiny::reactiveVal(list())

    fb_button <- function(label, action, i, title) {
      shiny::tags$button(
        type = "button", class = "btn btn-sm btn-outline-secondary fb-btn", title = title,
        onclick = sprintf("Shiny.setInputValue('%s', {action: '%s', i: %d, nonce: Math.random()}, {priority: 'event'})", ns("fb"), action, i),
        label
      )
    }

    output$thread <- shiny::renderUI({
      h <- history()
      v <- verdicts()
      if (!length(h)) return(shiny::p(class = "hint", "Nothing yet. Say something below."))
      shiny::tagList(lapply(seq_along(h), function(i) {
        m <- h[[i]]
        controls <- NULL
        if (m$role == "assistant") {
          badge <- v[[as.character(i)]]
          controls <- shiny::div(class = "fb-row",
            fb_button("\U0001F44D", "up", i, "Good reply"),
            fb_button("\U0001F44E", "down", i, "Bad reply"),
            fb_button("Edit", "edit", i, "Replace with a better reply"),
            if (i == length(h)) fb_button("Regenerate", "regen", i, "Ask again"),
            if (!is.null(badge)) shiny::span(class = paste("fb-badge", badge), switch(badge, up = "liked", down = "disliked", edited = "edited"))
          )
        }
        shiny::div(class = paste("bubble", m$role),
          shiny::span(class = "role", if (m$role == "assistant") "model" else "you"),
          shiny::div(class = "content", m$content),
          controls
        )
      }))
    })

    label_now <- function() {
      b <- backend()
      if (!is.null(b) && is_server_backend(b)) b$model else input$run %||% "run"
    }

    shiny::observeEvent(input$fb, {
      ev <- input$fb
      h <- history()
      i <- as.integer(ev$i)
      if (is.na(i) || i > length(h) || !identical(h[[i]]$role, "assistant")) return()
      sys <- if (nzchar(trimws(input$system %||% ""))) input$system
      context <- h[seq_len(i - 1)]
      switch(ev$action,
        up = , down = {
          record_feedback(runs_dir, label_now(), sys, context, h[[i]]$content, rating = if (ev$action == "up") 1 else -1, source = "app")
          v <- verdicts(); v[[as.character(i)]] <- ev$action; verdicts(v)
          shiny::showNotification("Thanks, recorded. dragon_feedback() turns these into training data.", type = "message", duration = 4)
        },
        edit = {
          shiny::showModal(shiny::modalDialog(
            title = "Replace the model's reply",
            shiny::textAreaInput(ns("edit_text"), NULL, value = h[[i]]$content, rows = 8, width = "100%"),
            footer = shiny::tagList(shiny::modalButton("Cancel"), shiny::actionButton(ns("edit_save"), "Save as the better reply", class = "btn-primary")),
            size = "l", easyClose = TRUE
          ))
          session$userData$edit_index <- i
        },
        regen = {
          ch <- tryCatch(build_chat(), error = function(e) { notify_error(e); NULL })
          if (is.null(ch)) return()
          shiny::withProgress(message = "Asking again", value = 0.5, {
            ok <- tryCatch({ ch$regenerate(); TRUE }, error = function(e) { notify_error(e); FALSE })
          })
          if (ok) {
            history(ch$history())
            chat_obj(ch)
            v <- verdicts(); v[[as.character(i)]] <- NULL; verdicts(v)
          }
        }
      )
    })

    shiny::observeEvent(input$edit_save, {
      i <- session$userData$edit_index
      h <- history()
      text <- trimws(input$edit_text %||% "")
      if (is.null(i) || !nzchar(text) || i > length(h)) { shiny::removeModal(); return() }
      sys <- if (nzchar(trimws(input$system %||% ""))) input$system
      record_feedback(runs_dir, label_now(), sys, h[seq_len(i - 1)], h[[i]]$content, edited = text, source = "app")
      h[[i]]$content <- text
      history(h)
      v <- verdicts(); v[[as.character(i)]] <- "edited"; verdicts(v)
      shiny::removeModal()
      shiny::showNotification("Saved. The edited reply is now part of this conversation and of the feedback data.", type = "message", duration = 5)
    })

    output$save <- shiny::downloadHandler(
      filename = function() sprintf("dragonfarm-chat-%s.json", format(Sys.time(), "%Y%m%d-%H%M%S")),
      content = function(file) {
        ch <- chat_obj()
        if (is.null(ch)) {
          write_json(list(format = "dragonfarm-chat", version = 1L, saved_at = now_iso(), messages = history()), file)
        } else {
          ch$save(file)
        }
      },
      contentType = "application/json"
    )
  })
}
