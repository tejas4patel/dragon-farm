# GPU prerequisites: which torch wheel index fits a driver, and why a machine
# ended up on the CPU. Pure functions so they are unit-tested without Python.

# PyTorch wheel index whose CUDA build the installed NVIDIA driver supports.
# CUDA 13 wheels need driver 580+, CUDA 12.8 wheels need 570+, CUDA 12.6
# wheels need 560+. NA when there is no driver.
torch_index_for_driver <- function(driver) {
  if (is.na(driver)) return(NA_character_)
  if (driver >= 580) return("https://download.pytorch.org/whl/cu130")
  if (driver >= 570) return("https://download.pytorch.org/whl/cu128")
  "https://download.pytorch.org/whl/cu126"
}

# Minimum NVIDIA driver major version for a CUDA version string such as
# "13.0" or "12.8" (torch.version.cuda). Unknown strings get the CUDA 12
# floor.
min_driver_for_cuda <- function(cuda) {
  v <- suppressWarnings(as.numeric(sub("^(\\d+\\.\\d+).*$", "\\1", as.character(cuda))))
  if (length(v) != 1 || is.na(v)) return(525)
  if (v >= 13) return(580)
  if (v >= 12.8) return(570)
  if (v >= 12.6) return(560)
  if (v >= 12.4) return(550)
  525
}

# Explain why training will run on the CPU and what to do about it.
#
# `torch_cuda_build` is torch.version.cuda from the installed wheel (NULL for
# a CPU-only build), `driver` is the NVIDIA driver major version from
# nvidia-smi (NA when none is installed), `windows` says whether the default
# PyPI torch wheel would have been CPU-only.
#
# Returns list(reason, lines) where `lines` is a named character vector ready
# for cli::cli_bullets(), already interpolated so callers need no variables in
# scope. Reasons: "no_driver", "cpu_build", "driver_too_old", "unknown".
cpu_diagnosis <- function(torch_cuda_build, driver, windows = is_windows()) {
  cpu_build <- is.null(torch_cuda_build) || length(torch_cuda_build) == 0 ||
    is.na(torch_cuda_build) || !nzchar(torch_cuda_build)
  fmt <- function(x) {
    out <- vapply(x, function(line) cli::format_inline(line), character(1))
    names(out) <- names(x)
    out
  }

  if (is.na(driver)) {
    return(list(reason = "no_driver", lines = fmt(c(
      "i" = "No NVIDIA driver was found ({.code nvidia-smi} is not on the PATH).",
      "i" = "If this machine has an NVIDIA GPU, install the current driver from {.url https://www.nvidia.com/drivers}, restart, and run {.fn dragon_check} again. The CUDA Toolkit is not needed: torch bundles its own CUDA libraries.",
      "i" = "If there is no NVIDIA GPU, this is expected. Models of 135M to 360M parameters train on the CPU."
    ))))
  }

  url <- torch_index_for_driver(driver)

  if (cpu_build) {
    lines <- if (windows) c(
      "!" = "NVIDIA driver {driver} is present, but the installed torch is a CPU-only build.",
      "i" = "The PyPI torch wheel for Windows has no CUDA support. Point the installer at the CUDA wheel index and let it rebuild the environment:",
      " " = "  Sys.setenv(DRAGONFARM_TORCH_INDEX = \"{url}\")",
      "i" = "Then restart R and run {.fn dragon_check} again. If {.envvar UV_INDEX} or {.envvar UV_EXTRA_INDEX_URL} is set in your environment it takes precedence and must include that index."
    ) else c(
      "!" = "NVIDIA driver {driver} is present, but the installed torch is a CPU-only build.",
      "i" = "The default PyPI wheel on Linux includes CUDA, so a custom index or the interpreter named by {.envvar DRAGONFARM_PYTHON} selected the CPU build. Reinstall torch from {.url {url}} in that environment, or unset the override so reticulate builds its own."
    )
    return(list(reason = "cpu_build", lines = fmt(lines)))
  }

  need <- min_driver_for_cuda(torch_cuda_build)
  if (driver < need) {
    return(list(reason = "driver_too_old", lines = fmt(c(
      "!" = "torch was built for CUDA {torch_cuda_build}, which needs NVIDIA driver {need} or newer. This machine has {driver}.",
      "i" = "Update the driver from {.url https://www.nvidia.com/drivers} (recommended), or install a torch build that matches the current driver:",
      " " = "  Sys.setenv(DRAGONFARM_TORCH_INDEX = \"{url}\")",
      "i" = "Then restart R and run {.fn dragon_check} again."
    ))))
  }

  list(reason = "unknown", lines = fmt(c(
    "!" = "torch was built for CUDA {torch_cuda_build} and NVIDIA driver {driver} is present, yet CUDA is unavailable.",
    "i" = "Run {.code nvidia-smi} in a terminal to confirm the GPU is visible. Common causes are a driver update that still needs a reboot, or a laptop GPU disabled by the power plan."
  )))
}
