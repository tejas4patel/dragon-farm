mod_train_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::layout_columns(
    col_widths = c(7, 5),
    bslib::card(
      bslib::card_header("Training settings"),
      shiny::uiOutput(ns("stage_ui")),
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
      shiny::selectInput(ns("base_run"), "Start from", choices = c("The model chosen in step 3" = ""), width = "100%"),
      shiny::uiOutput(ns("checklist")),
      shiny::actionButton(ns("start"), "Start training", class = "btn-primary btn-lg", width = "100%"),
      shiny::uiOutput(ns("launched")),
      shiny::hr(),
      bslib::accordion(
        id = ns("cloud_acc"), open = FALSE,
        bslib::accordion_panel(
          "No GPU here? Train on a cloud GPU", value = "cloud",
          shiny::p(class = "hint", "Same run, different machine: package it as a zip, open a free or rented GPU notebook, upload the zip, run all cells, then import the results in Monitor."),
          shiny::selectInput(ns("provider"), "Provider", choices = cloud_provider_choices(), width = "100%"),
          shiny::actionButton(ns("bundle"), "Prepare cloud bundle", class = "btn-outline-primary"),
          shiny::uiOutput(ns("cloud_ready"))
        )
      )
    )
  )
}

mod_train_server <- function(id, state, nav_to, runs_dir = dragon_runs_dir()) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    kind <- shiny::reactive({
      m <- state$mapped
      if (is.null(m)) "messages" else mapping_kind(m) %||% "messages"
    })
    is_pairs <- shiny::reactive(identical(kind(), "pairs"))
    is_rl <- shiny::reactive(identical(kind(), "prompts"))

    # Preference and RL runs need lower learning rates; nudge the defaults
    # once when the mapping switches kind.
    shiny::observeEvent(kind(), {
      switch(kind(),
        pairs = {
          shiny::updateNumericInput(session, "learning_rate", value = 5e-5)
          shiny::updateNumericInput(session, "epochs", value = 2)
        },
        prompts = {
          shiny::updateNumericInput(session, "learning_rate", value = 1e-5)
          shiny::updateNumericInput(session, "epochs", value = 1)
          shiny::updateNumericInput(session, "grad_accum", value = 1)
        },
        {
          shiny::updateNumericInput(session, "learning_rate", value = 2e-4)
          shiny::updateNumericInput(session, "epochs", value = 3)
        }
      )
    }, ignoreInit = TRUE)

    output$stage_ui <- shiny::renderUI({
      if (is_rl()) {
        return(shiny::div(class = "stage-box",
          shiny::p(class = "text-muted small", "Stage: reinforcement learning (GRPO). The model writes several answers per prompt; the rewards below decide which ones it learns from."),
          shiny::checkboxGroupInput(ns("reward_types"), "Rewards (summed)", inline = TRUE,
            choices = c("numeric answer" = "numeric", "exact match" = "exact", "contains reference" = "contains",
                        "valid JSON" = "json", "length cap" = "length", "keywords" = "keyword", "regex" = "regex"),
            selected = "numeric"),
          bslib::layout_columns(
            col_widths = c(4, 4, 4),
            shiny::textInput(ns("reward_regex"), "Regex pattern", placeholder = "^T-\\d{4}"),
            shiny::textInput(ns("reward_words"), "Keywords (comma separated)", placeholder = "refund, replace"),
            shiny::numericInput(ns("reward_max_chars"), "Max characters", value = 400, min = 10, step = 10)
          ),
          bslib::layout_columns(
            col_widths = c(3, 3, 3, 3),
            shiny::numericInput(ns("group_size"), "Samples per prompt", value = 4, min = 2, max = 16, step = 1),
            shiny::numericInput(ns("kl_beta"), "KL beta", value = 0.04, min = 0, max = 1, step = 0.01),
            shiny::numericInput(ns("rl_temperature"), "Temperature", value = 1.0, min = 0.1, max = 2, step = 0.1),
            shiny::numericInput(ns("rl_max_new_tokens"), "Max new tokens", value = 128, min = 8, step = 8)
          )
        ))
      }
      if (!is_pairs()) {
        return(shiny::p(class = "text-muted small", "Stage: supervised fine-tuning on prompt and response rows."))
      }
      shiny::div(class = "stage-box",
        shiny::p(class = "text-muted small", "Stage: preference optimization on chosen and rejected pairs."),
        bslib::layout_columns(
          col_widths = c(6, 6),
          shiny::selectInput(ns("method"), "Method",
                             choices = c("DPO (needs a fine-tuned start)" = "dpo", "ORPO (works from a base model)" = "orpo")),
          shiny::numericInput(ns("beta"), "Beta (preference strength)", value = 0.1, min = 0.001, max = 10, step = 0.05)
        )
      )
    })

    # Finished runs with an adapter can be the starting point of the next stage.
    base_runs <- shiny::reactivePoll(4000, session,
      checkFunc = function() {
        dirs <- list.dirs(runs_dir, recursive = FALSE)
        paste(dirs, file.info(file.path(dirs, "status.json"))$mtime, collapse = "|")
      },
      valueFunc = function() {
        df <- dragon_runs(runs_dir)
        df[df$state == "succeeded" & file.exists(file.path(df$dir, "adapter", "adapter_config.json")), , drop = FALSE]
      }
    )
    shiny::observe({
      df <- base_runs()
      labels <- if (nrow(df)) sprintf("%s  [%s, %s]", df$id, df$stage, basename(df$model)) else character()
      choices <- c("The model chosen in step 3" = "", stats::setNames(df$id, labels))
      selected <- shiny::isolate(input$base_run)
      shiny::updateSelectInput(session, "base_run", choices = choices,
                               selected = if (!is.null(selected) && selected %in% choices) selected else "")
    })

    base <- shiny::reactive({
      id <- input$base_run
      if (is.null(id) || !nzchar(id)) return(NULL)
      dir <- file.path(runs_dir, id)
      if (!file.exists(file.path(dir, "config.json"))) return(NULL)
      dragon_run(dir)
    })

    problems <- shiny::reactive({
      out <- character()
      if (is.null(state$dataset)) out <- c(out, "Load a dataset (step 1).")
      if (is.null(state$mapped)) out <- c(out, "Map the columns (step 2).")
      if (is.null(base()) && (is.null(state$model$id) || !nzchar(state$model$id))) out <- c(out, "Choose a model (step 3) or a run to start from.")
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
      b <- base()
      shiny::tags$ul(class = "checklist ok",
        shiny::tags$li(sprintf("%d %s, %d held out", n - n_eval, switch(kind(), pairs = "training pairs", prompts = "prompts", "training rows"), n_eval)),
        shiny::tags$li(if (is.null(b)) shiny::code(state$model$id) else shiny::span("Continue from run ", shiny::code(b$id))),
        shiny::tags$li(if (is_pairs()) sprintf("%s, beta %s", toupper(input$method %||% "dpo"), input$beta %||% 0.1)
                       else if (is_rl()) sprintf("GRPO, %d samples per prompt, rewards: %s", input$group_size %||% 4, paste(input$reward_types %||% "numeric", collapse = ", "))
                       else "Supervised fine-tuning"),
        shiny::tags$li(sprintf("Effective batch %d, about %d optimizer steps", eff, as.integer(steps)))
      )
    })

    # Everything the launcher needs, built from the form. Shared by local
    # training and the cloud bundle so both produce the same run.
    settings <- function() {
      max_steps <- if (is.na(input$max_steps %||% NA)) NULL else as.integer(input$max_steps)
      b <- base()
      list(
        dataset = dragon_split(state$mapped, eval_frac = input$eval_frac %||% 0.05, seed = input$seed %||% 42),
        model = if (is.null(b)) state$model$id else b,
        kind = kind(),
        method = input$method %||% "dpo",
        beta = if (is_rl()) input$kl_beta %||% 0.04 else input$beta %||% 0.1,
        rewards = if (is_rl()) rewards_from_inputs(input),
        group_size = input$group_size %||% 4,
        rl_temperature = input$rl_temperature %||% 1.0,
        rl_max_new_tokens = input$rl_max_new_tokens %||% 128,
        lora = dragon_lora(r = input$rank, alpha = input$alpha, dropout = input$dropout),
        args = dragon_train_args(
          epochs = input$epochs, learning_rate = input$learning_rate,
          batch_size = input$batch_size, grad_accum = input$grad_accum,
          max_seq_len = input$max_seq_len, max_steps = max_steps,
          save_steps = input$save_steps, gradient_checkpointing = isTRUE(input$grad_ckpt),
          seed = input$seed, logging_steps = 1
        ),
        name = if (nzchar(trimws(input$name %||% ""))) input$name,
        trust_remote_code = isTRUE(state$model$trust_remote_code)
      )
    }

    launch <- function(s, hardware) {
      if (identical(s$kind, "prompts")) {
        return(dragon_reinforce(s$dataset, s$model, rewards = s$rewards, group_size = s$group_size, beta = s$beta,
                                temperature = s$rl_temperature, max_new_tokens = s$rl_max_new_tokens,
                                lora = s$lora, args = s$args, hardware = hardware, name = s$name,
                                trust_remote_code = s$trust_remote_code))
      }
      if (identical(s$kind, "pairs")) {
        dragon_prefer(s$dataset, s$model, method = s$method, beta = s$beta, lora = s$lora, args = s$args,
                      hardware = hardware, name = s$name, trust_remote_code = s$trust_remote_code)
      } else {
        dragon_train(s$dataset, s$model, lora = s$lora, args = s$args, hardware = hardware,
                     name = s$name, trust_remote_code = s$trust_remote_code)
      }
    }

    shiny::observeEvent(input$start, {
      p <- problems()
      if (length(p)) {
        shiny::showNotification(paste(p, collapse = " "), type = "warning")
        return()
      }
      run <- tryCatch({
        s <- settings()
        shiny::withProgress(message = "Launching trainer", detail = "Preparing Python on first use", {
          launch(s, dragon_hardware(device = input$device, dtype = input$dtype))
        })
      }, error = function(e) { notify_error(e); NULL })
      if (!is.null(run)) {
        state$run <- run
        shiny::showNotification(sprintf("Run %s launched.", run$id), type = "message")
        nav_to("monitor")
      }
    })

    # Cloud GPU path: the same settings, but the run is zipped instead of launched.
    shiny::observe({
      hw <- state$hardware
      if (!is.null(hw) && identical(hw$device, "cpu")) {
        bslib::accordion_panel_open("cloud_acc", "cloud", session = session)
      }
    })

    shiny::observeEvent(input$bundle, {
      p <- problems()
      if (length(p)) {
        shiny::showNotification(paste(p, collapse = " "), type = "warning")
        return()
      }
      provider <- input$provider %||% "colab"
      res <- tryCatch({
        s <- settings()
        run <- dragon_bundle(s$dataset, s$model, lora = s$lora, args = s$args, name = s$name,
                             trust_remote_code = s$trust_remote_code,
                             method = if (identical(s$kind, "pairs")) s$method, beta = s$beta,
                             rewards = s$rewards, group_size = s$group_size,
                             temperature = s$rl_temperature, max_new_tokens = s$rl_max_new_tokens)
        info <- dragon_remote(run, provider, open = FALSE)
        list(run = run, info = info)
      }, error = function(e) { notify_error(e); NULL })
      if (!is.null(res)) {
        state$run <- res$run
        state$cloud <- list(run_id = res$run$id, provider = provider, url = res$info$url,
                            bundle = res$info$bundle, steps = res$info$steps)
        shiny::showNotification(sprintf("Bundle ready for %s.", provider_name(provider)), type = "message")
      }
    })

    output$bundle_zip <- shiny::downloadHandler(
      filename = function() basename(state$cloud$bundle),
      content = function(file) file.copy(state$cloud$bundle, file),
      contentType = "application/zip"
    )

    output$cloud_ready <- shiny::renderUI({
      cl <- state$cloud
      if (is.null(cl)) return(NULL)
      shiny::div(class = "cloud-ready",
        shiny::p(class = "small", "Run ", shiny::code(cl$run_id), " is bundled (", file_size_label(cl$bundle), ")."),
        shiny::div(class = "cloud-actions",
          shiny::downloadButton(ns("bundle_zip"), "Download bundle", class = "btn-primary"),
          shiny::tags$a(href = cl$url, target = "_blank", rel = "noopener", class = "btn btn-outline-primary",
                        paste("Open", provider_name(cl$provider)))
        ),
        shiny::tags$ol(class = "cloud-steps", lapply(cl$steps, shiny::tags$li)),
        shiny::p(class = "hint", "When the notebook finishes, import the results zip in the Monitor panel.")
      )
    })

    output$launched <- shiny::renderUI({
      run <- state$run
      if (is.null(run)) return(NULL)
      shiny::p(class = "small text-muted", "Latest run: ", shiny::code(run$id))
    })
  })
}


# Reward list from the Train panel's inputs.
rewards_from_inputs <- function(input) {
  types <- input$reward_types %||% "numeric"
  out <- lapply(types, function(tp) {
    switch(tp,
      regex = if (nzchar(trimws(input$reward_regex %||% ""))) dragon_reward("regex", pattern = input$reward_regex),
      keyword = {
        words <- trimws(strsplit(input$reward_words %||% "", ",")[[1]])
        words <- words[nzchar(words)]
        if (length(words)) dragon_reward("keyword", words = words)
      },
      length = dragon_reward("length", max_chars = as.integer(input$reward_max_chars %||% 400), weight = 0.5),
      dragon_reward(tp)
    )
  })
  out <- Filter(Negate(is.null), out)
  if (!length(out)) cli::cli_abort("Pick at least one reward (a regex reward needs a pattern, a keyword reward needs words).")
  out
}
