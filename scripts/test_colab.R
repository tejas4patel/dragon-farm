# dragonfarm: Google Colab smoke test
#
# Self-contained: this script installs dragonfarm itself, so it can be run
# on its own, in a fresh R session, with nothing set up beforehand (it does
# not depend on any other script having been run first).
#
# It has one manual step in the middle that happens in a browser, not R.
# Run PART 1, follow the printed instructions in Colab, then come back to
# THIS SAME R SESSION (don't restart R) and press Enter when it asks, to run
# PART 2.
#
# You'll need your own (free) Google account, logged into Colab in a
# browser. This script never asks for or stores any Google credentials --
# you log in yourself, entirely outside R. Colab's free T4 tier costs
# nothing.

# ---- 0. Install dragonfarm from GitHub ---------------------------------------
if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes")
remotes::install_github("tejas4patel/dragon-farm", ref = "v0.3.1", upgrade = "never")
# ^ pinned to the 0.3.1 release candidate, so this always tests the exact
#   version being submitted to CRAN. Drop `ref = "v0.3.1"` to track the
#   latest commit on main instead.

library(dragonfarm)
options(dragonfarm.runs_dir = "~/dragonfarm_runs")   # same folder as the other test scripts, if you ran one

# ============================== PART 1 =======================================
# Build the same dataset as the other test scripts, bundle it for Colab, and
# print the exact steps to take in the browser.

tickets <- dragon_dataset(dragon_example_data()) |>
  dragon_map(
    prompt = "{subject}\n\n{body}",
    response = "reply",
    system = "You are a concise, warm support agent for a smart-home company."
  )

bundle <- dragon_bundle(tickets, "Qwen/Qwen2.5-0.5B-Instruct")
dragon_remote(bundle, "colab")

cat("\n================================================================\n")
cat("Now, in a browser:\n")
cat("  1. The link above opens the dragon-farm notebook directly in Colab\n")
cat("     (log in with your Google account if it asks)\n")
cat("  2. Runtime -> Change runtime type -> T4 GPU (the free tier), Save\n")
cat("  3. Runtime -> Run all\n")
cat("  4. The first cell asks you to upload the bundle zip named above --\n")
cat("     use the file picker it shows\n")
cat("  5. When the last cell finishes, Colab downloads the results zip to\n")
cat("     your browser's default Downloads folder automatically\n")
cat("  6. Optional: Runtime -> Disconnect and delete runtime, to free up\n")
cat("     the GPU for your next session\n")
cat("================================================================\n\n")

readline("Once the results zip has finished downloading, press Enter here to continue... ")

# ============================== PART 2 =======================================
# Bring the results back into R. A file-picker window opens; select the zip
# you just downloaded (usually in your Downloads folder).

results_zip <- file.choose()
run <- dragon_import(bundle, results_zip)

cat("\nImported. Checking the result...\n")
print(dragon_status(run))
print(dragon_evaluate(run))

prompt <- "My thermostat keeps dropping off Wi-Fi."
cat("\n--- Reply from the Colab-trained model ---\n")
cat(dragon_generate(run, prompt), "\n")

cat("\n================================================================\n")
cat("Colab round trip finished with no errors.\n")
cat("Run directory:", run$dir, "\n")
cat("================================================================\n")
