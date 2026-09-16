#' Multi-turn conversations as training data
#'
#' [dragon_map()] builds one user turn and one assistant turn per row. When
#' the examples are whole conversations, chat transcripts for instance, use
#' this instead. Each conversation is a list of messages with `role` and
#' `content`; it must contain at least one user turn and end with an
#' assistant turn, which is the turn the model learns to produce. Earlier
#' turns are context.
#'
#' @param x A list of conversations (each a list of messages), a path to a
#'   JSONL file with one `{"messages": [...]}` object per line, or a data
#'   frame with a `messages` list column.
#' @param name Display name. Defaults to the file name.
#' @return A `dragon_dataset` mapped as conversations, usable wherever a
#'   prompt and response dataset is: [dragon_train()], [dragon_bundle()],
#'   [dragon_step_train()].
#' @export
#' @examples
#' convs <- list(
#'   list(
#'     list(role = "system", content = "You are a support agent."),
#'     list(role = "user", content = "My thermostat drops off Wi-Fi."),
#'     list(role = "assistant", content = "Which router do you use?"),
#'     list(role = "user", content = "An Eero."),
#'     list(role = "assistant",
#'          content = "Eero often band-steers 2.4 GHz devices. Make a 2.4 GHz-only network.")
#'   )
#' )
#' ds <- dragon_conversations(convs)
#' dragon_preview(ds)
dragon_conversations <- function(x, name = NULL) {
  source <- "conversations"
  if (is.character(x) && length(x) == 1) {
    if (!file.exists(x)) cli::cli_abort("File {.path {x}} does not exist.")
    rows <- read_jsonl(x)
    convs <- lapply(rows, function(r) r$messages)
    source <- x
    name <- name %||% basename(x)
  } else if (is.data.frame(x)) {
    if (!"messages" %in% names(x)) cli::cli_abort("The data frame needs a {.field messages} list column.")
    convs <- as.list(x$messages)
    source <- "data.frame"
  } else if (is.list(x)) {
    convs <- x
  } else {
    cli::cli_abort("{.arg x} must be a list of conversations, a JSONL path, or a data frame.")
  }
  convs <- lapply(seq_along(convs), function(i) validate_conversation(convs[[i]], i))
  if (!length(convs)) cli::cli_abort("No conversations found.")
  df <- data.frame(
    turns = vapply(convs, length, integer(1)),
    last_user = vapply(convs, function(m) last_role_content(m, "user"), character(1)),
    last_assistant = vapply(convs, function(m) m[[length(m)]]$content, character(1)),
    stringsAsFactors = FALSE
  )
  df$messages <- I(convs)
  ds <- new_dataset(df, source = source, name = name %||% "conversations")
  ds$mapping <- list(kind = "conversations")
  ds
}

validate_conversation <- function(msgs, i) {
  if (!is.list(msgs) || !length(msgs)) cli::cli_abort("Conversation {i} is empty.")
  roles <- vapply(msgs, function(m) as.character(m$role %||% NA_character_), character(1))
  contents <- vapply(msgs, function(m) as.character(m$content %||% NA_character_), character(1))
  if (any(is.na(roles)) || any(is.na(contents))) cli::cli_abort("Conversation {i} has a message without a role or content.")
  bad <- setdiff(unique(roles), c("system", "user", "assistant"))
  if (length(bad)) cli::cli_abort("Conversation {i} uses unknown role{?s} {.val {bad}}.")
  if (!"user" %in% roles) cli::cli_abort("Conversation {i} has no user turn.")
  if (roles[length(roles)] != "assistant") cli::cli_abort("Conversation {i} must end with an assistant turn (that is what the model learns).")
  lapply(seq_along(msgs), function(j) list(role = roles[j], content = contents[j]))
}

last_role_content <- function(msgs, role) {
  hits <- Filter(function(m) identical(m$role, role), msgs)
  if (length(hits)) hits[[length(hits)]]$content else NA_character_
}

# Rows for the "conversations" kind: the messages as they are.
dataset_conversations <- function(dataset, idx = NULL) {
  check_dataset(dataset, mapped = TRUE, kind = "conversations")
  convs <- dataset$data$messages
  if (!is.null(idx)) convs <- convs[idx]
  lapply(convs, function(m) list(messages = m))
}

# Write conversations as a JSONL file that dragon_conversations() reads back.
write_conversations <- function(convs, path) {
  write_jsonl(lapply(convs, function(m) list(messages = m)), path)
}
