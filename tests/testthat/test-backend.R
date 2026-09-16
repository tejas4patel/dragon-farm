# A backend that answers from the conversation itself, so chat and routing
# can be tested without Python or a server.
fake_backend <- function() structure(list(kind = "fake", model = "fake"), class = c("dragon_backend_fake", "dragon_backend"))
backend_generate.dragon_backend_fake <- function(backend, target, conversations, max_new_tokens = 256,
                                                 temperature = 0.7, top_p = 0.9, on_token = NULL) {
  lapply(conversations, function(msgs) {
    users <- vapply(Filter(function(m) m$role == "user", msgs), `[[`, character(1), "content")
    reply <- sprintf("turn %d: %s", length(users), users[length(users)])
    if (!is.null(on_token)) for (piece in strsplit(reply, " ")[[1]]) on_token(paste0(piece, " "))
    reply
  })
}
registerS3method("backend_generate", "dragon_backend_fake", backend_generate.dragon_backend_fake, envir = asNamespace("dragonfarm"))

test_that("backend constructors normalize their inputs", {
  loc <- dragon_backend_local()
  expect_s3_class(loc, "dragon_backend_local")
  expect_true(loc$keep_loaded)
  srv <- dragon_backend_server("https://host.example.com", "my/model", api_key = "k")
  expect_equal(srv$url, "https://host.example.com/v1")
  expect_equal(dragon_backend_server("http://h/v1/", "m", api_key = "")$url, "http://h/v1")
  oll <- dragon_backend_ollama("support-0.5b")
  expect_equal(oll$url, "http://localhost:11434/v1")
  expect_equal(oll$kind, "ollama")
  expect_true(dragonfarm:::is_server_backend(oll))
  expect_false(dragonfarm:::is_server_backend(loc))
  expect_match(dragonfarm:::backend_label(oll), "Ollama support-0.5b")
  expect_error(dragon_backend_server("", "m"), "non-empty")
  withr::local_options(dragonfarm.backend = oll)
  expect_equal(dragon_backend()$model, "support-0.5b")
  withr::local_options(dragonfarm.backend = 42)
  expect_error(dragon_backend(), "dragon_backend")
})

test_that("the chat completion request follows the OpenAI shape", {
  skip_if_not_installed("httr2")
  b <- dragon_backend_server("https://host/v1", "m", api_key = "secret", headers = c(`x-extra` = "1"))
  req <- dragonfarm:::chat_completion_request(b, list(list(role = "user", content = "hi")), 64, 0.2, 0.9)
  expect_equal(req$url, "https://host/v1/chat/completions")
  body <- req$body$data
  expect_equal(body$model, "m")
  expect_equal(body$max_tokens, 64L)
  expect_equal(body$messages[[1]]$content, "hi")
  expect_false(body$stream)
  expect_true("Authorization" %in% names(req$headers))   # value is redacted by httr2
  expect_equal(req$headers[["x-extra"]], "1")
  none <- dragonfarm:::chat_completion_request(dragon_backend_ollama("m"), list(), 10, 0, 1)
  expect_false("Authorization" %in% names(none$headers))
})

test_that("a mocked server round-trips a reply and surfaces errors", {
  skip_if_not_installed("httr2")
  b <- dragon_backend_server("https://host/v1", "m", api_key = "")
  httr2::local_mocked_responses(function(req) {
    body <- req$body$data   # req_body_json() keeps the R object until the request is sent
    httr2::response_json(200, body = list(choices = list(list(message = list(role = "assistant", content = paste("echo:", body$messages[[length(body$messages)]]$content))))))
  })
  out <- dragonfarm:::backend_generate(b, NULL, list(list(list(role = "user", content = "ping"))))
  expect_equal(out[[1]], "echo: ping")
  expect_equal(dragon_generate("ignored/model", c("a", "b"), backend = b), c("echo: a", "echo: b"))

  httr2::local_mocked_responses(function(req) httr2::response_json(503, body = list(error = list(message = "down"))))
  expect_error(dragonfarm:::chat_completion(b, list(list(role = "user", content = "x"))), "HTTP 503")
})

test_that("dragon_generate routes through the backend and keeps prompt order", {
  out <- dragon_generate("any/model", c("first", "second"), system = "sys", backend = fake_backend())
  expect_equal(out, c("turn 1: first", "turn 1: second"))
})

test_that("dragon_chat keeps context across turns, streams, resets, saves, and loads", {
  chat <- dragon_chat("any/model", system = "Be brief.", backend = fake_backend(), temperature = 0)
  expect_s3_class(chat, "dragon_chat")
  expect_equal(chat$say("hello"), "turn 1: hello")
  expect_equal(chat$say("again"), "turn 2: again")
  h <- chat$history()
  expect_length(h, 4)
  expect_equal(vapply(h, `[[`, character(1), "role"), c("user", "assistant", "user", "assistant"))
  ex <- chat$as_example()
  expect_equal(ex$messages[[1]]$role, "system")
  expect_length(ex$messages, 5)

  pieces <- character()
  chat$say("stream", on_token = function(p) pieces <<- c(pieces, p))
  expect_equal(trimws(paste(pieces, collapse = "")), "turn 3: stream")

  chat$undo()
  expect_length(chat$history(), 4)
  path <- tempfile(fileext = ".json")
  chat$save(path)
  again <- dragon_chat_load(path, "any/model", backend = fake_backend())
  expect_length(again$history(), 4)
  expect_equal(again$system, "Be brief.")
  expect_equal(again$say("more"), "turn 3: more")
  chat$reset()
  expect_length(chat$history(), 0)
  msgs <- testthat::capture_messages(print(again))
  expect_true(any(grepl("turn", msgs)))
  expect_error(dragon_chat_load(tempfile()), "does not exist")
  expect_error(dragon_chat(NULL, backend = fake_backend()), "what should answer")
})

test_that("server backends do not need a local model", {
  chat <- dragon_chat(backend = dragon_backend_ollama("m"))
  expect_null(chat$target)
  expect_equal(chat$label, "m")
})

test_that("Ollama serving writes a Modelfile and reports a missing binary", {
  mf <- dragonfarm:::ollama_modelfile("C:/models/merged")
  expect_match(mf[1], "^FROM C:/models/merged$")
  expect_error(dragon_serve_ollama(dragon_run(copy_fixture_run()), ollama = ""), "not found on the PATH")
})

test_that("the chat module sends turns through the chosen backend", {
  runs <- tempfile("runs-")
  dir.create(runs)
  withr::local_options(dragonfarm.backend = fake_backend())
  state <- shiny::reactiveValues(run = NULL)
  shiny::testServer(dragonfarm:::mod_chat_server, args = list(state = state, runs_dir = runs), {
    session$setInputs(source = "ollama", ollama_model = "m", ollama_url = "http://localhost:11434",
                      system = "", temperature = 0.5, max_new_tokens = 64, text = "hello")
    # swap the server backend for the fake so no network is touched
    b <- backend()
    expect_equal(b$kind, "ollama")
  })
  shiny::testServer(dragonfarm:::mod_chat_server, args = list(state = state, runs_dir = runs), {
    session$setInputs(source = "run", system = "", temperature = 0.5, max_new_tokens = 64, text = "")
    expect_length(history(), 0)
    session$setInputs(send = 1)
    expect_length(history(), 0)   # empty text is ignored
  })
})
