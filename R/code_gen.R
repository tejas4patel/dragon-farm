#' R code that reproduces a run
#'
#' Every run, including ones started from the Shiny app, can be replayed as
#' a script. The dataset path is the original source when it was a file.
#'
#' @param run A `dragon_run` or run directory.
#' @return A single string of R code.
#' @export
dragon_code <- function(run) {
  run <- dragon_run(run)
  cfg <- run_config(run)
  meta <- if (file.exists(run_path(run, "dataset.json"))) read_json(run_path(run, "dataset.json")) else list()
  src <- meta$source %||% "path/to/your/data.csv"
  m <- meta$mapping %||% list(prompt = "prompt", response = "response")
  fmt <- function(x) if (is.null(x)) "NULL" else deparse(x)
  lora_line <- sprintf("dragon_lora(r = %d, alpha = %s, dropout = %s, target_modules = %s)",
                       cfg$lora$r, fmt(cfg$lora$alpha), fmt(cfg$lora$dropout),
                       if (is.list(cfg$lora$target_modules)) fmt(unlist(cfg$lora$target_modules)) else fmt(cfg$lora$target_modules))
  t <- cfg$train
  args_parts <- c(
    sprintf("epochs = %s", fmt(t$epochs)),
    sprintf("learning_rate = %s", fmt(t$learning_rate)),
    sprintf("batch_size = %d", t$per_device_batch_size),
    sprintf("grad_accum = %d", t$gradient_accumulation),
    sprintf("max_seq_len = %d", t$max_seq_len),
    if (!is.null(t$max_steps)) sprintf("max_steps = %d", t$max_steps),
    if (isTRUE(t$gradient_checkpointing)) "gradient_checkpointing = TRUE",
    sprintf("seed = %d", t$seed)
  )
  hw <- cfg$hardware
  hw_line <- sprintf("dragon_hardware(device = %s, dtype = %s%s)", fmt(hw$device), fmt(hw$dtype),
                     if (isTRUE(hw$load_in_4bit)) ", load_in_4bit = TRUE" else "")
  map_line <- sprintf("dragon_map(prompt = %s, response = %s%s)", fmt(m$prompt), fmt(m$response),
                      if (!is.null(m$system)) paste0(", system = ", fmt(m$system)) else "")
  paste(
    "library(dragonfarm)",
    "",
    sprintf("run <- dragon_dataset(%s) |>", fmt(src)),
    sprintf("  %s |>", map_line),
    "  dragon_train(",
    sprintf("    model = %s,", fmt(cfg$model$id)),
    sprintf("    lora = %s,", lora_line),
    sprintf("    args = dragon_train_args(%s),", paste(args_parts, collapse = ", ")),
    sprintf("    hardware = %s,", hw_line),
    "    wait = TRUE",
    "  )",
    "",
    "dragon_evaluate(run)",
    "dragon_generate(run, \"Your prompt here\")",
    sep = "\n"
  )
}
