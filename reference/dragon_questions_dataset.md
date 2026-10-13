# Training data from reviewed questions

Builds the dataset the fine-tune trains on: for every kept question, the
`k` most relevant excerpts are retrieved from the documents (by the
question, not the chunk it was written from, so training matches what
happens at answer time) and placed in the prompt ahead of it; the answer
is the response. This is the setup that beat a plain fine-tune in the
prototypes: the model learns to use excerpts, and the documents stay the
source of truth and can change later without retraining.

## Usage

``` r
dragon_questions_dataset(qa, docs = NULL, k = 4)
```

## Arguments

- qa:

  A `dragon_questions` data frame (only rows with `keep = TRUE` are
  used).

- docs:

  The document set; defaults to the one the questions came from.

- k:

  Excerpts per prompt.

## Value

A mapped `dragon_dataset` ready for
[`dragon_train()`](https://dragonfarm.dev/reference/dragon_train.md).
