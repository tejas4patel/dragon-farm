# dragonfarm: local GPU smoke test
#
# Self-contained: this script installs dragonfarm itself, so it can be run
# on its own, in a fresh R session, with nothing set up beforehand.
#
# Run top to bottom in R (line by line with Ctrl+Enter in RStudio, or
# source("scripts/test_local_gpu.R") to run it all at once). Stops with a
# clear error if any step doesn't look right.

# ---- 0. Install dragonfarm from GitHub ---------------------------------------
if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes")
remotes::install_github("tejas4patel/dragon-farm", ref = "v0.3.3", upgrade = "never")
# ^ pinned to the 0.3.3 release candidate, so this always tests the exact
#   version being submitted to CRAN. Drop `ref = "v0.3.3"` to track the
#   latest commit on main instead.

library(dragonfarm)

# ---- 1. Confirm the GPU is actually visible to torch ------------------------
info <- dragon_check()
print(info)
if (!identical(info$device, "cuda")) {
  stop(
    "dragon_check() reported device = '", info$device, "', not 'cuda'. ",
    "Run nvidia-smi in a terminal to confirm the driver is installed, ",
    "then try again before continuing."
  )
}
cat("\nGPU confirmed:", info$device_name, "\n\n")

# ---- 2. Keep this run around after the R session ends -----------------------
# dragon_runs_dir() defaults to a session temp folder as of 0.3.0, which
# disappears when R closes. Point it somewhere real for this test.
options(dragonfarm.runs_dir = "~/dragonfarm_runs")
cat("Runs will be saved under:", normalizePath(dragon_runs_dir(), mustWork = FALSE), "\n\n")

# ---- 3. Load and map the built-in example dataset ---------------------------
tickets <- dragon_dataset(dragon_example_data()) |>
  dragon_map(
    prompt = "{subject}\n\n{body}",
    response = "reply",
    system = "You are a concise, warm support agent for a smart-home company."
  )
dragon_preview(tickets, n = 1)

# ---- 4. Train -----------------------------------------------------------------
cat("\nTraining (a minute or two on a real GPU)...\n")
run <- dragon_train(tickets, "Qwen/Qwen2.5-0.5B-Instruct", wait = TRUE)
print(run)

# ---- 5. Evaluate on the held-out rows ----------------------------------------
cat("\nEvaluating...\n")
print(dragon_evaluate(run))

# ---- 6. Compare the fine-tuned model against the untouched base -------------
prompt <- "My thermostat keeps dropping off Wi-Fi."
cat("\n--- Fine-tuned reply ---\n")
cat(dragon_generate(run, prompt), "\n")
cat("\n--- Base model reply (for comparison) ---\n")
cat(dragon_generate(run, prompt, base = TRUE), "\n")

# ---- 7. Done ------------------------------------------------------------------
cat("\n================================================================\n")
cat("Local GPU test finished with no errors.\n")
cat("Run directory:", run$dir, "\n")
cat("To try the drag-and-drop app now, run:  dragon_app()\n")
cat("================================================================\n")
