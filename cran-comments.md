## This is an update to fix an additional-issues failure on 0.3.3

dragonfarm 0.3.3 is on CRAN. Its "Additional issues" entry (M1mac) reports one
failing test, `test-run.R:5`, which passed on all nine regular flavors:

* The test compared `dragon_runs_dir()`'s default (a directory under
  `tempdir()` that does not exist yet) against `tempdir()` after
  `normalizePath()`. On macOS, `normalizePath()` resolves `/var` to
  `/private/var` for the existing `tempdir()` but leaves the nonexistent path
  unresolved, so the prefix comparison failed. The test now compares the
  existing parent directory instead.
* Only the test changed. There is no change to package code or behaviour.

This is submitted 5 days after 0.3.3 because the CRAN package page asks for
the issue to be fixed before 2026-10-29, hence the "Days since last update"
NOTE below.

## R CMD check results

Local `R CMD check --as-cran` on 0.3.4: 0 errors | 0 warnings | 2 notes.

* "Days since last update: 5", explained above.
* "detritus in the temp directory" (a leftover `Rscript` temp file from the
  local Windows run).

On the regular CRAN flavors, 0.3.3 is OK on all nine. The one NOTE seen at its
submission ("Possibly misspelled words: LoRA") refers to the name of the
technique, defined in the Description as Low-Rank Adaptation.

## Test environments

* local Windows 11, R 4.6.1
* the CRAN incoming checks and the regular flavors, via the 0.3.3 submission
