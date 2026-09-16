convo <- function(n_pairs = 1, system = NULL) {
  msgs <- if (!is.null(system)) list(list(role = "system", content = system)) else list()
  for (i in seq_len(n_pairs)) {
    msgs <- c(msgs, list(list(role = "user", content = paste("question", i)), list(role = "assistant", content = paste("answer", i))))
  }
  msgs
}

test_that("dragon_conversations validates and summarises conversations", {
  ds <- dragon_conversations(list(convo(1), convo(2, system = "Be brief.")))
  expect_s3_class(ds, "dragon_dataset")
  expect_equal(dragonfarm:::mapping_kind(ds), "conversations")
  expect_equal(nrow(ds$data), 2)
  expect_equal(ds$data$turns, c(2L, 5L))
  expect_equal(ds$data$last_user, c("question 1", "question 2"))
  rows <- dragonfarm:::dataset_rows(ds, 2)
  expect_equal(rows[[1]]$messages[[1]]$role, "system")
  expect_length(rows[[1]]$messages, 5)
  msgs <- testthat::capture_messages(print(ds))
  expect_true(any(grepl("conversation", msgs, ignore.case = TRUE)))
  pv <- suppressMessages(dragon_preview(ds, n = 1))
  expect_equal(pv[[1]]$messages[[2]]$role, "assistant")

  expect_error(dragon_conversations(list(list(list(role = "user", content = "q")))), "end with an assistant")
  expect_error(dragon_conversations(list(list(list(role = "assistant", content = "a")))), "no user turn")
  expect_error(dragon_conversations(list(list(list(role = "tool", content = "x"), list(role = "assistant", content = "a")))), "unknown role")
  expect_error(dragon_conversations(list()), "No conversations")
  expect_error(dragon_conversations(42), "must be a list")
  expect_error(dragon_conversations(tempfile()), "does not exist")
})

test_that("conversations round-trip through JSONL and train like prompt/response data", {
  convs <- lapply(1:30, function(i) convo(1 + i %% 3, system = if (i %% 2 == 0) "Be brief."))
  path <- tempfile(fileext = ".jsonl")
  dragonfarm:::write_conversations(convs, path)
  ds <- dragon_conversations(path)
  expect_equal(nrow(ds$data), 30)
  expect_equal(ds$source, path)

  files <- dragonfarm:::write_dataset_files(dragon_split(ds, 0.1, seed = 1), dir <- tempfile("run-"))
  expect_equal(files$format, "messages")           # same on-disk rows as dragon_map() data
  expect_equal(files$n_train + files$n_eval, 30)
  train <- dragonfarm:::read_jsonl(file.path(dir, "data", "train.jsonl"))
  expect_named(train[[1]], "messages")
  last <- train[[1]]$messages[[length(train[[1]]$messages)]]
  expect_equal(last$role, "assistant")

  run <- suppressMessages(dragon_bundle(ds, "HuggingFaceTB/SmolLM2-135M-Instruct", runs_dir = tempfile("runs-")))
  cfg <- dragonfarm:::run_config(run)
  expect_equal(cfg$stage, "sft")
  expect_equal(cfg$data$format, "messages")
  code <- dragon_code(run)
  expect_match(code, "dragon_conversations(", fixed = TRUE)
  expect_false(grepl("dragon_map(", code, fixed = TRUE))
  expect_error(dragon_prefer(ds, "x/y", runs_dir = tempfile()), "dragon_map_pairs")
  expect_s3_class(dragon_step_train(ds), "dragon_step")
})
