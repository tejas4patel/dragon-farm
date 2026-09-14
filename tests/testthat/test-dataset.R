test_that("data frames become datasets and factors are converted", {
  df <- data.frame(a = factor(c("x", "y")), b = 1:2)
  ds <- dragon_dataset(df)
  expect_s3_class(ds, "dragon_dataset")
  expect_type(ds$data$a, "character")
  expect_equal(nrow(ds$data), 2)
  expect_null(ds$mapping)
})

test_that("csv and jsonl files are read", {
  csv <- tempfile(fileext = ".csv")
  utils::write.csv(toy_df(3), csv, row.names = FALSE)
  ds <- dragon_dataset(csv)
  expect_equal(names(ds$data), c("subject", "body", "reply"))
  expect_equal(ds$name, basename(csv))

  jl <- tempfile(fileext = ".jsonl")
  writeLines(c('{"q":"hi","a":"hello"}', '{"q":"bye"}'), jl)
  ds2 <- dragon_dataset(jl)
  expect_equal(nrow(ds2$data), 2)
  expect_true(is.na(ds2$data$a[2]))
})

test_that("format override and unsupported formats", {
  f <- tempfile(fileext = ".txt")
  utils::write.csv(toy_df(2), f, row.names = FALSE)
  expect_error(dragon_dataset(f), "Unsupported format")
  expect_equal(nrow(dragon_dataset(f, format = "csv")$data), 2)
  expect_error(dragon_dataset("does-not-exist.csv"), "does not exist")
})

test_that("empty inputs are rejected", {
  expect_error(dragon_dataset(data.frame(a = character())), "no rows")
})

test_that("the bundled example loads", {
  ds <- dragon_dataset(dragon_example_data())
  expect_equal(nrow(ds$data), 200)
  expect_true(all(c("subject", "body", "reply", "product") %in% names(ds$data)))
  expect_message(print(ds), "200 rows")
})
