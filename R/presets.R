#' Recommended small models
#'
#' A table of small instruction-tuned models that work well with LoRA on a
#' single consumer GPU or, for the smallest, a CPU. Any Hugging Face causal
#' language model id can be passed to [dragon_train()]; these are just good
#' starting points.
#'
#' @return A data frame with columns `id`, `params`, `license`, `gated`,
#'   `rank`, `min_vram_gb`, and `notes`.
#' @export
#' @examples
#' dragon_presets()
dragon_presets <- function() {
  data.frame(
    id = c(
      "HuggingFaceTB/SmolLM2-135M-Instruct",
      "HuggingFaceTB/SmolLM2-360M-Instruct",
      "Qwen/Qwen2.5-0.5B-Instruct",
      "google/gemma-3-1b-it",
      "meta-llama/Llama-3.2-1B-Instruct",
      "Qwen/Qwen2.5-1.5B-Instruct",
      "HuggingFaceTB/SmolLM2-1.7B-Instruct"
    ),
    params = c("135M", "360M", "0.5B", "1B", "1.2B", "1.5B", "1.7B"),
    license = c("Apache 2.0", "Apache 2.0", "Apache 2.0", "Gemma", "Llama 3.2", "Apache 2.0", "Apache 2.0"),
    gated = c(FALSE, FALSE, FALSE, TRUE, TRUE, FALSE, FALSE),
    rank = c(8L, 8L, 16L, 16L, 16L, 16L, 16L),
    min_vram_gb = c(2, 3, 3, 5, 5, 7, 8),
    notes = c(
      "Fastest. Trains on a CPU in minutes. Used by the package tests.",
      "Good laptop default.",
      "App default. Strong for its size.",
      "Needs a Hugging Face token.",
      "Needs a Hugging Face token.",
      "Top of the comfortable range on an 8 GB card.",
      "Largest preset. Turn on gradient checkpointing on 8 GB cards."
    ),
    stringsAsFactors = FALSE
  )
}

preset_for <- function(model) {
  p <- dragon_presets()
  hit <- p[p$id == model, , drop = FALSE]
  if (nrow(hit)) hit else NULL
}
