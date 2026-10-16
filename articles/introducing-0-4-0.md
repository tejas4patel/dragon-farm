# Ask your documents. Then teach a model.

![The dragonfarm dragon: a friendly orange dragon with small wings and
one tiny fang](../dragon.svg)

dragonfarm 0.4.0 is here, and it hatches from your documents. Feed it
PDFs, Word files, and web pages, ask it anything, and it answers in full
from what it read. When you want more, it turns the same documents into
homework, studies, and fine-tunes a model that knows your material. All
from R, on your own machine, free. Raise your own dragon.

## Ask it anything

I fed it Costco’s 2024 annual report, all 76 pages, and asked two
questions:

Question

Who is Costco’s independent registered public accounting firm?

Costco’s independent registered public accounting firm is KPMG LLP,
located in Seattle, WA.

Question

What was net cash used in investing activities in fiscal 2024?

Net cash used in investing activities in fiscal 2024 totaled \$4,409
million.

Of thirteen factual questions about the report, it got twelve right. The
thirteenth was a figure printed inside a map, and the dragon said the
report does not cover it rather than making something up. Good dragon.

## Six steps, one app

![The app, step by step: drop in documents, ask them with sources,
review generated questions, train, watch the loss, compare against the
base model.](../demo/dragonfarm-demo.gif)

The app, step by step: drop in documents, ask them with sources, review
generated questions, train, watch the loss, compare against the base
model.

1.  **Documents.** Feed it PDFs, Word files, web pages, spreadsheets, or
    a whole folder.
2.  **Ask.** Get full answers drawn from your documents.
3.  **Teach.** It writes its own practice questions and answers from
    your documents. You keep the good ones.
4.  **Train.** It studies the pairs you kept.
5.  **Monitor.** Watch it learn.
6.  **Try it.** Put the trained dragon next to the wild one, both
    answering from your documents.

Your documents never leave your machine. No GPU? dragonfarm sends the
training to a free Colab or Kaggle GPU and brings the dragon home.

## What you get

- **Full answers, in plain words.** It reads the relevant parts of your
  documents and answers the question, not just points you at a page.
- **An honest “not covered”.** Ask about something the documents do not
  contain and it says so.
- **Training data you did not have to write.** Most people who want to
  fine-tune have documents, not a table of questions and answers. The
  dragon writes the table; you mark it.
- **A model that is yours.** It runs on your machine and loads anywhere
  with standard tools. No subscription, no leash.
- **The right size for your nest.** An 8 GB laptop GPU raises a 7B
  dragon; smaller cards and CPUs get a smaller one, picked for you.

## How big a dragon do you need?

The same questions, the same documents, four sizes, one 8 GB laptop GPU,
before any training:

| Dragon | Annual report: right of 23 | R manuals: right of 32 | Said “not covered” when true, of 20 |
|----|----|----|----|
| Hatchling (0.5B) | 17 | 19 | 16 |
| Drake (1.5B) | 19 | 28 | 20 |
| Wyvern (3B) | 21 | 30 | 20 |
| Elder (7B) | 23 | 32 | 20 |

And after training:

- **The Elder, trained on R’s manuals**, stayed exactly as accurate and
  picked up manners: shorter, tidier answers.
- **On support tickets**, a dragon trained this way recalled 89 percent
  of the policy facts on tickets it had never seen, against 68 percent
  for ordinary fine-tuning. When the policy changed after training, it
  followed the new version in 88 percent of answers. Old dragon, new
  tricks.
- **For a fixed format** such as turning tickets into JSON, even the
  Hatchling scored 20 of 20 after a few minutes of training.

The details are in [Choosing a model
size](https://dragonfarm.dev/articles/model-sizes.md).

## Where dragons fear to tread

- Questions that need every row of a spreadsheet (“which year had the
  highest margin?”) are better answered in R, on the data.
- Scanned pages need OCR first, and numbers inside charts are lost.
- Small dragons trained on a few hundred examples can get cocky. Review
  the practice questions, and let a bigger dragon do the answering.
- These numbers come from a handful of documents, not yours. Try it on
  yours.

## Hatch one

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
for new dragon keepers.
