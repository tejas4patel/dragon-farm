# Appends one row of growth metrics to scripts/metrics_log.csv.
# Run from the repo root: Rscript scripts/metrics.R
#
# Needs the GitHub CLI (`gh`) already logged in. Nothing here stores a token.
# CRAN download counts come from the public cranlogs API and lag by about a day.

repo <- "tejas4patel/dragonfarm"
pkg <- "dragonfarm"
published <- as.Date("2026-10-07")
today <- Sys.Date()

num_or_na <- function(expr) tryCatch(as.numeric(expr), error = function(e) NA_real_, warning = function(w) NA_real_)

cran_total <- function(from, to) {
  url <- sprintf("https://cranlogs.r-pkg.org/downloads/total/%s:%s/%s", from, to, pkg)
  num_or_na(jsonlite::fromJSON(url)$downloads)
}

gh_json <- function(endpoint) {
  out <- system2("gh", c("api", endpoint), stdout = TRUE, stderr = FALSE)
  jsonlite::fromJSON(paste(out, collapse = ""))
}

repo_info <- tryCatch(gh_json(paste0("repos/", repo)), error = function(e) list())
views <- tryCatch(gh_json(paste0("repos/", repo, "/traffic/views")), error = function(e) list())
clones <- tryCatch(gh_json(paste0("repos/", repo, "/traffic/clones")), error = function(e) list())

row <- data.frame(
  date = as.character(today),
  cran_downloads_since_publish = cran_total(published, today),
  cran_downloads_last_7d = cran_total(today - 7, today - 1),
  github_stars = num_or_na(repo_info$stargazers_count),
  github_forks = num_or_na(repo_info$forks_count),
  github_watchers = num_or_na(repo_info$subscribers_count),
  open_issues = num_or_na(repo_info$open_issues_count),
  views_14d = num_or_na(views$count),
  unique_visitors_14d = num_or_na(views$uniques),
  clones_14d = num_or_na(clones$count)
)

log_path <- file.path("scripts", "metrics_log.csv")
write.table(row, log_path, sep = ",", row.names = FALSE,
            col.names = !file.exists(log_path), append = file.exists(log_path))
print(row, row.names = FALSE)
