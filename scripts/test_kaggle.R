# dragonfarm: Kaggle smoke test
#
# Self-contained: this script installs dragonfarm itself, so it can be run
# on its own, in a fresh R session, with nothing set up beforehand (it does
# not depend on any other script having been run first).
#
# It has one manual step in the middle that happens in a browser, not R.
# Run PART 1, follow the printed instructions on kaggle.com, then come back
# to THIS SAME R SESSION (don't restart R) and press Enter when it asks, to
# run PART 2.
#
# You'll need your own (free) Kaggle account, logged in in a browser. Kaggle
# asks for one-time phone verification before it will turn GPUs on for a new
# account. This script never asks for or stores any Kaggle credentials --
# you log in yourself, entirely outside R. Kaggle's free GPU tier costs
# nothing (about 30 GPU-hours a week).

# ---- 0. Install dragonfarm from GitHub ---------------------------------------
if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes")
remotes::install_github("tejas4patel/dragon-farm", ref = "v0.3.0", upgrade = "never")
# ^ pinned to the 0.3.0 release candidate, so this always tests the exact
#   version being submitted to CRAN. Drop `ref = "v0.3.0"` to track the
#   latest commit on main instead.

library(dragonfarm)
options(dragonfarm.runs_dir = "~/dragonfarm_runs")   # same folder as the other test scripts, if you ran one

# ============================== PART 1 =======================================
# Build the same dataset as the other test scripts, bundle it for Kaggle, and
# print the exact steps to take in the browser.

tickets <- dragon_dataset(dragon_example_data()) |>
  dragon_map(
    prompt = "{subject}\n\n{body}",
    response = "reply",
    system = "You are a concise, warm support agent for a smart-home company."
  )

bundle <- dragon_bundle(tickets, "Qwen/Qwen2.5-0.5B-Instruct")
dragon_remote(bundle, "kaggle")

cat("\n================================================================\n")
cat("Now, in a browser:\n")
cat("  1. The link above opens the dragon-farm notebook on Kaggle (log in,\n")
cat("     or verify your phone number, if it asks -- one-time for a new\n")
cat("     account). If it opens a blank notebook instead, use\n")
cat("     File -> Import Notebook -> Link and paste the GitHub notebook\n")
cat("     URL printed above.\n")
cat("  2. In the right sidebar: Accelerator -> GPU T4 x2 (or P100),\n")
cat("     Internet -> On\n")
cat("  3. Input -> Upload -> New Dataset: upload the bundle zip named\n")
cat("     above. It lands under /kaggle/input, where the notebook expects it.\n")
cat("  4. Run All\n")
cat("  5. When the notebook finishes, the results zip appears under the\n")
cat("     Output tab -- click it, then Download\n")
cat("================================================================\n\n")

readline("Once you've downloaded the results zip, press Enter here to continue... ")

# ============================== PART 2 =======================================
# Bring the results back into R. A file-picker window opens; select the zip
# you just downloaded (usually in your Downloads folder).

results_zip <- file.choose()
run <- dragon_import(bundle, results_zip)

cat("\nImported. Checking the result...\n")
print(dragon_status(run))
print(dragon_evaluate(run))

prompt <- "My thermostat keeps dropping off Wi-Fi."
cat("\n--- Reply from the Kaggle-trained model ---\n")
cat(dragon_generate(run, prompt), "\n")

cat("\n================================================================\n")
cat("Kaggle round trip finished with no errors.\n")
cat("Run directory:", run$dir, "\n")
cat("================================================================\n")
