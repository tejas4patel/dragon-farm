# Ask your documents. Then teach a model.

dragonfarm 0.4.0 starts from your documents. Drop in PDFs, Word files,
and web pages. Ask them questions and get answers that name the page.
Then have a model write training questions from them, review those, and
fine-tune. On your own GPU, from R, free.

It reaches CRAN in November. Until then, R-universe builds it for
Windows, Mac, and Linux:

``` r

install.packages("dragonfarm",
  repos = c("https://tejas4patel.r-universe.dev", "https://cloud.r-project.org"))
```

## One PDF, two questions

Costco’s 2024 annual report, all 76 pages of it:

``` r

library(dragonfarm)
docs <- dragon_documents("COST-2024-Annual-Report.pdf", name = "costco-2024")

dragon_ask(docs, "Who is Costco's independent registered public accounting firm?")
#> Costco's independent registered public accounting firm is KPMG LLP, located in Seattle, WA [1].
#>
#> [1]* COST-2024-Annual-Report.pdf, p. 68 › Item 14—Principal Accounting Fees and Services

dragon_ask(docs, "What was net cash used in investing activities in fiscal 2024?")
#> Net cash used in investing activities in fiscal 2024 totaled $4,409 million [1].
#>
#> [1]* COST-2024-Annual-Report.pdf, p. 34 › Cash Flows from Investing Activities
```

Every answer names its page, so you can check it. Of thirteen factual
questions about this report, the model got twelve right. The thirteenth,
a total printed inside a map graphic, it declined rather than guessed.

The app does the same by drag and drop.
[`dragon_app()`](https://dragonfarm.dev/reference/dragon_app.md) opens
on Documents and walks six steps: Documents, Ask, Teach, Train, Monitor,
Try it.

![The app, step by step: drop in documents, ask them with sources,
review generated questions, train, watch the loss, compare against the
base model.](../demo/dragonfarm-demo.gif)

The app, step by step: drop in documents, ask them with sources, review
generated questions, train, watch the loss, compare against the base
model.

## What just happened

- **Read.** PDF, Word, HTML, Markdown, spreadsheets, and web pages are
  split into chunks of about 170 words that never cross a heading. Each
  chunk remembers its file, its section, and its page.
- **Index.** A small embedding model indexes the chunks on your machine,
  with a keyword index beside it for names and figures.
- **Ask.** The four most relevant excerpts go to a language model with
  one instruction: answer only from these. The reply cites them by
  number.
- **Pick the model for the GPU you have.** An 8 GB NVIDIA card gets a 7B
  model in 4-bit: about a minute to load for the first question, a few
  seconds for each one after. 6 to 8 GB gets a 3B; less than that, or a
  CPU, a 1.5B.
  [`dragon_check()`](https://dragonfarm.dev/reference/dragon_check.md)
  tells you which.

Nothing leaves your machine, and nothing is trained yet. For a lot of
uses, this is already the finish line.

## Real documents fight back

That annual report was not a clean test, which is the point. The
standard PDF library returned it as two-letter fragments (“Co st co Wh
ol es al e”). Its cash-flow figures sit pages away from the “(dollars in
millions)” note that gives them their unit. Its table of contents and
running page headers look like content. The Word version of the same
report hides its sub-headings in italics.

Each of those is handled now, and each was found by running a real
document through, not by reading the code.

## When reading back is not enough

Sometimes you want the model to carry the house style, the vocabulary,
or the way your team phrases a policy, not just quote it. That is
fine-tuning, and it normally needs a table of prompts and replies that
nobody has. dragonfarm writes one from the documents:

``` r

qa <- dragon_questions(docs)   # a local model writes questions each chunk can answer
qa                             # every pair kept or rejected, with the reason
```

The questions are written by the same local model that answers, or by
Claude if you pass it as the `generator`. Filters drop questions the
passage cannot answer, answers that drift from the text, and duplicates.
With the 7B writing, 78 to 87 percent survived on real documents.

Then you read them. The Teach step shows the questions grouped by the
chunk they came from, a checkbox each, and the reason for every
rejection so you can overrule it.

The review is the point. Training on unreviewed machine-written pairs is
how a small model learns to make its mistakes confident.

``` r

dragon_questions_save(qa)
run <- dragon_train(dragon_questions_dataset(qa, docs), "Qwen/Qwen2.5-7B-Instruct",
                    hardware = dragon_hardware(load_in_4bit = TRUE),
                    args = dragon_train_args(batch_size = 1, grad_accum = 16,
                                             gradient_checkpointing = TRUE),
                    wait = TRUE)
dragon_chat(run, documents = docs)$say("What drove the change in gross margin?")
```

Every training prompt carries the retrieved excerpts, the same way the
model will see them later. Three things we measured:

- **A 7B trained on R’s manuals** (four hours overnight on the same 8 GB
  laptop) stayed exactly as accurate as before and changed only its
  manner: shorter answers, an excerpt cited every time.
- **Smaller models** trained on the same pairs answered more questions,
  but also learned to cite a source for things the source does not say.
  Fine-tuning is for style, once the model is big enough to know when to
  stop.
- **On support tickets**, the model trained with excerpts in its prompts
  recalled 89 percent of the policy facts on unseen tickets, against 68
  percent for a plain fine-tune. When the policy was edited after
  training, it followed the new text in 88 percent of answers; the plain
  fine-tune kept repeating the old one. The documents stay the source of
  truth and can change without retraining.

## How big a model do you need?

The same tests on four sizes of the same model family, on the same 8 GB
card, before any training:

| Model | Costco figures right | R questions right | Wrong or empty, of 55 | Declined the 20 it could not answer |
|----|----|----|----|----|
| 0.5B | 17 of 23 | 19 of 32 | 14 | 16 |
| 1.5B | 19 of 23 | 28 of 32 | 6 | 20 |
| 3B | 20 of 23 | 30 of 32 | 5 | 20 |
| 7B, 4-bit | 23 of 23 | 31 of 32 | 1 | 20 |

The small models get plenty right. The difference is how often they are
wrong, and whether they say “the documents do not cover that” when it is
true. Before this release the 0.5B never did, and made up details about
Costco’s executives instead. For a fixed output format the picture
flips: every size, 0.5B included, scored 20 of 20 on ticket-to-JSON
after training, and the 0.5B took under three minutes. The full
measurements are in [Choosing a model
size](https://dragonfarm.dev/articles/model-sizes.md).

## What it needs

- **R**, and about 3 GB of disk for the Python environment the package
  sets up on first use.
- **A GPU, or patience.** NVIDIA or Apple Silicon. A 0.5B model trains
  in a few minutes on a laptop GPU; a 7B in 4-bit takes about 22 minutes
  for three epochs on a couple of hundred short examples.
- **No GPU at all?**
  [`dragon_bundle()`](https://dragonfarm.dev/reference/dragon_bundle.md)
  and
  [`dragon_remote()`](https://dragonfarm.dev/reference/dragon_remote.md)
  send the run to a free Colab or Kaggle GPU and bring the adapter back.

## What to expect, honestly

- Retrieval does most of the work, and a larger answering model helps
  more than training does. Answer first, train second.
- A small model trained on a few hundred generated pairs learns to cite
  and to answer in one sentence. It also learns to answer with
  confidence when the documents are silent.
- Questions that need every row of a spreadsheet or every year of a
  table (“which year had the highest margin?”) are out of reach for
  excerpt retrieval. Ask those in R, on the data.
- Tables inside PDFs flatten into lines of text, scans need OCR first,
  and numbers inside charts are lost.
- The numbers above come from a handful of documents, not from yours.
  [From your documents to your
  model](https://dragonfarm.dev/articles/documents.md) has every
  measurement and the settings behind it.

## Try it

``` r

install.packages("dragonfarm",
  repos = c("https://tejas4patel.r-universe.dev", "https://cloud.r-project.org"))
library(dragonfarm)
dragon_app()
```

dragonfarm is MIT licensed. Issues, documents that break it, and pull
requests are welcome at
[github.com/tejas4patel/dragonfarm](https://github.com/tejas4patel/dragonfarm),
and there are a few [good first
issues](https://github.com/tejas4patel/dragonfarm/labels/good%20first%20issue)
to start from.
