# Builds tickets the example data never contained: the (product, subject, body)
# combinations that data-raw/support_tickets.R did not draw. Run from the repo root:
#   Rscript scripts/rag_prototype/make_eval_tickets.R
# The generator is sourced from a temporary working directory so that
# inst/extdata/support_tickets.jsonl is not rewritten.
root <- normalizePath(".")
gen <- file.path(root, "data-raw", "support_tickets.R")
tmp <- tempfile("rag_gen_"); dir.create(tmp)
old <- setwd(tmp); on.exit(setwd(old))
env <- new.env()
sys.source(gen, envir = env)
setwd(old)

n_per_issue <- 8
set.seed(7)
rows <- list()
for (k in seq_along(env$issues)) {
  iss <- env$issues[[k]]
  all <- expand.grid(p = env$products, s = seq_along(iss$subjects), b = seq_along(iss$bodies), stringsAsFactors = FALSE)
  used <- env$pools[[k]]
  # drop the combos drawn (even the few beyond the 200th row, to be safe)
  key <- function(d) paste(d$p, d$s, d$b)
  free <- all[!(key(all) %in% key(used)), , drop = FALSE]
  free <- free[sample(nrow(free), min(n_per_issue, nrow(free))), , drop = FALSE]
  for (i in seq_len(nrow(free))) {
    p <- free$p[i]
    rows[[length(rows) + 1]] <- list(
      id = sprintf("E-%03d", length(rows) + 1), product = p, category = iss$key,
      subject = env$glue_fill(iss$subjects[free$s[i]], p),
      body = env$glue_fill(iss$bodies[free$b[i]], p)
    )
  }
}
out <- file.path(root, "scripts", "rag_prototype", "eval_tickets.jsonl")
con <- file(out, open = "w", encoding = "UTF-8")
for (r in rows) writeLines(as.character(jsonlite::toJSON(r, auto_unbox = TRUE)), con)
close(con)
cat("wrote", length(rows), "unseen tickets\n")
# sanity: none of them appears in the shipped training file
shipped <- jsonlite::stream_in(file(file.path(root, "inst", "extdata", "support_tickets.jsonl")), verbose = FALSE)
ev <- jsonlite::stream_in(file(out), verbose = FALSE)
cat("overlap with shipped data:", sum(paste(ev$subject, ev$body) %in% paste(shipped$subject, shipped$body)), "\n")
