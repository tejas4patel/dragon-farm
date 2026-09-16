#' Map columns for preference optimization
#'
#' For [dragon_prefer()]. Each row holds one prompt and two candidate replies:
#' the one you prefer and the one you want the model to move away from. As in
#' [dragon_map()], each argument is a column name or a [glue::glue()] template
#' combining several columns.
#'
#' @inheritParams dragon_map
#' @param chosen Column name or template for the preferred reply.
#' @param rejected Column name or template for the reply to move away from.
#' @return The dataset with the mapping attached.
#' @export
#' @examples
#' df <- data.frame(
#'   q = c("What is 2 + 2?", "Capital of France?"),
#'   good = c("4", "Paris"),
#'   bad = c("5", "Lyon")
#' )
#' ds <- dragon_map_pairs(dragon_dataset(df), prompt = "q", chosen = "good", rejected = "bad")
#' dragon_preview(ds, n = 1)
dragon_map_pairs <- function(dataset, prompt, chosen, rejected, system = NULL) {
  check_dataset(dataset)
  cols <- names(dataset$data)
  dataset$mapping <- list(
    kind = "pairs",
    prompt = as_template(prompt, cols, "prompt"),
    chosen = as_template(chosen, cols, "chosen"),
    rejected = as_template(rejected, cols, "rejected"),
    system = if (!is.null(system)) as_template(system, cols, "system", allow_constant = TRUE)
  )
  dataset
}

# "messages" for prompt/response data, "pairs" for preference data, NULL when unmapped.
mapping_kind <- function(dataset) {
  if (is.null(dataset$mapping)) return(NULL)
  dataset$mapping$kind %||% "messages"
}

# Rows of the "pairs" format: the prompt as chat messages plus both replies.
dataset_pairs <- function(dataset, idx = NULL) {
  check_dataset(dataset, mapped = TRUE, kind = "pairs")
  d <- dataset$data
  if (!is.null(idx)) d <- d[idx, , drop = FALSE]
  if (!nrow(d)) return(list())
  m <- dataset$mapping
  prompt <- render_template(m$prompt, d)
  chosen <- render_template(m$chosen, d)
  rejected <- render_template(m$rejected, d)
  system <- if (!is.null(m$system)) render_template(m$system, d)
  lapply(seq_len(nrow(d)), function(i) {
    msgs <- list()
    if (!is.null(system) && nzchar(trimws(system[i]))) {
      msgs[[length(msgs) + 1]] <- list(role = "system", content = system[i])
    }
    msgs[[length(msgs) + 1]] <- list(role = "user", content = prompt[i])
    list(prompt = msgs, chosen = chosen[i], rejected = rejected[i])
  })
}

# Rows of whichever kind the dataset is mapped as.
dataset_rows <- function(dataset, idx = NULL) {
  switch(mapping_kind(dataset) %||% "messages",
    pairs = dataset_pairs(dataset, idx),
    prompts = dataset_prompts(dataset, idx),
    conversations = dataset_conversations(dataset, idx),
    dataset_messages(dataset, idx)
  )
}

# A pairs row as chat turns for previews: prompt turns, then the two replies
# under their own roles.
pair_as_messages <- function(row) {
  list(messages = c(
    row$prompt,
    list(list(role = "chosen", content = row$chosen), list(role = "rejected", content = row$rejected))
  ))
}

# Rows of either kind as chat turns, for the console and app previews.
preview_rows <- function(dataset, idx = NULL) {
  rows <- dataset_rows(dataset, idx)
  switch(mapping_kind(dataset) %||% "messages",
    pairs = lapply(rows, pair_as_messages),
    prompts = lapply(rows, prompt_as_messages),
    rows
  )
}
