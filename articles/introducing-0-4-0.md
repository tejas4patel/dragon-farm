# Ask your documents. Then teach a model.

dragonfarm 0.4.0 starts from your documents. Drop in PDFs, Word files,
and web pages, ask them questions, and get answers that name the page
they came from. When you want more, it turns the same documents into
training data and fine-tunes a model on them. All from R, on your own
machine, free.

## Ask, and see the source

I gave it Costco’s 2024 annual report, all 76 pages, and asked two
questions:

Question

Who is Costco’s independent registered public accounting firm?

Costco’s independent registered public accounting firm is KPMG LLP,
located in Seattle, WA \[1\].

\[1\] Annual report, p. 68 › Item 14, Principal Accounting Fees and
Services

Question

What was net cash used in investing activities in fiscal 2024?

Net cash used in investing activities in fiscal 2024 totaled \$4,409
million \[1\].

\[1\] Annual report, p. 34 › Cash Flows from Investing Activities

Of thirteen factual questions about the report, it got twelve right. The
thirteenth, a figure printed inside a map, it said the report does not
cover, rather than guessing.

## Six steps, one app

![The app, step by step: drop in documents, ask them with sources,
review generated questions, train, watch the loss, compare against the
base model.](../demo/dragonfarm-demo.gif)

The app, step by step: drop in documents, ask them with sources, review
generated questions, train, watch the loss, compare against the base
model.

1.  **Documents.** Drop in PDFs, Word files, web pages, spreadsheets, or
    a whole folder.
2.  **Ask.** Get answers with numbered sources you can check.
3.  **Teach.** A model writes practice questions and answers from your
    documents. You keep the good ones.
4.  **Train.** Fine-tune a model on the pairs you kept.
5.  **Monitor.** Watch it learn.
6.  **Try it.** Put the tuned model next to the original, both answering
    from your documents.

Your documents never leave your machine. No GPU? dragonfarm can send the
training to a free Colab or Kaggle GPU and bring the model back.

## What you get

- **Answers you can check.** Every answer names its file, page, and
  section.
- **An honest “not covered”.** Ask about something the documents do not
  contain and the answer says so.
- **Training data you did not have to write.** Most people who want to
  fine-tune have documents, not a table of questions and answers.
  dragonfarm writes that table for you to review.
- **A model that is yours.** It runs on your machine and loads anywhere
  with standard tools.
- **The right model for your machine.** An 8 GB laptop GPU runs a 7B
  model; smaller cards and CPUs get a smaller one, picked for you.

## What we measured

The same questions, the same documents, four model sizes, one 8 GB
laptop GPU, before any training:

| Model | Annual report: right of 23 | R manuals: right of 32 | Said “not covered” when true, of 20 |
|----|----|----|----|
| 0.5B | 17 | 19 | 16 |
| 1.5B | 19 | 28 | 20 |
| 3B | 20 | 30 | 20 |
| 7B | 23 | 31 | 20 |

And after training:

- **A 7B trained on R’s manuals** stayed exactly as accurate and changed
  its manner: shorter answers, a source cited every time.
- **On support tickets**, a model trained this way recalled 89 percent
  of the policy facts on tickets it had never seen, against 68 percent
  for ordinary fine-tuning. When the policy changed after training, it
  followed the new version in 88 percent of answers.
- **For a fixed format** such as turning tickets into JSON, even the
  smallest model scored 20 of 20 after a few minutes of training.

The details are in [Choosing a model
size](https://dragonfarm.dev/articles/model-sizes.md).

## What it does not do

- Questions that need every row of a spreadsheet (“which year had the
  highest margin?”) are better answered in R, on the data.
- Scanned pages need OCR first, and numbers inside charts are lost.
- Small models trained on a few hundred examples can become confident
  when they should not be. Review the training questions, and prefer a
  larger model for answering.
- These numbers come from a handful of documents, not yours. Try it on
  yours.

## Try it

dragonfarm reaches CRAN in November. Until then, get it from
[R-universe](https://tejas4patel.r-universe.dev/dragonfarm), which
builds it for Windows, Mac, and Linux. Then open the app with
[`dragon_app()`](https://dragonfarm.dev/reference/dragon_app.md), or
follow the [quickstart](https://dragonfarm.dev/articles/quickstart.md).

dragonfarm is MIT licensed. Issues, documents that break it, and pull
requests are welcome at
[github.com/tejas4patel/dragonfarm](https://github.com/tejas4patel/dragonfarm),
and there are a few [good first
issues](https://github.com/tejas4patel/dragonfarm/labels/good%20first%20issue)
to start from.
