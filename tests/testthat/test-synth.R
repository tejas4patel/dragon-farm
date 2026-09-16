# Deterministic stand-ins: a student whose samples vary in length, a teacher
# that answers well, and a judge that scores by length.
fake_student <- function(prompts) {
  k <- seq_along(prompts)
  vapply(k, function(i) paste0("reply to ", prompts[i], " ", strrep("word ", (i %% 4) + 1)), character(1))
}
fake_teacher <- function(prompts) paste("Teacher answer for", prompts)
length_judge <- function(prompts, schema = NULL) {
  vapply(prompts, function(p) {
    reply <- sub(".*Reply to rate:\n(.*?)\n\nRespond with JSON.*", "\\1", p)
    sprintf('{"score": %d, "reason": "length"}', min(10, 1 + nchar(reply) %/% 6))
  }, character(1), USE.NAMES = FALSE)
}

test_that("as_llm wraps every accepted form and refuses the rest", {
  f <- function(p) p
  expect_identical(dragonfarm:::as_llm(f, "teacher"), f)
  local <- dragonfarm:::as_llm("org/model", "teacher", temperature = 0.5)
  expect_equal(attr(local, "label"), "local:org/model")
  run <- dragon_run(copy_fixture_run())
  asrun <- dragonfarm:::as_llm(run, "student")
  expect_equal(attr(asrun, "label"), paste0("run:", run$id))
  expect_error(dragonfarm:::as_llm(NULL, "teacher"), "No teacher given")
  expect_error(dragonfarm:::as_llm(NULL, "student"), "No student given")
  expect_error(dragonfarm:::as_llm(list(), "judge"), "must be a function")
  expect_error(dragonfarm:::call_llm(function(p) "one", c("a", "b"), "teacher"), "returned 1 reply for 2 prompts")
})

test_that("prompts come from vectors, mapped datasets, and runs", {
  expect_equal(dragonfarm:::as_prompt_vector(c("a", "", NA, "b")), c("a", "b"))
  ds <- dragon_map(dragon_dataset(toy_df(3)), "{subject}: {body}", "reply")
  expect_equal(dragonfarm:::as_prompt_vector(ds)[1], "Subject 1: Body text 1")
  expect_error(dragonfarm:::as_prompt_vector(dragon_dataset(toy_df(3))), "no column mapping")
  expect_error(dragonfarm:::as_prompt_vector(42), "character vector")

  run <- suppressMessages(dragon_bundle(dragon_map(dragon_dataset(toy_df(60)), "subject", "reply"),
                                        "HuggingFaceTB/SmolLM2-135M-Instruct", runs_dir = tempfile("runs-")))
  expect_length(dragon_prompts(run, "eval"), 3)
  expect_length(dragon_prompts(run, "train"), 57)
  expect_length(dragon_prompts(run, "train", n = 10), 10)
  expect_equal(dragon_prompts(run, "train", n = 5, seed = 1), dragon_prompts(run, "train", n = 5, seed = 1))
  expect_length(dragon_prompts(dragon_run(copy_fixture_run()), "eval"), 0)
})

test_that("dragon_synthesize writes teacher replies as a mapped, reloadable dataset", {
  runs <- tempfile("runs-")
  ds <- suppressMessages(dragon_synthesize(c("Q1", "Q2", "Q3"), fake_teacher, system = "Be brief.", runs_dir = runs))
  expect_s3_class(ds, "dragon_dataset")
  expect_equal(dragonfarm:::mapping_kind(ds), "messages")
  expect_equal(nrow(ds$data), 3)
  expect_equal(ds$data$response[2], "Teacher answer for Q2")
  expect_true(file.exists(ds$source))
  expect_match(ds$source, "synth/.*-synthetic-sft\\.jsonl$")
  meta <- dragonfarm:::read_json(sub("\\.jsonl$", ".meta.json", ds$source))
  expect_equal(meta$kind, "sft")
  expect_equal(meta$n_kept, 3)
  msgs <- dragonfarm:::dataset_messages(ds, 1)[[1]]$messages
  expect_equal(vapply(msgs, `[[`, character(1), "role"), c("system", "user", "assistant"))
  expect_equal(msgs[[1]]$content, "Be brief.")
  again <- dragon_map(dragon_dataset(ds$source), "prompt", "response")
  expect_equal(nrow(again$data), 3)
  expect_equal(attr(ds, "synthesis")$teacher, "custom")
})

test_that("dragon_synthesize drops empty and failed replies and can write to a chosen file", {
  flaky <- function(prompts) c("fine", "", "__error__ refusal", NA)
  out <- tempfile(fileext = ".jsonl")
  ds <- suppressMessages(dragon_synthesize(c("a", "b", "c", "d"), flaky, file = out))
  expect_equal(nrow(ds$data), 1)
  expect_equal(ds$source, out)
  expect_error(suppressMessages(dragon_synthesize(c("a"), function(p) "", runs_dir = tempfile())), "no usable replies")
  expect_error(dragon_synthesize(c("a"), NULL), "No teacher given")
})

test_that("dragon_synthesize's quality pass drops duplicate prompts and duplicate or near-duplicate responses", {
  # an exact duplicate prompt: only the first occurrence is kept
  teacher1 <- function(ps) paste("Answer for", ps)
  ds1 <- suppressMessages(dragon_synthesize(c("p1", "p2", "p1"), teacher1, runs_dir = tempfile("runs-")))
  expect_equal(ds1$data$prompt, c("p1", "p2"))
  expect_equal(attr(ds1, "synthesis")$dropped$duplicate_prompt, 1)

  # an exact duplicate response, for two different prompts
  teacher2 <- function(ps) c("Same canned answer.", "A different, specific answer.", "Same canned answer.")
  ds2 <- suppressMessages(dragon_synthesize(c("p1", "p2", "p3"), teacher2, runs_dir = tempfile("runs-")))
  expect_equal(nrow(ds2$data), 2)
  expect_equal(attr(ds2, "synthesis")$dropped$duplicate_response, 1)

  # a near-duplicate response: 26 shared words plus one differing tail word
  # (similarity 26/28 ~ 0.93) is flagged at the default threshold but not a stricter one
  near_a <- paste(c(letters, "alpha"), collapse = " ")
  near_b <- paste(c(letters, "beta"), collapse = " ")
  teacher3 <- function(ps) c(near_a, near_b)
  ds3 <- suppressMessages(dragon_synthesize(c("p1", "p2"), teacher3, runs_dir = tempfile("runs-")))
  expect_equal(nrow(ds3$data), 1)
  expect_equal(attr(ds3, "synthesis")$dropped$near_duplicate, 1)
  ds3b <- suppressMessages(dragon_synthesize(c("p1", "p2"), teacher3, near_dup_threshold = 0.95, runs_dir = tempfile("runs-")))
  expect_equal(nrow(ds3b$data), 2)

  # dedupe = FALSE disables all of the above
  ds4 <- suppressMessages(dragon_synthesize(c("p1", "p2", "p1"), teacher1, dedupe = FALSE, runs_dir = tempfile("runs-")))
  expect_equal(nrow(ds4$data), 3)
  expect_equal(attr(ds4, "synthesis")$dropped$duplicate_prompt, 0)
})

test_that("dragon_synthesize's quality pass applies length and garbled-text filters", {
  teacher <- function(ps) c("ok", "A perfectly ordinary, complete answer to the question asked.", strrep("☃", 8))
  ds <- suppressMessages(dragon_synthesize(c("short", "normal", "garbled"), teacher, min_chars = 5, runs_dir = tempfile("runs-")))
  expect_setequal(ds$data$prompt, c("normal", "garbled"))   # "ok" (2 chars) is the only one below min_chars
  expect_equal(attr(ds, "synthesis")$dropped$length, 1)

  ds2 <- suppressMessages(dragon_synthesize(c("short", "normal", "garbled"), teacher, min_chars = 1, min_alpha_ratio = 0.9, runs_dir = tempfile("runs-")))
  expect_setequal(ds2$data$prompt, c("short", "normal"))   # the snowmen have no ordinary characters
  expect_equal(attr(ds2, "synthesis")$dropped$language, 1)

  expect_error(
    suppressMessages(dragon_synthesize(c("a", "b"), function(ps) c("x", "y"), min_chars = 10, runs_dir = tempfile("runs-"))),
    "quality filters"
  )
})

test_that("dragon_synthesize with a judge keeps only replies at or above min_score", {
  # length_judge scores min(10, 1 + nchar(reply) %/% 6): 5 chars -> 1, 12 -> 3, 30 -> 6, 60 -> 10
  teacher <- function(ps) c(strrep("x", 5), strrep("x", 12), strrep("x", 30), strrep("x", 60))
  ds <- suppressMessages(dragon_synthesize(c("p1", "p2", "p3", "p4"), teacher,
                                           judge = length_judge, min_score = 3, runs_dir = tempfile("runs-")))
  expect_setequal(ds$data$prompt, c("p2", "p3", "p4"))
  meta <- attr(ds, "synthesis")
  expect_equal(meta$judge, "custom")
  expect_equal(meta$min_score, 3)
  expect_equal(meta$mean_score, 5)   # mean(1, 3, 6, 10), computed before the score filter
  expect_equal(meta$dropped$low_score, 1)

  expect_error(
    suppressMessages(dragon_synthesize(c("a"), function(p) "x", judge = length_judge, min_score = 9, runs_dir = tempfile())),
    "at or above"
  )
})

test_that("judge mode keeps the best and worst sample per prompt and honours min_gap", {
  runs <- tempfile("runs-")
  ds <- suppressMessages(dragon_synthesize_pairs(c("p1", "p2", "p3"), student = fake_student, judge = length_judge,
                                                 n_samples = 4, min_gap = 1, runs_dir = runs))
  expect_equal(dragonfarm:::mapping_kind(ds), "pairs")
  d <- ds$data
  expect_equal(nrow(d), 3)
  expect_true(all(d$chosen_score > d$rejected_score))
  expect_true(all(nchar(d$chosen) > nchar(d$rejected)))
  expect_true(all(c("chosen_score", "rejected_score") %in% names(d)))
  expect_match(ds$source, "-preferences-pairs\\.jsonl$")
  meta <- dragonfarm:::read_json(sub("\\.jsonl$", ".meta.json", ds$source))
  expect_equal(meta$mode, "judge")
  expect_equal(meta$n_samples, 4)

  strict <- suppressMessages(tryCatch(
    dragon_synthesize_pairs(c("p1", "p2", "p3"), student = fake_student, judge = length_judge,
                            n_samples = 4, min_gap = 100, runs_dir = runs),
    error = function(e) e
  ))
  expect_s3_class(strict, "error")
  expect_match(conditionMessage(strict), "No preference pairs survived")
})

test_that("judge mode drops prompts whose samples cannot be separated", {
  same <- function(prompts) rep("identical", length(prompts))
  expect_error(suppressMessages(dragon_synthesize_pairs("p", student = same, judge = length_judge, n_samples = 3, runs_dir = tempfile())),
               "No preference pairs survived")
  broken_judge <- function(prompts) rep("not json", length(prompts))
  expect_error(suppressMessages(dragon_synthesize_pairs("p", student = fake_student, judge = broken_judge, n_samples = 3, runs_dir = tempfile())),
               "No preference pairs survived")
  expect_error(dragon_synthesize_pairs("p", student = fake_student, judge = length_judge, n_samples = 1), "at least 2")
  expect_error(dragon_synthesize_pairs("p", student = "org/model", judge = length_judge, temperature = 0), "above 0")
  expect_error(dragon_synthesize_pairs("p", student = fake_student), "judge.*or a.*teacher")
})

test_that("teacher mode pairs the teacher's reply against the student's", {
  ds <- suppressMessages(dragon_synthesize_pairs(c("p1", "p2"), student = fake_student, teacher = fake_teacher,
                                                 system = "Be kind.", runs_dir = tempfile("runs-")))
  d <- ds$data
  expect_equal(nrow(d), 2)
  expect_equal(d$chosen, c("Teacher answer for p1", "Teacher answer for p2"))
  expect_match(d$rejected[1], "^reply to p1")
  expect_equal(unique(d$system), "Be kind.")
  rows <- dragonfarm:::dataset_pairs(ds, 1)[[1]]
  expect_equal(rows$prompt[[1]]$role, "system")
  expect_equal(attr(ds, "synthesis")$mode, "teacher")
  # identical replies are not a preference
  expect_error(suppressMessages(dragon_synthesize_pairs("p", student = fake_teacher, teacher = fake_teacher, runs_dir = tempfile())),
               "identical or empty")
})

test_that("synthesized pairs feed straight into a preference run", {
  runs <- tempfile("runs-")
  pairs <- suppressMessages(dragon_synthesize_pairs(paste("prompt", 1:40), student = fake_student, judge = length_judge,
                                                    n_samples = 3, min_gap = 1, runs_dir = runs))
  run <- suppressMessages(dragon_bundle(pairs, "HuggingFaceTB/SmolLM2-135M-Instruct", runs_dir = runs))
  cfg <- dragonfarm:::run_config(run)
  expect_equal(cfg$stage, "prefer")
  expect_equal(cfg$data$format, "pairs")
  expect_match(dragon_code(run), "synth/", fixed = TRUE)
  expect_match(dragon_code(run), "dragon_map_pairs(", fixed = TRUE)
})
