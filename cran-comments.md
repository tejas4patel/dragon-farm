## Submission

This is a feature release, 0.4.0. Its main addition is a document route:
functions that read PDF, Word, HTML, Markdown, spreadsheet files and web pages
into chunked "document sets", retrieve the relevant chunks for a question,
answer with cited sources, and turn the documents into training data. As in
earlier versions, all heavy work runs in a separate 'Python' process; no
'Python' code runs during R CMD check, and examples and tests that need it are
skipped on CRAN.

## R CMD check results

Local `R CMD check --as-cran` on the 0.4.0 tarball (Windows 11, R 4.6.1):
0 errors | 0 warnings | 1 note. The note is the incoming check's "Days since
last update", from a run made three days after 0.3.4; this release is
submitted at least a month after 0.3.4, so it should not appear.

The "detritus in the temp directory" NOTE reported with 0.3.4 is fixed: a
test started `Rscript -e` and stopped it, and on Windows that leaves an
`Rscript*` file in the temporary folder. The test now runs a script file in
its own temporary folder, and the package's background pipelines also run
from a script file.

## Changes that touch the check

* New 'Python' requirements for the document readers ('pypdf',
  'python-docx', 'openpyxl') and for 4-bit loading ('bitsandbytes', skipped
  on macOS). They are declared with `reticulate::py_require()` and installed
  only when a user first runs a function that needs 'Python'.
* New example data under `inst/extdata/policies/` (three short Markdown
  files, about 16 KB on disk).
* `Language: en-GB` added to DESCRIPTION, with `inst/WORDLIST`.
* Title and Description now describe the document route as well as the
  table route.

## Test environments

* local Windows 11, R 4.6.1
* GitHub Actions: macOS (release), Windows (release), Ubuntu (devel,
  release, oldrel-1)
