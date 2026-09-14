mod_model_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::layout_columns(
    col_widths = c(7, 5),
    bslib::card(
      bslib::card_header("Pick a base model"),
      shiny::uiOutput(ns("preset_cards")),
      shiny::hr(),
      shiny::textInput(ns("custom"), "Or any Hugging Face model id", placeholder = "org/model-name", width = "100%"),
      shiny::checkboxInput(ns("trust"), "Allow custom code from the model repository (trust_remote_code)", value = FALSE)
    ),
    bslib::card(
      bslib::card_header("This machine"),
      shiny::actionButton(ns("detect"), "Detect hardware", class = "btn-outline-primary"),
      shiny::uiOutput(ns("hardware")),
      shiny::hr(),
      shiny::uiOutput(ns("verdict"))
    )
  )
}

mod_model_server <- function(id, state, nav_to) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    presets <- dragon_presets()

    output$preset_cards <- shiny::renderUI({
      choices <- stats::setNames(presets$id, presets$id)
      shiny::tagList(
        shiny::radioButtons(ns("preset"), NULL, choices = choices, selected = "Qwen/Qwen2.5-0.5B-Instruct", width = "100%"),
        shiny::div(class = "table-wrap", shiny::tableOutput(ns("preset_table")))
      )
    })

    output$preset_table <- shiny::renderTable({
      data.frame(
        Model = presets$id, Size = presets$params, License = presets$license,
        Token = ifelse(presets$gated, "required", ""), `Min VRAM` = paste(presets$min_vram_gb, "GB"),
        Notes = presets$notes, check.names = FALSE
      )
    }, spacing = "xs", width = "100%")

    chosen <- shiny::reactive({
      custom <- trimws(input$custom %||% "")
      if (nzchar(custom)) custom else input$preset
    })
    shiny::observe({
      state$model <- list(id = chosen(), trust_remote_code = isTRUE(input$trust))
    })

    shiny::observeEvent(input$detect, {
      shiny::withProgress(message = "Checking Python and hardware. First time builds the environment.", {
        hw <- tryCatch(hardware_info(), error = function(e) { notify_error(e); NULL })
        state$hardware <- hw
        if (is.null(hw)) shiny::showNotification("Hardware check failed. See the R console.", type = "error")
      })
    })

    output$hardware <- shiny::renderUI({
      hw <- state$hardware
      if (is.null(hw)) return(shiny::p(class = "hint", "Not checked yet. This also prepares the Python environment, which takes a few minutes the first time."))
      shiny::tagList(
        shiny::div(class = "kv", shiny::span("Device"), shiny::strong(hw$device_name)),
        if (identical(hw$device, "cuda")) shiny::div(class = "kv", shiny::span("GPU memory"), shiny::strong(sprintf("%.1f GB", hw$vram_gb))),
        shiny::div(class = "kv", shiny::span("torch"), shiny::strong(hw$torch)),
        shiny::div(class = "kv", shiny::span("transformers"), shiny::strong(hw$transformers))
      )
    })

    output$verdict <- shiny::renderUI({
      id <- chosen()
      shiny::req(id)
      p <- preset_for(id)
      hw <- state$hardware
      notes <- list()
      if (!is.null(p) && p$gated && !hf_token_present()) {
        notes <- c(notes, list(shiny::p(class = "text-danger small",
          "This model is gated. Accept its license on huggingface.co and set HF_TOKEN in the R session before training.")))
      }
      if (!is.null(hw) && !is.null(p)) {
        if (identical(hw$device, "cuda")) {
          if (hw$vram_gb < p$min_vram_gb) {
            notes <- c(notes, list(shiny::p(class = "text-warning small",
              sprintf("Needs about %d GB of GPU memory; this GPU has %.1f GB. Lower the batch size and sequence length, or turn on gradient checkpointing.", p$min_vram_gb, hw$vram_gb))))
          } else {
            notes <- c(notes, list(shiny::p(class = "text-success small", "Fits on this GPU.")))
          }
        } else if (identical(hw$device, "cpu") && p$min_vram_gb > 3) {
          notes <- c(notes, list(shiny::p(class = "text-warning small", "This model is slow to train on a CPU. Try the 135M or 360M models first.")))
        }
      }
      shiny::tagList(
        shiny::div(class = "kv", shiny::span("Selected"), shiny::code(id)),
        notes,
        shiny::actionButton(ns("next"), "Next: training settings", class = "btn-primary")
      )
    })
    shiny::observeEvent(input$`next`, nav_to("train"))
  })
}
