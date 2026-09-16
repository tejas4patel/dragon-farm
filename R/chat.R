#' Talk to a model, with memory of the conversation
#'
#' A conversation object that keeps the message history and sends all of it
#' on every turn, so the model has context. Works with any backend: the
#' local worker, Ollama, or a remote server. Transcripts use the same
#' message format as training data, so a good conversation can become an
#' example.
#'
#' @param x What answers: a `dragon_run`, adapter or model directory, or
#'   model id. Ignored by server backends, which serve a fixed model.
#' @param system Optional system prompt, kept at the top of every turn.
#' @param backend Where to run inference. See [dragon_backend].
#' @param max_new_tokens,temperature,top_p Generation settings.
#' @param base Talk to what the run started from instead of the run.
#' @return A `dragon_chat` object with methods:
#'   `$say(text, on_token = NULL)` sends a user turn and returns the reply
#'   (streaming pieces to `on_token` when the backend supports it);
#'   `$history()` returns the messages; `$reset()` clears them;
#'   `$save(path)` and `dragon_chat_load(path)` write and read a transcript;
#'   `$as_example()` returns the conversation as one training row.
#' @export
#' @examples
#' \dontrun{
#' chat <- dragon_chat(run, system = "You are a concise support agent.")
#' chat$say("My thermostat keeps dropping off Wi-Fi.")
#' chat$say("I tried that. What else?")   # the model sees the first exchange
#' chat$history()
#' chat$save("good-conversation.json")
#' }
dragon_chat <- function(x = NULL, system = NULL, backend = dragon_backend(), max_new_tokens = 256,
                        temperature = 0.7, top_p = 0.9, base = FALSE) {
  target <- if (is_server_backend(backend)) NULL else {
    if (is.null(x)) cli::cli_abort("Say what should answer: a run, adapter, model directory, or model id.")
    t <- resolve_target(x)
    if (isTRUE(base)) t$adapter <- NULL
    t
  }
  self <- new.env(parent = emptyenv())
  self$backend <- backend
  self$target <- target
  self$system <- system
  self$settings <- list(max_new_tokens = as.integer(max_new_tokens), temperature = temperature, top_p = top_p)
  self$messages <- list()
  self$label <- if (!is.null(target)) (if (!is.null(x) && inherits(x, "dragon_run")) x$id else basename(target$model)) else backend$model

  self$say <- function(text, on_token = NULL) {
    check_string(text, "text")
    turn <- c(self$messages, list(list(role = "user", content = text)))
    convo <- if (!is.null(self$system)) c(list(list(role = "system", content = self$system)), turn) else turn
    reply <- backend_generate(self$backend, self$target, list(convo),
                              max_new_tokens = self$settings$max_new_tokens,
                              temperature = self$settings$temperature, top_p = self$settings$top_p,
                              on_token = on_token)[[1]]
    self$messages <- c(turn, list(list(role = "assistant", content = reply)))
    invisible(reply)
  }
  self$history <- function() self$messages
  self$reset <- function() {
    self$messages <- list()
    invisible(self)
  }
  self$undo <- function() {
    n <- length(self$messages)
    if (n >= 2) self$messages <- self$messages[seq_len(n - 2)]
    invisible(self)
  }
  self$as_example <- function() {
    msgs <- self$messages
    if (!is.null(self$system)) msgs <- c(list(list(role = "system", content = self$system)), msgs)
    list(messages = msgs)
  }
  self$save <- function(path) {
    write_json(list(
      format = "dragonfarm-chat", version = 1L, saved_at = now_iso(), label = self$label,
      system = self$system, settings = self$settings, messages = self$messages
    ), path)
    invisible(path)
  }
  class(self) <- "dragon_chat"
  self
}

#' @rdname dragon_chat
#' @param path A transcript written by `$save()`.
#' @export
dragon_chat_load <- function(path, x = NULL, backend = dragon_backend()) {
  check_string(path, "path")
  if (!file.exists(path)) cli::cli_abort("Transcript {.path {path}} does not exist.")
  rec <- read_json(path)
  if (!identical(rec$format, "dragonfarm-chat")) cli::cli_abort("{.path {path}} is not a dragonfarm chat transcript.")
  chat <- dragon_chat(x, system = rec$system, backend = backend,
                      max_new_tokens = rec$settings$max_new_tokens %||% 256,
                      temperature = rec$settings$temperature %||% 0.7, top_p = rec$settings$top_p %||% 0.9)
  chat$messages <- rec$messages %||% list()
  chat
}

#' @export
print.dragon_chat <- function(x, ...) {
  n <- length(x$messages)
  cli::cli_text("{.cls dragon_chat} with {.strong {x$label}} via {backend_label(x$backend)}: {n %/% 2} turn{?s}")
  if (!is.null(x$system)) cli::cli_text("{.emph system:} {x$system}")
  tail <- if (n > 6) x$messages[(n - 5):n] else x$messages
  for (m in tail) {
    cli::cli_text("{.strong {m$role}:} {substr(gsub('\\\\s+', ' ', m$content), 1, 200)}")
  }
  invisible(x)
}

#' @export
`$.dragon_chat` <- function(x, name) get(name, envir = x, inherits = FALSE)
