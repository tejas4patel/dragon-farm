# Read documents into a document set

Reads files or web pages, splits them into chunks of about `max_words`
words that never cross a heading, and stores the result as a document
set under `runs_dir/documents/<name>/`. Each chunk keeps the file (or
URL) and the section heading it came from, so later answers can say
where they came from. This is the first step of the document route: no
column mapping, no training yet.

## Usage

``` r
dragon_documents(
  paths,
  name = NULL,
  runs_dir = dragon_runs_dir(),
  max_words = 170,
  min_words = 35,
  index = TRUE
)
```

## Arguments

- paths:

  Character vector of files, directories, or URLs.

- name:

  Name of the document set, used for the directory. Defaults to the
  first path's file name, or `"documents"` for several paths.

- runs_dir:

  Parent directory; the set goes under
  `file.path(runs_dir, "documents", name)`. See
  [`dragon_runs_dir()`](https://dragonfarm.dev/reference/dragon_runs_dir.md)
  for why the default is temporary and how to keep sets between
  sessions.

- max_words:

  Target chunk size in words. Chunks never cross a heading, so most are
  shorter.

- min_words:

  Sections shorter than this are folded into the previous chunk.

- index:

  Build the retrieval index right away (see
  [`dragon_index()`](https://dragonfarm.dev/reference/dragon_index.md)),
  so [`dragon_ask()`](https://dragonfarm.dev/reference/dragon_ask.md)
  works immediately. The first call downloads the small embedding model.
  `FALSE` postpones it; retrieval then indexes on first use.

## Value

A `dragon_documents` object: the directory, the name, and the manifest.
[`print()`](https://rdrr.io/r/base/print.html) lists the sources;
[`dragon_chunks()`](https://dragonfarm.dev/reference/dragon_chunks.md)
returns the chunks as a data frame.

## Details

Supported inputs: PDF, HTML, Markdown, plain text, Word (`.docx`),
spreadsheets (`.xlsx`, `.csv`, `.tsv`; one chunk per group of rows, each
row written as `column: value` pairs), directories (walked for those
file types), and `http(s)` URLs (fetched once; the page's text is kept).

Reading the same set again re-reads only files whose contents changed
and keeps the other chunks as they were. Files named like a changelog
(`NEWS`, `CHANGELOG`, ...) or made mostly of version headings are read
but flagged, and their chunks are down-weighted when retrieved, because
they tend to crowd out the page that actually answers a question. Quoted
material (block quotes) and code blocks are marked on each chunk so
question generation can skip them.

## See also

[`dragon_ask()`](https://dragonfarm.dev/reference/dragon_ask.md),
[`dragon_chunks()`](https://dragonfarm.dev/reference/dragon_chunks.md),
[`dragon_documents_load()`](https://dragonfarm.dev/reference/dragon_documents_load.md),
[`dragon_documents_list()`](https://dragonfarm.dev/reference/dragon_documents_list.md)

## Examples

``` r
if (interactive()) {
docs <- dragon_documents(c("policies.pdf", "https://example.com/faq"), name = "support")
docs
head(dragon_chunks(docs))
}
```
