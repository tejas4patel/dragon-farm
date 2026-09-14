flat <- function(d) paste(d$lines, collapse = "\n")

test_that("cpu_diagnosis explains a missing driver", {
  d <- cpu_diagnosis(NULL, NA_real_, windows = TRUE)
  expect_equal(d$reason, "no_driver")
  expect_match(flat(d), "nvidia.com/drivers", fixed = TRUE)
  expect_match(flat(d), "CUDA Toolkit is not needed", fixed = TRUE)
})

test_that("cpu_diagnosis explains a CPU-only torch on Windows with the matching index", {
  d <- cpu_diagnosis(NULL, 592, windows = TRUE)
  expect_equal(d$reason, "cpu_build")
  expect_match(flat(d), "whl/cu130", fixed = TRUE)
  expect_match(flat(d), "DRAGONFARM_TORCH_INDEX", fixed = TRUE)
  expect_match(flat(d), "592", fixed = TRUE)
})

test_that("cpu_diagnosis explains a CPU-only torch on Linux", {
  d <- cpu_diagnosis(NULL, 575, windows = FALSE)
  expect_equal(d$reason, "cpu_build")
  expect_match(flat(d), "whl/cu128", fixed = TRUE)
  expect_match(flat(d), "DRAGONFARM_PYTHON", fixed = TRUE)
})

test_that("cpu_diagnosis treats an empty CUDA string as a CPU build", {
  expect_equal(cpu_diagnosis("", 592, windows = TRUE)$reason, "cpu_build")
  expect_equal(cpu_diagnosis(NA_character_, 592, windows = TRUE)$reason, "cpu_build")
  expect_equal(cpu_diagnosis(character(), 592, windows = TRUE)$reason, "cpu_build")
})

test_that("cpu_diagnosis explains a driver that is too old for the installed torch", {
  d <- cpu_diagnosis("13.0", 560, windows = TRUE)
  expect_equal(d$reason, "driver_too_old")
  expect_match(flat(d), "580", fixed = TRUE)
  expect_match(flat(d), "560", fixed = TRUE)
  expect_match(flat(d), "whl/cu126", fixed = TRUE)
})

test_that("cpu_diagnosis falls through when torch and driver both look right", {
  d <- cpu_diagnosis("12.8", 592, windows = TRUE)
  expect_equal(d$reason, "unknown")
  expect_match(flat(d), "nvidia-smi", fixed = TRUE)
})

test_that("index choice and minimum-driver table agree with each other", {
  expect_equal(torch_index_for_driver(580), "https://download.pytorch.org/whl/cu130")
  expect_equal(torch_index_for_driver(570), "https://download.pytorch.org/whl/cu128")
  expect_equal(torch_index_for_driver(569), "https://download.pytorch.org/whl/cu126")
  expect_true(is.na(torch_index_for_driver(NA_real_)))

  expect_equal(min_driver_for_cuda("13.0"), 580)
  expect_equal(min_driver_for_cuda("12.8"), 570)
  expect_equal(min_driver_for_cuda("12.6"), 560)
  expect_equal(min_driver_for_cuda("12.4"), 550)
  expect_equal(min_driver_for_cuda("11.8"), 525)
  expect_equal(min_driver_for_cuda("not a version"), 525)

  # A driver that is good enough for the index we pick must satisfy that
  # index's own minimum, so the two tables never send a user in circles.
  for (drv in c(560, 570, 580, 600)) {
    idx <- torch_index_for_driver(drv)
    cuda <- switch(sub(".*/whl/cu", "", idx), "130" = "13.0", "128" = "12.8", "126" = "12.6")
    expect_gte(drv, min_driver_for_cuda(cuda))
  }
})
