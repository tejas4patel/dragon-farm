math_df <- function(n = 30) {
  a <- seq_len(n)
  data.frame(question = sprintf("What is %d + %d?", a, a), answer = as.character(2 * a),
             topic = "addition", stringsAsFactors = FALSE)
}
prompts_ds <- function(n = 30) {
  dragon_map_prompts(dragon_dataset(math_df(n)), prompt = "question", reference = "answer")
}

test_that("dragon_map_prompts maps prompt, reference, and keeps other columns as fields", {
  ds <- prompts_ds()
  expect_equal(dragonfarm:::mapping_kind(ds), "prompts")
  rows <- dragonfarm:::dataset_prompts(ds, 1:2)
  expect_equal(rows[[1]]$prompt[[1]]$content, "What is 1 + 1?")
  expect_equal(rows[[1]]$reference, "2")
  expect_equal(rows[[2]]$fields$topic, "addition")
  expect_equal(rows[[2]]$fields$answer, "4")

  plain <- dragon_map_prompts(dragon_dataset(math_df()), prompt = "Q: {question}", system = "Answer with a number.")
  r <- dragonfarm:::dataset_prompts(plain, 1)[[1]]
  expect_null(r$reference)
  expect_equal(vapply(r$prompt, `[[`, character(1), "role"), c("system", "user"))
  expect_equal(r$prompt[[2]]$content, "Q: What is 1 + 1?")

  msgs <- suppressMessages(dragon_preview(ds, n = 1))[[1]]$messages
  expect_equal(vapply(msgs, `[[`, character(1), "role"), c("user", "reference"))
  expect_error(dragon_map_prompts(dragon_dataset(math_df()), prompt = "nope"), "not found")
})

test_that("prompt rows are written in the prompts format", {
  files <- dragonfarm:::write_dataset_files(prompts_ds(40), dir <- tempfile("run-"))
  expect_equal(files$format, "prompts")
  train <- dragonfarm:::read_jsonl(file.path(dir, "data", "train.jsonl"))
  expect_setequal(names(train[[1]]), c("prompt", "reference", "fields"))
  expect_equal(train[[1]]$prompt[[1]]$role, "user")
  # a JSON null reference survives the round trip as NULL
  plain <- dragon_map_prompts(dragon_dataset(math_df(40)), prompt = "question")
  files2 <- dragonfarm:::write_dataset_files(plain, dir2 <- tempfile("run-"))
  expect_null(dragonfarm:::read_jsonl(file.path(dir2, "data", "train.jsonl"))[[1]]$reference)
})

test_that("dragon_reward validates each type and prints", {
  expect_s3_class(dragon_reward("exact"), "dragon_reward")
  r <- dragon_reward("regex", pattern = "^T-\\d{4}", weight = 2, name = "ticket")
  expect_equal(r$pattern, "^T-\\d{4}")
  expect_equal(r$weight, 2)
  expect_false(r$case_sensitive)
  expect_equal(dragon_reward("json", keys = c("id", "status"))$keys, list("id", "status"))
  expect_equal(dragon_reward("length", max_chars = 200)$max_chars, 200)
  expect_equal(dragon_reward("keyword", words = c("a", "b"), mode = "all")$mode, "all")
  cmd <- dragon_reward("command", command = c("pytest", "-q"))
  expect_equal(cmd$command, list("pytest", "-q"))
  expect_equal(cmd$input, "stdin")
  expect_equal(cmd$score_from, "exit_code")
  expect_equal(cmd$timeout, 30)
  expect_null(cmd$min)
  out <- dragon_reward("command", command = "check.sh", input = "file", score_from = "stdout",
                       min_score = -5, max_score = 5, timeout = 5)
  expect_equal(out$input, "file")
  expect_equal(out$min, -5)
  expect_equal(out$max, 5)
  expect_equal(out$timeout, 5)
  expect_error(dragon_reward("regex"), "pattern")
  expect_error(dragon_reward("length"), "min_chars")
  expect_error(dragon_reward("keyword"), "words")
  expect_error(dragon_reward("command"), "command")
  expect_error(dragon_reward("custom", file = tempfile()), "does not exist")
  expect_error(dragon_reward("exact", weight = -1), "between")
  expect_error(dragon_reward("nope"))
  msgs <- testthat::capture_messages(print(r))
  expect_true(any(grepl("ticket", msgs)))
  specs <- dragonfarm:::as_reward_specs(list(dragon_reward("exact"), r))
  expect_length(specs, 2)
  expect_false(inherits(specs[[1]], "dragon_reward"))
  expect_error(dragonfarm:::as_reward_specs(list("exact")), "dragon_reward")
  expect_error(dragonfarm:::as_reward_specs(NULL), "dragon_reward")
})

test_that("a command reward reproduces as code, with defaults omitted", {
  minimal <- dragon_reward("command", command = c("pytest", "-q"))
  expect_equal(dragonfarm:::reward_code(minimal), 'dragon_reward("command", command = c("pytest", "-q"))')

  full <- dragon_reward("command", command = "check.sh", weight = 0.5, input = "file", score_from = "stdout",
                        min_score = -1, max_score = 9, timeout = 5)
  code <- dragonfarm:::reward_code(full)
  expect_match(code, 'command = "check.sh"', fixed = TRUE)
  expect_match(code, 'input = "file"', fixed = TRUE)
  expect_match(code, 'score_from = "stdout"', fixed = TRUE)
  expect_match(code, "min_score = -1", fixed = TRUE)
  expect_match(code, "max_score = 9", fixed = TRUE)
  expect_match(code, "timeout = 5", fixed = TRUE)
  parsed <- eval(parse(text = code)[[1]])
  expect_equal(parsed$command, full$command)
  expect_equal(parsed$min, full$min)
})

test_that("stages refuse prompt datasets and reinforce refuses the others", {
  runs <- tempfile("runs-")
  expect_error(dragon_train(prompts_ds(), "x/y", runs_dir = runs), "dragon_reinforce")
  expect_error(dragon_prefer(prompts_ds(), "x/y", runs_dir = runs), "dragon_map_pairs")
  expect_error(dragon_reinforce(dragon_map(dragon_dataset(toy_df()), "subject", "reply"), "x/y",
                                rewards = dragon_reward("exact"), runs_dir = runs), "dragon_map_prompts")
  expect_error(dragon_reinforce(prompts_ds(), "x/y", rewards = dragon_reward("exact"), group_size = 1, runs_dir = runs), "between")
  expect_error(dragon_reinforce(prompts_ds(), "x/y", rewards = dragon_reward("exact"), temperature = 0, runs_dir = runs), "between")
})

test_that("a bundled RL run records rewards, copies custom reward files, and reproduces as code", {
  runs <- tempfile("runs-")
  py <- tempfile("myreward-", fileext = ".py")
  writeLines(c("def reward(prompt, completion, reference, row):", "    return 1.0 if 'the' in completion else 0.0"), py)
  rewards <- list(dragon_reward("numeric"), dragon_reward("length", max_chars = 120, weight = 0.5),
                  dragon_reward("custom", file = py), dragon_reward("keyword", words = c("sum", "total")))
  run <- suppressMessages(dragon_bundle(prompts_ds(40), "HuggingFaceTB/SmolLM2-135M-Instruct", runs_dir = runs,
                                        rewards = rewards, group_size = 6, beta = 0.05, temperature = 0.9, max_new_tokens = 64))
  cfg <- dragonfarm:::run_config(run)
  expect_equal(cfg$stage, "reinforce")
  expect_equal(cfg$data$format, "prompts")
  expect_equal(cfg$reinforce$group_size, 6)
  expect_equal(cfg$reinforce$beta, 0.05)
  expect_equal(cfg$reinforce$temperature, 0.9)
  expect_equal(cfg$reinforce$max_new_tokens, 64)
  expect_length(cfg$reinforce$rewards, 4)
  expect_equal(cfg$reinforce$rewards[[3]]$type, "custom")
  expect_equal(cfg$reinforce$rewards[[3]]$file, paste0("rewards/", basename(py)))
  expect_true(file.exists(file.path(run$dir, "rewards", basename(py))))
  expect_match(run$id, "-grpo$")
  expect_null(cfg$prefer)

  files <- zip::zip_list(dragonfarm:::bundle_paths(run)$zip)$filename
  expect_true(paste0("run/rewards/", basename(py)) %in% files)

  df <- dragon_runs(runs)
  expect_equal(df$stage, "reinforce")
  expect_equal(df$method, "grpo")

  code <- dragon_code(run)
  expect_match(code, "dragon_map_prompts(", fixed = TRUE)
  expect_match(code, "dragon_reinforce(", fixed = TRUE)
  expect_match(code, 'dragon_reward("numeric")', fixed = TRUE)
  expect_match(code, 'dragon_reward("length", weight = 0.5, max_chars = 120)', fixed = TRUE)
  expect_match(code, 'words = c("sum", "total")', fixed = TRUE)
  expect_match(code, "group_size = 6", fixed = TRUE)
  expect_match(code, "beta = 0.05", fixed = TRUE)

  expect_error(suppressMessages(dragon_bundle(prompts_ds(40), "HuggingFaceTB/SmolLM2-135M-Instruct", runs_dir = runs)),
               "rewards")
})

test_that("progress frames and comparisons carry reward columns", {
  pr <- dragonfarm:::dragon_progress_empty()
  expect_true(all(c("reward", "reward_std", "kl", "completion_len") %in% names(pr)))
  dir <- copy_fixture_run()
  st <- dragonfarm:::read_json(file.path(dir, "status.json"))
  st$reward_mean <- 0.42
  dragonfarm:::write_json(st, file.path(dir, "status.json"))
  cmp <- dragon_compare(dragon_run(dir))
  expect_equal(cmp$reward, 0.42)
})

test_that("the mapping module handles RL prompts", {
  state <- shiny::reactiveValues(dataset = dragon_dataset(math_df(5)), mapped = NULL)
  shiny::testServer(dragonfarm:::mod_mapping_server, args = list(state = state, nav_to = function(p) NULL), {
    session$setInputs(mode = "prompts", prompt_tpl = "question", reference_tpl = "answer", system_tpl = "")
    m <- mapped()
    expect_s3_class(m, "dragon_dataset")
    expect_equal(dragonfarm:::mapping_kind(m), "prompts")
    expect_equal(m$mapping$reference, "{`answer`}")
    session$setInputs(reference_tpl = "")
    expect_null(mapped()$mapping$reference)
  })
})

test_that("the train module launches an RL bundle with the chosen rewards", {
  runs <- tempfile("runs-")
  withr::local_options(dragonfarm.runs_dir = runs)
  ds <- dragon_dataset(math_df(30))
  state <- shiny::reactiveValues(
    dataset = ds, mapped = dragon_map_prompts(ds, "question", reference = "answer"),
    model = list(id = "HuggingFaceTB/SmolLM2-135M-Instruct", trust_remote_code = FALSE),
    run = NULL, hardware = NULL, cloud = NULL
  )
  shiny::testServer(dragonfarm:::mod_train_server, args = list(state = state, nav_to = function(p) NULL, runs_dir = runs), {
    session$setInputs(epochs = 1, learning_rate = 1e-5, rank = 8, max_seq_len = 256, batch_size = 2, grad_accum = 1,
                      alpha = 16, dropout = 0.05, max_steps = NA, eval_frac = 0.1, save_steps = 10, seed = 1,
                      device = "auto", dtype = "auto", grad_ckpt = FALSE, name = "", provider = "colab", base_run = "",
                      reward_types = c("numeric", "length", "regex"), reward_regex = "^\\d+$", reward_max_chars = 50,
                      reward_words = "", group_size = 4, kl_beta = 0.04, rl_temperature = 1, rl_max_new_tokens = 32)
    expect_equal(kind(), "prompts")
    session$setInputs(bundle = 1)
    expect_s3_class(state$run, "dragon_run")
    cfg <- dragonfarm:::run_config(state$run)
    expect_equal(cfg$stage, "reinforce")
    types <- vapply(cfg$reinforce$rewards, `[[`, character(1), "type")
    expect_setequal(types, c("numeric", "length", "regex"))
    expect_equal(cfg$reinforce$group_size, 4)
  })
})
