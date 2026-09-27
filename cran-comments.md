## This is a resubmission

Version 0.1.1 was reviewed by Konstanze Lauseker, who asked for the
following changes. Each is fixed:

* Package/software names in `Title` and `Description` are now quoted and
  cased correctly ('Python', 'shiny'); quotes were removed from `LoRA`,
  which is a technique name, not a package.
* Every `\dontrun{}` in the examples was replaced with `if (interactive())
  {}`, so the examples are parsed (though still not run) by `R CMD check`.
* Added `testthat` tests for the app's Shiny modules that had none (the
  Data, Model, and Try it panels), covering their server-side logic
  directly via `shiny::testServer()`, with no live Shiny session, Python,
  or GPU required.
* No function writes to the user's home filespace or working directory by
  default any more. `dragon_runs_dir()` (the default `runs_dir` for every
  function that writes a run) previously defaulted to `dragonfarm_runs`
  under the working directory; it now defaults to `dragonfarm_runs` under
  `tempdir()`, so nothing is written outside a session temp directory
  unless the user explicitly configures a persistent location (an option,
  an environment variable, or a `runs_dir` argument). Tests and examples
  rely on this default (or use `tempfile()`/`tempdir()` explicitly) and
  never touch the working directory or home filespace.
* The one `cat()` in `R/train.R` writes an already-existing run's log
  file, never the console; it now goes through a small file-append helper
  instead of a literal `cat()` call, to remove any ambiguity.
* `.GlobalEnv` is no longer referenced anywhere in the package's own code.
  Three functions used to save and restore `.Random.seed` by hand around a
  seeded sample; they now use `withr::with_seed()`, which does the same
  thing internally without dragonfarm's own source touching `.GlobalEnv`.
  `withr` moved from Suggests to Imports accordingly.

## R CMD check results

0 errors | 0 warnings | 1 note (New submission; carried over from 0.1.1,
which was never actually published).

## Test environments

* local Windows 11, R 4.6.1
* GitHub Actions: ubuntu-latest (release, devel), macos-latest (release), windows-latest (release)
* win-builder (devel, release)

## Python dependencies

This package drives Hugging Face `transformers` and `peft` through a Python
subprocess. Python is declared as a system requirement and is never needed
at install, load, check, or test time:

* `.onLoad()` only declares requirements with `reticulate::py_require()`. It
  does not start Python, download anything, or change the environment.
* The Python environment is built by `reticulate` on the first call to a
  function that needs it, and only after an informative message.
* Examples that need Python are wrapped in `if (interactive())`.
* Unit tests run against fixture files and never start Python. The
  end-to-end test is gated behind the `DRAGONFARM_INTEGRATION` environment
  variable and additionally calls `skip_on_cran()`.
* Vignettes are `eval = FALSE`.

## Downloads and user files

The package writes only inside the run directory the user names, which
defaults to `dragonfarm_runs` under `tempdir()` (never the working
directory or home filespace) unless the user configures a persistent one,
and, through `reticulate`, inside reticulate's own cache. Model weights are
downloaded by Hugging Face `transformers` into its standard cache on first
use, with a message.
