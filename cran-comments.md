## R CMD check results

0 errors | 0 warnings | 1 note

The note is "New submission". win-builder (R-devel and R-release) reports
the same single note. Version 0.1.1 rather than 0.1.0 because 0.1.0 was
tagged on GitHub before the cloud-GPU functions were added; no earlier
version was published on CRAN.

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
* All examples that need Python are wrapped in `\dontrun{}`.
* Unit tests run against fixture files and never start Python. The
  end-to-end test is gated behind the `DRAGONFARM_INTEGRATION` environment
  variable and additionally calls `skip_on_cran()`.
* Vignettes are `eval = FALSE`.

## Downloads and user files

The package writes only inside the run directory the user names (default
`dragonfarm_runs` under the working directory) and, through `reticulate`,
inside reticulate's own cache. Model weights are downloaded by Hugging Face
`transformers` into its standard cache on first use, with a message.
