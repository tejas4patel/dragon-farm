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
      bslib::card_header("Judge"),
      shiny::p(class = "hint", "Ask a stronger model to compare this run's replies with another model's on the held-out prompts. Each pair is judged twice with the order swapped, so a judge that favours the first answer cannot tip the result."),
      bslib::layout_columns(
        col_widths = c(4, 4, 2, 2),
        shiny::selectInput(ns("judge_kind"), "Judge", choices = c("Claude API (ANTHROPIC_API_KEY)" = "anthropic", "Local model" = "local")),
        shiny::uiOutput(ns("judge_model_ui")),
        shiny::selectInput(ns("against"), "Compare with", choices = c("What it started from" = "base", "Nothing: score 1-10" = "none")),
        shiny::numericInput(ns("judge_n"), "Prompts", value = 10, min = 1, max = 200, step = 1)
      ),
      shiny::textInput(ns("rubric"), "Rubric (optional)", width = "100%",
                       placeholder = "Reward replies that give concrete next steps and stay under 120 words."),
      shiny::actionButton(ns("judge"), "Run judge", class = "btn-outline-primary"),
      shiny::uiOutput(ns("judge_out"))
    ),
    bslib::card(
      bslib::card_header("Improve: preference pairs from this run's own replies"),
      shiny::p(class = "hint", "Closes the loop. The run answers each prompt several times, the judge above scores every sample, and the best and worst become chosen and rejected pairs. The pairs load into the Map step, ready for a DPO or ORPO stage that starts from this run."),
      bslib::layout_columns(
        col_widths = c(3, 3, 3, 3),
        shiny::selectInput(ns("synth_split"), "Prompts from", choices = c("Training rows" = "train", "Held-out rows" = "eval")),
        shiny::numericInput(ns("synth_n"), "Prompts", value = 50, min = 2, max = 2000, step = 10),
        shiny::numericInput(ns("synth_samples"), "Samples per prompt", value = 4, min = 2, max = 8, step = 1),
        shiny::numericInput(ns("synth_gap"), "Min score gap", value = 2, min = 0, max = 9, step = 0.5)
      ),
      shiny::actionButton(ns("synth"), "Build preference pairs", class = "btn-outline-primary"),
      shiny::uiOutput(ns("synth_out"))
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

    output$judge_model_ui <- shiny::renderUI({
      if (identical(input$judge_kind, "local")) {
        shiny::textInput(session$ns("judge_model"), "Model id or directory", value = "Qwen/Qwen2.5-1.5B-Instruct")
      } else {
        shiny::selectInput(session$ns("judge_model"), "Model",
                           choices = c("claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5"))
      }
    })

    judgement <- shiny::reactiveVal(NULL)
    shiny::observeEvent(input$judge, {
      r <- run()
      judge <- if (identical(input$judge_kind, "local")) {
        trimws(input$judge_model %||% "")
      } else {
        if (!nzchar(Sys.getenv("ANTHROPIC_API_KEY"))) {
          shiny::showNotification("Set ANTHROPIC_API_KEY in the R session before using the Claude API as judge, or pick a local model.", type = "warning", duration = 10)
          return()
        }
        dragon_judge_anthropic(model = input$judge_model %||% "claude-opus-5")
      }
      if (is.character(judge) && !nzchar(judge)) {
        shiny::showNotification("Name a local model to judge with.", type = "warning")
        return()
      }
      rubric <- if (nzchar(trimws(input$rubric %||% ""))) input$rubric
      against <- if (identical(input$against, "none")) NULL else "base"
      shiny::withProgress(message = "Generating replies and judging", detail = "Two model loads plus the judge calls; this takes a few minutes", {
        res <- tryCatch(
          suppressMessages(dragon_judge(r, against = against, n = input$judge_n %||% 10, judge = judge, rubric = rubric)),
          error = function(e) { notify_error(e); NULL }
        )
        judgement(res)
      })
    })

    output$judge_out <- shiny::renderUI({
      j <- judgement()
      if (is.null(j)) return(NULL)
      s <- j$summary
      headline <- if (identical(j$mode, "pairwise")) {
        sprintf("Wins %.0f%% \u00b7 ties %.0f%% \u00b7 losses %.0f%% over %d prompts (position-consistent %.0f%%)",
                100 * s$win_rate, 100 * s$tie_rate, 100 * s$loss_rate, s$n, 100 * s$position_consistency)
      } else {
        sprintf("Mean score %.2f / 10 over %d prompts", s$mean_score, s$n)
      }
      d <- j$details
      rows <- lapply(seq_len(min(nrow(d), 5)), function(i) {
        if (identical(j$mode, "pairwise")) {
          shiny::div(class = "judge-row",
            shiny::div(class = "judge-prompt", d$prompt[i]),
            shiny::div(class = paste("judge-verdict", d$verdict[i]),
                       switch(d$verdict[i], a = "this run", b = j$against, tie = "tie", "unparsed")))
        } else {
          shiny::div(class = "judge-row",
            shiny::div(class = "judge-prompt", d$prompt[i]),
            shiny::div(class = "judge-verdict", sprintf("%s / 10", d$score[i])))
        }
      })
      shiny::tagList(
        shiny::p(class = "text-success small", headline),
        if (isTRUE(s$unparsed > 0)) shiny::p(class = "text-warning small", sprintf("%d judge replies could not be parsed.", s$unparsed)),
        rows,
        shiny::p(class = "hint", "Saved to judge.json in the run; the Monitor panel's comparison table shows it.")
      )
    })

    synth_result <- shiny::reactiveVal(NULL)
    shiny::observeEvent(input$synth, {
      r <- run()
      judge <- if (identical(input$judge_kind, "local")) {
        trimws(input$judge_model %||% "")
      } else {
        if (!nzchar(Sys.getenv("ANTHROPIC_API_KEY"))) {
          shiny::showNotification("Set ANTHROPIC_API_KEY in the R session before using the Claude API as judge, or pick a local model in the Judge card.", type = "warning", duration = 10)
          return()
        }
        dragon_judge_anthropic(model = input$judge_model %||% "claude-opus-5")
      }
      if (is.character(judge) && !nzchar(judge)) {
        shiny::showNotification("Name a local judge model in the Judge card.", type = "warning")
        return()
      }
      prompts <- dragon_prompts(r, input$synth_split %||% "train", n = input$synth_n %||% 50)
      if (length(prompts) < 2) {
        shiny::showNotification("This run has too few prompts in that split.", type = "warning")
        return()
      }
      rubric <- if (nzchar(trimws(input$rubric %||% ""))) input$rubric
      shiny::withProgress(message = "Sampling replies and scoring them", detail = "One model load, then the judge calls", {
        ds <- tryCatch(
          suppressMessages(dragon_synthesize_pairs(prompts, student = r, judge = judge,
                                                   n_samples = input$synth_samples %||% 4, min_gap = input$synth_gap %||% 2,
                                                   rubric = rubric, runs_dir = runs_dir)),
          error = function(e) { notify_error(e); NULL }
        )
        if (!is.null(ds)) {
          state$dataset <- ds
          state$mapped <- ds
          synth_result(list(n = nrow(ds$data), file = ds$source, run = r$id,
                            chosen = mean(ds$data$chosen_score), rejected = mean(ds$data$rejected_score)))
          shiny::showNotification(sprintf("%d pairs loaded. Go to Train, pick %s under Start from, and run DPO.", nrow(ds$data), r$id),
                                  type = "message", duration = 12)
        }
      })
    })

    output$synth_out <- shiny::renderUI({
      s <- synth_result()
      if (is.null(s)) return(NULL)
      shiny::tagList(
        shiny::p(class = "text-success small",
                 sprintf("%d pairs built from %s (mean judge score: chosen %.1f, rejected %.1f).", s$n, s$run, s$chosen, s$rejected)),
        shiny::p(class = "hint", "Saved to ", shiny::code(s$file), " and loaded as the current dataset. In Train, choose this run under Start from; the stage switches to preference optimization automatically.")
      )
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
