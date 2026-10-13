# Find the chunks most relevant to a question

Find the chunks most relevant to a question

## Usage

``` r
dragon_retrieve(docs, query, k = 4)
```

## Arguments

- docs:

  A `dragon_documents` object or its directory. Indexed on the fly if it
  has no index yet.

- query:

  One question, or several.

- k:

  Chunks to return per query.

## Value

A data frame with one row per hit: `query` (when several), `n` (rank),
`id`, `source`, `section`, `text`, `score` (cosine similarity times the
chunk's weight), `similarity`, and `weight`.
