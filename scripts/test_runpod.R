# dragonfarm: RunPod smoke test
#
# Self-contained: this script installs dragonfarm itself, so it can be run
# on its own, in a fresh R session, with nothing set up beforehand (it does
# not depend on test_local_gpu.R having been run first).
#
# It has one manual step in the middle that happens in a browser, not R.
# Run PART 1, follow the printed instructions on runpod.io, then come back to
# THIS SAME R SESSION (don't restart R) and press Enter when it asks, to run
# PART 2.
#
# You'll need your own RunPod account, already funded, open in a browser.
# This script never asks for or stores any RunPod credentials -- you log in
# and pay for the pod yourself, entirely outside R.

# ---- 0. Install dragonfarm from GitHub ---------------------------------------
if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes")
remotes::install_github("tejas4patel/dragon-farm", ref = "v0.3.2", upgrade = "never")
# ^ pinned to the 0.3.2 release candidate, so this always tests the exact
#   version being submitted to CRAN. Drop `ref = "v0.3.2"` to track the
#   latest commit on main instead.

library(dragonfarm)
options(dragonfarm.runs_dir = "~/dragonfarm_runs")   # same folder as the local GPU test, if you also ran it

# ============================== PART 1 =======================================
# Build the same dataset as the local test, bundle it for RunPod, and print
# the exact steps to take in the browser.

tickets <- dragon_dataset(dragon_example_data()) |>
  dragon_map(
    prompt = "{subject}\n\n{body}",
    response = "reply",
    system = "You are a concise, warm support agent for a smart-home company."
  )

bundle <- dragon_bundle(tickets, "Qwen/Qwen2.5-0.5B-Instruct")
dragon_remote(bundle, "runpod")

cat("\n================================================================\n")
cat("Now, in a browser:\n")
cat("  1. runpod.io/console -> log in -> '+ Deploy' (or '+ GPU Pod')\n")
cat("  2. Pick the 'RunPod PyTorch' template\n")
cat("  3. Pick a GPU with 16 GB VRAM or more, click Deploy\n")
cat("  4. Wait for the pod's status to say 'Running'\n")
cat("  5. Click Connect -> 'Connect to Jupyter Lab'\n")
cat("  6. In Jupyter, click Upload and add the two files named above\n")
cat("  7. Double-click the .ipynb file, then Run -> Run All Cells\n")
cat("  8. When the last cell finishes, right-click the new\n")
cat("     dragonfarm-results-*.zip file in the file list and Download\n")
cat("  9. Back in the RunPod console: click the pod, click Stop\n")
cat("     (RunPod bills by the hour while a pod is running -- don't skip this)\n")
cat("================================================================\n\n")

readline("Once you've downloaded the results zip and stopped the pod, press Enter here to continue... ")

# ============================== PART 2 =======================================
# Bring the results back into R. A file-picker window opens; select the zip
# you just downloaded (usually in your Downloads folder).

results_zip <- file.choose()
run <- dragon_import(bundle, results_zip)

cat("\nImported. Checking the result...\n")
print(dragon_status(run))
print(dragon_evaluate(run))

prompt <- "My thermostat keeps dropping off Wi-Fi."
cat("\n--- Reply from the RunPod-trained model ---\n")
cat(dragon_generate(run, prompt), "\n")

cat("\n================================================================\n")
cat("RunPod round trip finished with no errors.\n")
cat("Run directory:", run$dir, "\n")
cat("================================================================\n")
