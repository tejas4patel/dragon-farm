# Inference backends: where a model answers from. Training machines are
# rarely the right inference machines, so generation is routed through a
# backend object: the local worker (a Python process that keeps models
# loaded), or any OpenAI-compatible chat endpoint (vLLM, llama.cpp, Ollama,
# LM Studio, hosted services).

#' Inference backends
#'
#' Every function that generates text, [dragon_generate()], [dragon_chat()],
#' the judge, teacher, and synthesis helpers, takes a `backend`. The default
#' is the local worker; set `options(dragonfarm.backend = ...)` to change it
#' for a session.
#'
#' * `dragon_backend_local()`: a Python worker on this machine that keeps
#'   the last two models loaded, so repeated calls pay the model load once.
#'   `keep_loaded = FALSE` stops it after every call.
#' * `dragon_backend_server()`: any server that speaks the OpenAI chat
#'   completions protocol. `url` is the base that ends in `/v1`. The model
#'   must already be available on that server; see [dragon_serve_ollama()]
#'   for the local case.
#' * `dragon_backend_ollama()`: a server backend for a model registered
#'   with Ollama on this machine.
#' * `dragon_backend()`: the session default.
#'
#' @param keep_loaded Keep the worker and its models alive between calls.
#' @param device,dtype Device and precision for the local worker. See
#'   [dragon_hardware()].
#' @param url Base URL of the server, ending in `/v1`.
#' @param model Model name as the server knows it.
#' @param api_key Bearer token, if the server needs one. Defaults to
#'   `DRAGONFARM_API_KEY`, then `OPENAI_API_KEY`.
#' @param headers Extra HTTP headers as a named character vector.
#' @return A `dragon_backend` object.
#' @name dragon_backend
#' @examples
#' \dontrun{
#' options(dragonfarm.backend = dragon_backend_ollama("support-0.5b"))
#' dragon_generate(run, "My thermostat keeps dropping off Wi-Fi.")
#'
#' vllm <- dragon_backend_server("https://my-pod.example.com/v1", model = "tejas/support-0.5b")
#' dragon_generate(run, "Hello", backend = vllm)
#' }
NULL

#' @rdname dragon_backend
#' @export
dragon_backend_local <- function(keep_loaded = TRUE, device = "auto", dtype = "auto") {
  structure(list(kind = "local", keep_loaded = isTRUE(keep_loaded), device = device, dtype = dtype),
            class = c("dragon_backend_local", "dragon_backend"))
}

#' @rdname dragon_backend
#' @export
dragon_backend_server <- function(url, model, api_key = NULL, headers = NULL) {
  check_string(url, "url")
  check_string(model, "model")
  url <- sub("/+$", "", url)
  if (!grepl("/v1$", url)) url <- paste0(url, "/v1")
  api_key <- api_key %||% Sys.getenv("DRAGONFARM_API_KEY", unset = Sys.getenv("OPENAI_API_KEY"))
  structure(list(kind = "server", url = url, model = model, api_key = api_key, headers = headers),
            class = c("dragon_backend_server", "dragon_backend"))
}

#' @rdname dragon_backend
#' @export
dragon_backend_ollama <- function(model, url = "http://localhost:11434") {
  b <- dragon_backend_server(url, model, api_key = "")
  b$kind <- "ollama"
  b
}

#' @rdname dragon_backend
#' @export
dragon_backend <- function() {
  b <- getOption("dragonfarm.backend")
  if (is.null(b)) return(dragon_backend_local())
  if (!inherits(b, "dragon_backend")) cli::cli_abort("{.code options(dragonfarm.backend)} must be a {.cls dragon_backend}.")
  b
}

#' @export
print.dragon_backend <- function(x, ...) {
  cli::cli_text("{.cls dragon_backend} {backend_label(x)}")
  invisible(x)
}

backend_label <- function(b) {
  switch(b$kind,
    local = paste0("local worker (", if (b$keep_loaded) "kept loaded" else "one-shot", ")"),
    ollama = paste0("Ollama ", b$model, " at ", b$url),
    paste0(b$model, " at ", b$url)
  )
}

is_server_backend <- function(b) inherits(b, "dragon_backend_server")

# Generate replies for a list of conversations (each a list of messages).
# `target` comes from resolve_target() and is ignored by server backends.
# `on_token` streams the first conversation's reply piece by piece.
backend_generate <- function(backend, target, conversations, max_new_tokens = 256, temperature = 0.7,
                             top_p = 0.9, on_token = NULL) {
  UseMethod("backend_generate")
}

#' @export
backend_generate.dragon_backend_local <- function(backend, target, conversations, max_new_tokens = 256,
                                                  temperature = 0.7, top_p = 0.9, on_token = NULL) {
  if (is.null(target)) cli::cli_abort("The local backend needs a model to load: pass a run, adapter, or model id.")
  req <- list(
    op = "generate",
    model = target$model,
    adapter = target$adapter,
    base_adapters = as.list(target$base_adapters %||% character()),
    trust_remote_code = isTRUE(target$trust_remote_code),
    device = backend$device, dtype = backend$dtype,
    conversations = conversations,
    max_new_tokens = as.integer(max_new_tokens), temperature = temperature, top_p = top_p,
    stream = !is.null(on_token)
  )
  worker_start(backend)
  on.exit(if (!backend$keep_loaded) dragon_worker_stop(), add = TRUE)
  res <- worker_request(req, on_token = on_token)
  if (!is.null(on_token)) list(res$output) else res$outputs
}

#' @export
backend_generate.dragon_backend_server <- function(backend, target, conversations, max_new_tokens = 256,
                                                   temperature = 0.7, top_p = 0.9, on_token = NULL) {
  lapply(seq_along(conversations), function(i) {
    chat_completion(backend, conversations[[i]], max_new_tokens = max_new_tokens, temperature = temperature,
                    top_p = top_p, on_token = if (i == 1) on_token)
  })
}

# Local worker ---------------------------------------------------------------

worker_start <- function(backend = dragon_backend_local()) {
  if (worker_alive()) return(invisible(the$worker))
  py <- dragon_python(quiet = TRUE)
  log <- file.path(tempdir(), "dragonfarm-worker.log")
  p <- processx::process$new(
    py, c("-u", "-m", "dragonfarm.worker"),
    stdin = "|", stdout = "|", stderr = log,
    env = python_env(), cleanup = TRUE, windows_hide_window = TRUE
  )
  the$worker <- p
  the$worker_log <- log
  # Wait for the ready line so the first request does not race the import.
  started <- Sys.time()
  repeat {
    p$poll_io(500)
    lines <- p$read_output_lines()
    if (length(lines)) break
    if (!p$is_alive()) cli::cli_abort(c("The inference worker exited during startup.", "i" = paste(tail_lines(log, 15), collapse = "\n")))
    if (as.numeric(difftime(Sys.time(), started, units = "secs")) > 600) cli::cli_abort("The inference worker did not start within 10 minutes.")
  }
  invisible(p)
}

worker_alive <- function() {
  !is.null(the$worker) && tryCatch(the$worker$is_alive(), error = function(e) FALSE)
}

#' Stop the local inference worker
#'
#' The local backend keeps a Python process alive with the last models
#' loaded. Call this to free the memory (GPU included). It restarts on the
#' next generation call.
#'
#' @return `TRUE` invisibly.
#' @export
dragon_worker_stop <- function() {
  if (worker_alive()) {
    try(the$worker$write_input('{"op": "quit"}\n'), silent = TRUE)
    try(the$worker$wait(timeout = 5000), silent = TRUE)
    if (the$worker$is_alive()) try(the$worker$kill(), silent = TRUE)
  }
  the$worker <- NULL
  invisible(TRUE)
}

worker_request <- function(req, on_token = NULL, timeout = 3600) {
  p <- the$worker
  p$write_input(paste0(jsonlite::toJSON(req, auto_unbox = TRUE, null = "null", digits = NA), "\n"))
  started <- Sys.time()
  repeat {
    p$poll_io(1000)
    for (line in p$read_output_lines()) {
      obj <- tryCatch(jsonlite::fromJSON(line, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(obj)) next
      if (!isTRUE(obj$ok)) {
        cli::cli_abort(c("The inference worker reported an error.", "x" = "{obj$error %||% 'unknown'}"))
      }
      if (!is.null(obj$token)) {
        if (!is.null(on_token)) on_token(obj$token)
        next
      }
      return(obj)
    }
    if (!p$is_alive()) {
      the$worker <- NULL
      cli::cli_abort(c("The inference worker died.", "i" = paste(tail_lines(the$worker_log, 15), collapse = "\n")))
    }
    if (as.numeric(difftime(Sys.time(), started, units = "secs")) > timeout) {
      cli::cli_abort("The inference worker did not answer within {timeout} seconds.")
    }
  }
}

# OpenAI-compatible servers --------------------------------------------------

chat_completion_request <- function(backend, messages, max_new_tokens, temperature, top_p, stream = FALSE) {
  body <- list(
    model = backend$model, messages = messages,
    max_tokens = as.integer(max_new_tokens), temperature = temperature, top_p = top_p, stream = stream
  )
  req <- httr2::request(paste0(backend$url, "/chat/completions")) |>
    httr2::req_headers(`content-type` = "application/json") |>
    httr2::req_body_json(body, auto_unbox = TRUE) |>
    httr2::req_error(is_error = function(resp) FALSE)
  if (!is.null(backend$api_key) && nzchar(backend$api_key)) {
    req <- httr2::req_headers(req, Authorization = paste("Bearer", backend$api_key), .redact = "Authorization")
  }
  if (length(backend$headers)) req <- httr2::req_headers(req, !!!as.list(backend$headers))
  req
}

chat_completion <- function(backend, messages, max_new_tokens = 256, temperature = 0.7, top_p = 0.9, on_token = NULL) {
  rlang::check_installed("httr2", reason = "to call an inference server.")
  req <- chat_completion_request(backend, messages, max_new_tokens, temperature, top_p, stream = !is.null(on_token))
  if (is.null(on_token)) {
    resp <- httr2::req_perform(req)
    body <- tryCatch(httr2::resp_body_json(resp, simplifyVector = FALSE), error = function(e) NULL)
    if (httr2::resp_status(resp) >= 400 || is.null(body)) {
      cli::cli_abort(c("The server at {.url {backend$url}} answered HTTP {httr2::resp_status(resp)}.",
                       "x" = "{body$error$message %||% body$error %||% 'no detail'}"))
    }
    return(as.character(body$choices[[1]]$message$content %||% ""))
  }
  con <- httr2::req_perform_connection(req)
  on.exit(close(con), add = TRUE)
  pieces <- character()
  repeat {
    ev <- httr2::resp_stream_sse(con)
    if (is.null(ev)) break
    if (identical(trimws(ev$data), "[DONE]")) break
    d <- tryCatch(jsonlite::fromJSON(ev$data, simplifyVector = FALSE), error = function(e) NULL)
    piece <- d$choices[[1]]$delta$content
    if (!is.null(piece) && nzchar(piece)) {
      pieces <- c(pieces, piece)
      on_token(piece)
    }
  }
  paste(pieces, collapse = "")
}
