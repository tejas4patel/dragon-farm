test_that("the Monitor module archives, deletes, and restores runs", {
  runs_dir <- tempfile("runs-")
  dir.create(runs_dir)
  dir <- file.path(runs_dir, "20260913-101500-smollm2")
  dir.create(dir)
  file.copy(list.files(fixture_path("run1"), full.names = TRUE), dir, recursive = TRUE)

  state <- shiny::reactiveValues(run = NULL)
  shiny::testServer(dragonfarm:::mod_monitor_server, args = list(state = state, runs_dir = runs_dir), {
    session$setInputs(run = "20260913-101500-smollm2")
    df <- runs()
    expect_equal(df$id, "20260913-101500-smollm2")

    # archive moves it out of the active list (runs() is a reactivePoll;
    # elapse() advances the mock clock past its interval so it re-checks)
    session$setInputs(archive = 1)
    session$elapse(3100)
    expect_equal(nrow(runs()), 0)
    expect_false(dir.exists(dir))
    expect_true(dir.exists(file.path(runs_dir, "archived", "20260913-101500-smollm2")))

    # switch to the archived view and restore it
    session$setInputs(show_archived = TRUE)
    session$elapse(3100)
    df2 <- runs()
    expect_equal(df2$id, "20260913-101500-smollm2")
    session$setInputs(run = "20260913-101500-smollm2", restore = 1)
    expect_true(dir.exists(dir))

    # delete asks for confirmation before removing anything
    session$setInputs(show_archived = FALSE, run = "20260913-101500-smollm2", delete = 1)
    expect_true(dir.exists(dir))   # not deleted yet; awaiting confirmation
    session$setInputs(delete_confirm = 1)
    session$elapse(3100)
    expect_false(dir.exists(dir))
    expect_equal(nrow(runs()), 0)
  })
})

test_that("the Monitor module forgets a currently launched run when it is archived or deleted", {
  runs_dir <- tempfile("runs-")
  dir.create(runs_dir)
  dir <- file.path(runs_dir, "20260913-101500-smollm2")
  dir.create(dir)
  file.copy(list.files(fixture_path("run1"), full.names = TRUE), dir, recursive = TRUE)
  run <- dragon_run(dir)

  state <- shiny::reactiveValues(run = run)
  shiny::testServer(dragonfarm:::mod_monitor_server, args = list(state = state, runs_dir = runs_dir), {
    session$setInputs(run = "20260913-101500-smollm2", archive = 1)
    expect_null(state$run)
  })
})
