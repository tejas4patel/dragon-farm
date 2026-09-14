mod_train_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::layout_columns(
    col_widths = c(7, 5),
    bslib::card(
      bslib::card_header("Training settings"),
      bslib::layout_columns(
        col_widths = c(6, 6),
        shiny::numericInput(ns("epochs"), "Epochs", value = 3, min = 0.1, step = 0.5),
        shiny::numericInput(ns("learning_rate"), "Learning rate", value = 2e-4, min = 1e-6, max = 1e-2, step = 1e-5),
        shiny::numericInput(ns("rank"), "LoRA rank", value = 16, min = 1, max = 256, step = 1),
        shiny::numericInput(ns("max_seq_len"), "Max sequence length (tokens)", value = 1024, min = 64, step = 64),
        shiny::numericInput(ns("batch_size"), "Batch size", value = 4, min = 1, step = 1),
        shiny::numericInput(ns("grad_accum"), "Gradient accumulation", value = 4, min = 1, step = 1)
      ),
      bslib::accordion(
        open = FALSE,
        bslib::accordion_panel(
          "Advanced",
          bslib::layout_columns(
            col_widths = c(6, 6),
            shiny::numericInput(ns("alpha"), "LoRA alpha", value = 32, min = 1, step = 1),
            shiny::numericInput(ns("dropout"), "LoRA dropout", value = 0.05, min = 0, max = 0.9, step = 0.01),
            shiny::numericInput(ns("max_steps"), "Max steps (blank = use epochs)", value = NA, min = 1, step = 1),
            shiny::numericInput(ns("eval_frac"), "Held-out fraction", value = 0.05, min = 0, max = 0.5, step = 0.01),
            shiny::numericInput(ns("save_steps"), "Checkpoint every N steps", value = 100, min = 1, step = 1),
            shiny::numericInput(ns("seed"), "Seed", value = 42, step = 1),
            shiny::selectInput(ns("device"), "Device", choices = c("auto", "cuda", "mps", "cpu")),
            shiny::selectInput(ns("dtype"), "Precision", choices = c("auto", "bfloat16", "float16", "float32")),
            shiny::checkboxInput(ns("grad_ckpt"), "Gradient checkpointing (less memory, slower)", value = FALSE),
            shiny::textInput(ns("name"), "Run label", placeholder = "optional")
          )
        )
      )
    ),
    bslib::card(
      bslib::card_header("Ready?"),
      shiny::uiOutput(ns("checklist")),
      shiny::actionButton(ns("start"), "Start training", class = "btn-primary btn-lg", width = "100%"),
      shiny::uiOutput(ns("launched"))
    )
  )
}

mod_train_server <- function(id, state, nav_to) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    problems <- shiny::reactive({
      out <- character()
      if (is.null(state$dataset)) out <- c(out, "Load a dataset (step 1).")
      if (is.null(state$mapped)) out <- c(out, "Map prompt and response columns (step 2).")
      if (is.null(state$model$id) || !nzchar(state$model$id)) out <- c(out, "Choose a model (step 3).")
      out
    })

    output$checklist <- shiny::renderUI({
      p <- problems()
      if (length(p)) {
        return(shiny::tags$ul(class = "checklist bad", lapply(p, shiny::tags$li)))
      }
      ds <- state$mapped
      n <- nrow(ds$data)
      n_eval <- floor(n * (input$eval_frac %||% 0.05))
      eff <- (input$batch_size %||% 4) * (input$grad_accum %||% 4)
      steps <- if (!is.na(input$max_steps %||% NA)) input$max_steps else ceiling((n - n_eval) / eff) * (input$epochs %||% 3)
      shiny::tags$ul(class = "checklist ok",
        shiny::tags$li(sprintf("%d training rows, %d held out", n - n_eval, n_eval)),
        shiny::tags$li(shiny::code(state$model$id)),
        shiny::tags$li(sprintf("Effective batch %d, about %d optimizer steps", eff, as.integer(steps)))
      )
    })

    shiny::observeEvent(input$start, {
      p <- problems()
      if (length(p)) {
        shiny::showNotification(paste(p, collapse = " "), type = "warning")
        return()
      }
      ds <- dragon_split(state$mapped, eval_frac = input$eval_frac %||% 0.05, seed = input$seed %||% 42)
      max_steps <- if (is.na(input$max_steps %||% NA)) NULL else as.integer(input$max_steps)
      run <- tryCatch({
        shiny::withProgress(message = "Launching trainer", detail = "Preparing Python on first use", {
          dragon_train(
            ds, state$model$id,
            lora = dragon_lora(r = input$rank, alpha = input$alpha, dropout = input$dropout),
            args = dragon_train_args(
              epochs = input$epochs, learning_rate = input$learning_rate,
              batch_size = input$batch_size, grad_accum = input$grad_accum,
              max_seq_len = input$max_seq_len, max_steps = max_steps,
              save_steps = input$save_steps, gradient_checkpointing = isTRUE(input$grad_ckpt),
              seed = input$seed, logging_steps = 1
            ),
            hardware = dragon_hardware(device = input$device, dtype = input$dtype),
            name = if (nzchar(trimws(input$name %||% ""))) input$name,
            trust_remote_code = isTRUE(state$model$trust_remote_code)
          )
        })
      }, error = function(e) { notify_error(e); NULL })
      if (!is.null(run)) {
        state$run <- run
        shiny::showNotification(sprintf("Run %s launched.", run$id), type = "message")
        nav_to("monitor")
      }
    })

    output$launched <- shiny::renderUI({
      run <- state$run
      if (is.null(run)) return(NULL)
      shiny::p(class = "small text-muted", "Latest run: ", shiny::code(run$id))
    })
  })
}
