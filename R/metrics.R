#' Task metrics for generated replies
#'
#' Deterministic checks that need no judge model. Each metric is a function
#' of three character vectors, `generated`, `reference`, and `prompt`, and
#' returns one number per row (0 or 1 for pass/fail metrics). Pass names
#' from this list, or your own functions, to [dragon_evaluate()].
#'
#' * `exact`: normalized exact match (case, whitespace, and trailing
#'   punctuation ignored).
#' * `contains`: the normalized reference appears inside the reply.
#' * `token_f1`: token overlap F1 between reply and reference, the SQuAD
#'   style partial-credit score.
#' * `json_valid`: the reply parses as JSON (a fenced code block is unwrapped
#'   first).
#' * `numeric`: the last number in the reply equals the last number in the
#'   reference.
#' * `length_ratio`: characters in the reply divided by characters in the
#'   reference. Useful for spotting rambling or truncation.
#'
#' `dragon_metric_regex()` builds a metric that passes when the reply
#' matches a pattern, for format checks such as "starts with a ticket id".
#'
#' @return `dragon_metrics()`: a named list of metric functions.
#' @export
#' @examples
#' m <- dragon_metrics()
#' m$exact("Paris.", "paris", "Capital of France?")
#' m$token_f1("the cat sat on the mat", "a cat sat on a mat", "")
#' m$json_valid('```json\n{"a": 1}\n```', "", "")
dragon_metrics <- function() {
  list(
    exact = metric_exact,
    contains = metric_contains,
    token_f1 = metric_token_f1,
    json_valid = metric_json_valid,
    numeric = metric_numeric,
    length_ratio = metric_length_ratio
  )
}

#' @rdname dragon_metrics
#' @param pattern A regular expression the reply must match.
#' @param ignore_case Case-insensitive match.
#' @return `dragon_metric_regex()`: a metric function.
#' @export
dragon_metric_regex <- function(pattern, ignore_case = TRUE) {
  check_string(pattern, "pattern")
  force(ignore_case)
  function(generated, reference, prompt) {
    as.numeric(grepl(pattern, generated %||% "", ignore.case = ignore_case, perl = TRUE))
  }
}

normalize_text <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub("\\s+", " ", x)
  x <- gsub("[[:punct:]]+$", "", x)
  x[is.na(x)] <- ""
  x
}

metric_exact <- function(generated, reference, prompt) {
  as.numeric(normalize_text(generated) == normalize_text(reference))
}

metric_contains <- function(generated, reference, prompt) {
  g <- normalize_text(generated)
  r <- normalize_text(reference)
  out <- mapply(function(gg, rr) nzchar(rr) && grepl(rr, gg, fixed = TRUE), g, r, USE.NAMES = FALSE)
  as.numeric(out)
}

tokens_of <- function(x) {
  x <- normalize_text(x)
  x <- gsub("[[:punct:]]+", " ", x)
  toks <- strsplit(trimws(x), "\\s+")
  lapply(toks, function(t) t[nzchar(t)])
}

metric_token_f1 <- function(generated, reference, prompt) {
  g <- tokens_of(generated)
  r <- tokens_of(reference)
  mapply(function(gt, rt) {
    if (!length(gt) && !length(rt)) return(1)
    if (!length(gt) || !length(rt)) return(0)
    common <- 0
    pool <- rt
    for (t in gt) {
      hit <- match(t, pool)
      if (!is.na(hit)) {
        common <- common + 1
        pool <- pool[-hit]
      }
    }
    if (common == 0) return(0)
    p <- common / length(gt)
    rc <- common / length(rt)
    2 * p * rc / (p + rc)
  }, g, r, USE.NAMES = FALSE)
}

# Strip a ```json fence if the whole reply is one code block.
unfence <- function(x) {
  x <- trimws(x)
  m <- regmatches(x, regexec("^```[a-zA-Z]*\\s*\\n?([\\s\\S]*?)\\n?```$", x, perl = TRUE))[[1]]
  if (length(m) == 2) m[2] else x
}

metric_json_valid <- function(generated, reference, prompt) {
  vapply(as.character(generated), function(g) {
    if (is.na(g)) return(0)
    ok <- tryCatch({
      jsonlite::fromJSON(unfence(g), simplifyVector = FALSE)
      TRUE
    }, error = function(e) FALSE)
    as.numeric(ok)
  }, numeric(1), USE.NAMES = FALSE)
}

last_number <- function(x) {
  m <- regmatches(x, gregexpr("-?\\d[\\d,]*\\.?\\d*", x, perl = TRUE))[[1]]
  if (!length(m)) return(NA_real_)
  suppressWarnings(as.numeric(gsub(",", "", m[length(m)])))
}

metric_numeric <- function(generated, reference, prompt) {
  mapply(function(g, r) {
    a <- last_number(as.character(g))
    b <- last_number(as.character(r))
    if (is.na(a) || is.na(b)) return(0)
    tol <- max(1e-6, abs(b) * 1e-6)
    as.numeric(abs(a - b) <= tol)
  }, generated, reference, USE.NAMES = FALSE)
}

metric_length_ratio <- function(generated, reference, prompt) {
  g <- nchar(as.character(generated))
  r <- nchar(as.character(reference))
  g[is.na(g)] <- 0
  ifelse(is.na(r) | r == 0, NA_real_, g / r)
}

# Resolve what the user passed as `metrics` into a named list of functions.
resolve_metrics <- function(metrics) {
  if (isTRUE(metrics)) return(dragon_metrics())
  if (is.null(metrics) || isFALSE(metrics)) return(list())
  all <- dragon_metrics()
  if (is.character(metrics)) {
    bad <- setdiff(metrics, names(all))
    if (length(bad)) {
      cli::cli_abort(c(
        "Unknown {cli::qty(length(bad))}metric{?s}: {.val {bad}}.",
        "i" = "Built-in metrics are {.val {names(all)}}; anything else must be a function."
      ))
    }
    return(all[metrics])
  }
  if (is.function(metrics)) metrics <- list(custom = metrics)
  if (!is.list(metrics) || is.null(names(metrics)) || any(!nzchar(names(metrics)))) {
    cli::cli_abort("{.arg metrics} must be TRUE, metric names, or a named list of functions.")
  }
  out <- lapply(names(metrics), function(nm) {
    m <- metrics[[nm]]
    if (is.character(m) && length(m) == 1 && m %in% names(all)) return(all[[m]])
    if (!is.function(m)) cli::cli_abort("Metric {.val {nm}} is neither a built-in name nor a function.")
    m
  })
  names(out) <- names(metrics)
  out
}

# Apply metrics to a samples data frame. Returns list(per_sample = data.frame, summary = named numeric).
compute_metrics <- function(samples, metrics) {
  fns <- resolve_metrics(metrics)
  if (!length(fns) || !nrow(samples)) return(list(per_sample = samples, summary = stats::setNames(numeric(), character())))
  gen <- as.character(samples$generated)
  ref <- as.character(samples$reference %||% rep(NA_character_, nrow(samples)))
  pr <- as.character(samples$prompt %||% rep("", nrow(samples)))
  per <- samples
  summary <- numeric()
  for (nm in names(fns)) {
    vals <- tryCatch(as.numeric(fns[[nm]](gen, ref, pr)), error = function(e) {
      cli::cli_abort("Metric {.val {nm}} failed: {conditionMessage(e)}")
    })
    if (length(vals) != nrow(samples)) cli::cli_abort("Metric {.val {nm}} returned {length(vals)} values for {nrow(samples)} rows.")
    per[[nm]] <- vals
    summary[[nm]] <- mean(vals, na.rm = TRUE)
  }
  list(per_sample = per, summary = summary)
}
