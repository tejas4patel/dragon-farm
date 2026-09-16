# Internal helpers shared across the package.

`%||%` <- function(x, y) if (is.null(x)) y else x

# Package-level mutable state (cached Python path, hardware info).
the <- new.env(parent = emptyenv())

is_windows <- function() .Platform$OS.type == "windows"

now_iso <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

empty_object <- function() structure(list(), names = character(0))

read_jsonl <- function(path) {
  if (!file.exists(path)) return(list())
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lines <- lines[nzchar(trimws(lines))]
  lapply(lines, function(l) jsonlite::fromJSON(l, simplifyVector = FALSE))
}

write_jsonl <- function(records, path) {
  lines <- vapply(records, function(r) {
    as.character(jsonlite::toJSON(r, auto_unbox = TRUE, null = "null", digits = NA))
  }, character(1))
  con <- file(path, open = "w", encoding = "UTF-8")
  on.exit(close(con))
  writeLines(lines, con)
  invisible(path)
}

read_json <- function(path) {
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

# The trainer replaces status.json atomically; a read that lands mid-rename
# can see a missing or partial file, so retry a few times.
read_json_retry <- function(path, attempts = 10) {
  for (i in seq_len(attempts)) {
    out <- tryCatch(read_json(path), error = function(e) NULL)
    if (!is.null(out)) return(out)
    Sys.sleep(0.05 * i)
  }
  read_json(path)
}

write_json <- function(x, path) {
  jsonlite::write_json(x, path, auto_unbox = TRUE, null = "null", pretty = TRUE, digits = NA)
  invisible(path)
}

tail_lines <- function(path, n = 50) {
  if (!file.exists(path)) return(character())
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  utils::tail(lines, n)
}

# Turn a list of flat records (possibly with missing keys) into a data frame.
records_to_df <- function(records) {
  if (!length(records)) return(data.frame())
  cols <- unique(unlist(lapply(records, names)))
  out <- lapply(cols, function(cn) {
    vals <- lapply(records, function(r) {
      v <- r[[cn]]
      if (is.null(v)) return(NA)
      if (is.list(v)) return(as.character(jsonlite::toJSON(v, auto_unbox = TRUE)))
      v
    })
    unlist(vals, use.names = FALSE)
  })
  names(out) <- cols
  as.data.frame(out, stringsAsFactors = FALSE, check.names = FALSE)
}

# Convert literal "\n" typed in a text box into real newlines.
unescape_newlines <- function(x) gsub("\\\\n", "\n", x)
escape_newlines <- function(x) gsub("\n", "\\\\n", x)

check_number <- function(x, arg, min = -Inf, max = Inf, integer = FALSE, allow_null = FALSE) {
  if (is.null(x)) {
    if (allow_null) return(invisible(NULL))
    cli::cli_abort("{.arg {arg}} must not be NULL.")
  }
  if (!is.numeric(x) || length(x) != 1 || is.na(x)) {
    cli::cli_abort("{.arg {arg}} must be a single number.")
  }
  if (integer && x != round(x)) cli::cli_abort("{.arg {arg}} must be a whole number.")
  if (x < min || x > max) cli::cli_abort("{.arg {arg}} must be between {min} and {max}.")
  invisible(x)
}

check_string <- function(x, arg) {
  if (!is.character(x) || length(x) != 1 || is.na(x) || !nzchar(x)) {
    cli::cli_abort("{.arg {arg}} must be a single non-empty string.")
  }
  invisible(x)
}

slugify <- function(x) {
  x <- tolower(x)
  x <- gsub("[^a-z0-9]+", "-", x)
  x <- gsub("^-+|-+$", "", x)
  if (!nzchar(x)) "run" else substr(x, 1, 40)
}

hf_token_present <- function() {
  nzchar(Sys.getenv("HF_TOKEN")) || nzchar(Sys.getenv("HUGGING_FACE_HUB_TOKEN")) ||
    file.exists(file.path(Sys.getenv("HF_HOME", file.path(path.expand("~"), ".cache", "huggingface")), "token")) ||
    file.exists(file.path(path.expand("~"), ".cache", "huggingface", "token"))
}

# Deparse a value for generated code; whole numbers print without the L
# suffix that integers read back from JSON would otherwise carry.
fmt_arg <- function(x) {
  if (is.null(x)) return("NULL")
  if (is.numeric(x) && length(x) == 1 && !is.na(x) && x == round(x) && abs(x) < 1e15) return(format(x, scientific = FALSE))
  deparse(x)
}
