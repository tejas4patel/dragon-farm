# Documents panel: the default way in. Drop files or pages, read and index
# them into a document set, ask questions with cited sources, then carry
# the set into Chat. A table of prompt/response rows is the other route,
# reached from the link at the bottom of the Documents card.

DOCUMENT_EXTENSIONS <- c(".pdf", ".html", ".htm", ".md", ".markdown", ".txt", ".docx", ".xlsx", ".xlsm", ".csv", ".tsv")

mod_documents_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::layout_columns(
    col_widths = c(5, 7),
    bslib::card(
      bslib::card_header("Documents"),
      shiny::div(class = "dropzone",
        shiny::fileInput(ns("files"), label = NULL, multiple = TRUE, buttonLabel = "Browse",
                         placeholder = "Drop PDF, Word, HTML, Markdown, text, or spreadsheet files here",
                         accept = DOCUMENT_EXTENSIONS, width = "100%")
      ),
      bslib::layout_columns(
        col_widths = c(8, 4),
        shiny::textInput(ns("url"), label = NULL, placeholder = "https://... a web page", width = "100%"),
        shiny::actionButton(ns("add_url"), "Add page", class = "btn-outline-secondary", width = "100%")
      ),
      shiny::uiOutput(ns("pending")),
      shiny::textInput(ns("name"), "Name this set", value = "my-documents", width = "100%"),
      shiny::actionButton(ns("build"), "Read and index", class = "btn-primary"),
      shiny::p(class = "hint", "Files are copied into the set's folder under the runs directory, so the set survives this session. Reading the same set again picks up only what changed."),
      shiny::hr(),
      shiny::selectInput(ns("saved"), "Or open a saved set", choices = c("Choose a set" = ""), width = "100%"),
      shiny::uiOutput(ns("summary")),
      shiny::p(class = "hint mt-3", shiny::actionLink(ns("table_route"), "Have a table of prompts and replies instead?"))
    ),
    bslib::card(
      bslib::card_header("Ask"),
      shiny::textAreaInput(ns("question"), label = NULL, rows = 3, width = "100%",
                           placeholder = "Ask anything the documents should be able to answer."),
      bslib::layout_columns(
        col_widths = c(8, 4),
        shiny::selectInput(ns("model"), "Answered by", choices = c("Recommended for this machine" = ""), width = "100%"),
        shiny::numericInput(ns("k"), "Excerpts", value = 4, min = 1, max = 12, step = 1)
      ),
      shiny::div(class = "cloud-actions",
        shiny::actionButton(ns("ask"), "Ask", class = "btn-primary"),
        shiny::actionButton(ns("to_chat"), "Continue in Chat", class = "btn-outline-secondary")
      ),
      shiny::p(class = "hint", "Answers come from the most relevant excerpts, with sources under each answer. Nothing is trained; swap documents and ask again."),
      shiny::uiOutput(ns("answer"))
    )
  )
}

mod_documents_server <- function(id, state, nav_to, runs_dir) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    pending_files <- shiny::reactiveVal(data.frame(name = character(), datapath = character(), stringsAsFactors = FALSE))
    pending_urls <- shiny::reactiveVal(character())
    answer <- shiny::reactiveVal(NULL)

    shiny::observeEvent(input$files, {
      f <- input$files
      keep <- tolower(paste0(".", tools::file_ext(f$name))) %in% DOCUMENT_EXTENSIONS
      if (any(!keep)) shiny::showNotification(sprintf("Skipped %s: not a supported document type.", paste(f$name[!keep], collapse = ", ")), type = "warning")
      cur <- pending_files()
      add <- f[keep, c("name", "datapath"), drop = FALSE]
      cur <- rbind(cur[!cur$name %in% add$name, , drop = FALSE], add)
      pending_files(cur)
    })

    shiny::observeEvent(input$add_url, {
      u <- trimws(input$url %||% "")
      if (!nzchar(u)) return()
      if (!grepl("^https?://", u, ignore.case = TRUE)) u <- paste0("https://", u)
      pending_urls(unique(c(pending_urls(), u)))
      shiny::updateTextInput(session, "url", value = "")
    })

    output$pending <- shiny::renderUI({
      files <- pending_files(); urls <- pending_urls()
      if (!nrow(files) && !length(urls)) return(NULL)
      shiny::div(class = "pending-list",
        if (nrow(files)) shiny::tags$ul(lapply(files$name, shiny::tags$li)),
        if (length(urls)) shiny::tags$ul(lapply(urls, function(u) shiny::tags$li(shiny::code(u))))
      )
    })

    saved_sets <- shiny::reactivePoll(4000, session,
      checkFunc = function() runs_change_signature(file.path(runs_dir, "documents")),
      valueFunc = function() tryCatch(dragon_documents_list(runs_dir), error = function(e) NULL)
    )
    shiny::observe({
      sets <- saved_sets()
      choices <- c("Choose a set" = "")
      if (!is.null(sets) && nrow(sets)) choices <- c(choices, stats::setNames(sets$dir, sprintf("%s (%d chunks)", sets$name, sets$chunks)))
      current <- shiny::isolate(state$documents)
      shiny::updateSelectInput(session, "saved", choices = choices,
                               selected = if (!is.null(current) && current$dir %in% choices) current$dir else "")
    })
    shiny::observeEvent(input$saved, {
      d <- input$saved
      if (is.null(d) || !nzchar(d)) return()
      cur <- state$documents
      if (!is.null(cur) && identical(cur$dir, d)) return()
      docs <- tryCatch(dragon_documents_load(d), error = function(e) { notify_error(e); NULL })
      if (!is.null(docs)) { state$documents <- docs; answer(NULL) }
    })

    # Read and index: uploads are copied into <set>/uploads so their paths
    # outlive the session's temp files, then dragon_documents() does the rest.
    shiny::observeEvent(input$build, {
      files <- pending_files(); urls <- pending_urls()
      name <- slugify(input$name %||% "")
      if (!nrow(files) && !length(urls)) {
        shiny::showNotification("Add at least one file or page first.", type = "warning")
        return()
      }
      upload_dir <- file.path(runs_dir, "documents", name, "uploads")
      dir.create(upload_dir, recursive = TRUE, showWarnings = FALSE)
      if (nrow(files)) file.copy(files$datapath, file.path(upload_dir, files$name), overwrite = TRUE)
      paths <- c(if (dir.exists(upload_dir) && length(list.files(upload_dir))) upload_dir, urls)
      shiny::withProgress(message = "Reading and indexing. The first time downloads a small embedding model.", value = 0.4, {
        docs <- tryCatch(dragon_documents(paths, name = name, runs_dir = runs_dir), error = function(e) { notify_error(e); NULL })
      })
      if (is.null(docs)) return()
      state$documents <- docs
      answer(NULL)
      pending_files(pending_files()[0, , drop = FALSE])
      pending_urls(character())
      shiny::showNotification(sprintf("%s: %d chunks ready to ask.", docs$name, docs$manifest$n_chunks), type = "message", duration = 5)
    })

    output$summary <- shiny::renderUI({
      docs <- state$documents
      if (is.null(docs)) return(shiny::p(class = "hint", "No document set yet. Drop files above, or open a saved set."))
      m <- docs$manifest
      shiny::tagList(
        shiny::div(class = "kv", shiny::span("Set"), shiny::strong(docs$name)),
        shiny::tags$ul(class = "source-list", lapply(m$sources, function(s) {
          flags <- c(if (isTRUE(s$changelog_like)) "changelog, down-weighted", if (!is.null(s$error)) paste("could not read:", s$error))
          shiny::tags$li(s$name, sprintf(" — %d chunks", as.integer(s$n_chunks)),
                         if (length(flags)) shiny::span(class = "text-muted small", paste0(" (", paste(flags, collapse = "; "), ")")))
        })),
        shiny::div(class = "kv", shiny::span("Index"), shiny::strong(if (is.null(m$index)) "not built yet" else m$index$model))
      )
    })

    runs <- shiny::reactivePoll(4000, session,
      checkFunc = function() runs_change_signature(runs_dir),
      valueFunc = function() {
        df <- dragon_runs(runs_dir)
        df[file.exists(file.path(df$dir, "adapter", "adapter_config.json")), , drop = FALSE]
      }
    )
    shiny::observe({
      df <- runs()
      hw <- state$hardware
      rec <- if (!is.null(hw$tier)) sprintf("Recommended for this machine (%s)", hw$tier$model) else "Recommended for this machine"
      choices <- stats::setNames("", rec)
      if (nrow(df)) choices <- c(choices, stats::setNames(paste0("run:", df$id), paste("Run", df$id)))
      choices <- c(choices, stats::setNames(dragon_presets()$id, dragon_presets()$id))
      shiny::updateSelectInput(session, "model", choices = choices, selected = shiny::isolate(input$model) %||% "")
    })
    chosen_model <- function() {
      m <- input$model
      if (is.null(m) || !nzchar(m)) return(NULL)
      if (startsWith(m, "run:")) dragon_run(file.path(runs_dir, sub("^run:", "", m))) else m
    }

    shiny::observeEvent(input$ask, {
      q <- trimws(input$question %||% "")
      if (!nzchar(q)) { shiny::showNotification("Type a question first.", type = "warning"); return() }
      docs <- state$documents
      if (is.null(docs)) { shiny::showNotification("Read some documents first, or open a saved set.", type = "warning"); return() }
      shiny::withProgress(message = "Finding excerpts and answering. The first question loads the model.", value = 0.4, {
        ans <- tryCatch(dragon_ask(docs, q, model = chosen_model(), k = input$k %||% 4), error = function(e) { notify_error(e); NULL })
      })
      if (!is.null(ans)) answer(ans)
    })

    output$answer <- shiny::renderUI({
      a <- answer()
      if (is.null(a)) return(NULL)
      shiny::tagList(
        shiny::div(class = "bubble user", shiny::span(class = "role", "you"), shiny::div(class = "content", a$question)),
        shiny::div(class = "bubble assistant", shiny::span(class = "role", a$model), shiny::div(class = "content", a$answer), sources_footnotes(a$sources))
      )
    })

    shiny::observeEvent(input$to_chat, {
      if (is.null(state$documents)) { shiny::showNotification("Read some documents first.", type = "warning"); return() }
      nav_to("chat")
    })
    shiny::observeEvent(input$table_route, {
      state$route <- "table"
      nav_to("data")
    })
  })
}
