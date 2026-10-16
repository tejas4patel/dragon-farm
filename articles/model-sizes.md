# Choosing a model size

Does a smaller model cost you quality? We measured it. Four sizes of the
same model family, Qwen 2.5 Instruct at 0.5B, 1.5B, 3B, and 7B
parameters, ran the same tasks on the same laptop: an RTX 4060 with 8
GB. The 7B was loaded in 4-bit, as it must be to fit. Everything else
was identical: the same documents, the same retrieved excerpts, the same
questions, and for fine-tuning the same training rows.

## The short answer

| If you want to | Use | Because |
|----|----|----|
| Answer questions from documents | 7B in 4-bit if you have an 8 GB NVIDIA card; otherwise 3B | Smaller models answer many questions but make up answers to the rest |
| Write training questions from documents | 7B | It kept 104 of 120 questions, and every one we checked was right |
| Fine-tune on your documents | 3B or 7B | Only these learned to say “the documents do not cover it” |
| Fine-tune a fixed format (JSON, labels, a house style) | 0.5B to 1.5B | They reach the same score in minutes |

dragonfarm already picks the answering model for your hardware: a 7B in
4-bit at 8 GB and up, a 3B at 6 to 8 GB, a 1.5B below that and on a CPU.
[`dragon_check()`](https://dragonfarm.dev/reference/dragon_check.md)
says which.

## 1. Answering from documents, before any training

Each model answered from the four most relevant excerpts. Two test sets
had known answers: 23 questions about Costco’s 2024 annual report (a
76-page PDF, mostly figures from tables) and 32 questions about R’s own
manuals. Ten more questions were about things the documents do not
contain, such as a hot-dog sales figure or the default port of RStudio
Server; the right reply to those is to say so.

| Model | Costco figures right | R questions right | Wrong or empty, of those 55 | Declined the 10 it could not answer | Seconds per answer |
|----|----|----|----|----|----|
| 0.5B | 12 of 23 | 22 of 32 | 21 | 0 | 0.3 |
| 1.5B | 18 of 23 | 27 of 32 | 10 | 5 | 0.7 |
| 3B | 19 of 23 | 24 of 32 | 11 | 10 | 2.1 |
| 7B, 4-bit | 20 of 23 | 31 of 32 | 1 | 10 | 4.7 |

“Right” means the answer contained the correct figure or function name.
That is a lenient test: small models often named the right function with
a wrong detail around it.

The columns that matter most are “wrong or empty” and “declined”. The 7B
was wrong once in 55 answers; when it could not find a figure it said
so, three times on figures that were in the report. The other sizes were
wrong or empty ten to twenty times as often. And the 0.5B answered every
question it could not know: it gave Costco’s CEO a home address. The
1.5B did the same half the time, and named a Costco mobile game the
report never mentions. That is the real cost of a small model on
documents: not fewer answers, but answers you cannot tell from the right
ones.

The 3B had its own failure: on 6 of 65 questions it replied with nothing
but a citation marker, “\[1\]”.
[`dragon_ask()`](https://dragonfarm.dev/reference/dragon_ask.md) now
asks once more when that happens. With that retry the 3B left no reply
empty and answered 28 of the 32 R questions instead of 24, with the
Costco and declined columns unchanged.

## 2. Writing training questions

Each model wrote three questions and answers from each of the same 40
chunks of R’s manuals. The package’s filters then dropped the weak
pairs, and we graded twelve of each model’s kept pairs by hand against
the source text, without knowing which model wrote them.

| Model     | Pairs kept by the filters | Correct, of 12 checked | Minutes |
|-----------|---------------------------|------------------------|---------|
| 0.5B      | 18 of 120                 | 6                      | 2.0     |
| 1.5B      | 51 of 120                 | 11                     | 2.6     |
| 3B        | 82 of 120                 | 10                     | 3.2     |
| 7B, 4-bit | 104 of 120                | 12                     | 3.9     |

Multiply the two and the 7B gives about ten times as many usable pairs
as the 0.5B for twice the time. The 0.5B’s bad pairs were the dangerous
kind: fluent and wrong, such as a keyboard shortcut for resizing the
terminal that does not exist.

## 3. Fine-tuning on your documents

Each size was fine-tuned for three epochs on the same 586
question-and-answer rows, written by the 7B from R’s manuals, with the
retrieved excerpts in every prompt (up to 1,536 tokens). Then each
answered the 32 R questions and the five R questions the manuals do not
cover.

| Model | Training time | Held-out loss | R questions right | Declined the 5 it could not answer |
|----|----|----|----|----|
| 0.5B | 21 min | 0.64 | 27 of 32 | 0 |
| 1.5B | 36 min | 0.48 | 29 of 32 | 0 |
| 3B, 4-bit | 66 min | 0.46 | 30 of 32 | 2 |
| 7B, 4-bit | 4 h 19 min | 0.33 | 30 of 32 | 4 |

Training helped every size answer more questions, and every tuned model
cited a source in almost every reply. But the small models also learned
to cite a source for things the source does not say. The tuned 1.5B
answered “Who won the 2022 football World Cup?” with “France \[5\]”; the
tuned 0.5B gave RStudio Server’s port as 8443 and cited the manual for
it. The tuned 7B said “the documents do not cover it” to four of the
five, and for the fifth pointed to the CRAN task view that the R FAQ
recommends.

So fine-tuning a small model on documents teaches it the house style of
an answer, sources included, without teaching it when to stop. If wrong
answers are costly, train a 3B or 7B, or skip training and answer with
the largest model your card runs.

The cause turned out to be the training data: every training prompt
contained its answer, so the models never saw a case where the right
reply is “the documents do not cover this”.
[`dragon_questions_dataset()`](https://dragonfarm.dev/reference/dragon_questions_dataset.md)
now adds such cases by default, 15 percent extra rows that show a
question with excerpts from another section. Retrained on the same rows
plus those, and tested on 15 questions the manuals do not cover:

| Model | Declined, before | Declined, with “not covered” rows | R questions right, before | after |
|----|----|----|----|----|
| 0.5B | 0 of 15 | 14 of 15 | 27 of 32 | 26 of 32 |
| 1.5B | 0 of 15 | 15 of 15 | 29 of 32 | 25 of 32 |
| 3B, 4-bit | 6 of 15 | 15 of 15 | 30 of 32 | 28 of 32 |

The cost is a few answerable questions declined or answered with a wrong
detail; the gain is that a tuned model now says when it does not know. A
small model still names fewer right details than a large one.

## 4. A fixed format: tickets to JSON

The narrow case looks very different. Each model read a support ticket
and replied with JSON naming the product and the issue category.
Training used 190 example tickets; scoring used 20 held-out ones,
counting a reply right only when both fields matched.

| Model | Untrained, both fields right | Fine-tuned, both fields right | Training time |
|----|----|----|----|
| 0.5B | 10 of 20 | 20 of 20 | 2.6 min |
| 1.5B | 16 of 20 | 20 of 20 | 3.8 min |
| 3B, 4-bit | 17 of 20 | 20 of 20 | 25.5 min |
| 7B, 4-bit | 18 of 20 | 20 of 20 | 24.6 min |

Every size reached a perfect score after training, so the 0.5B is the
right choice here: ten times faster to train than the 3B or the 7B, and
quick to serve. The untrained 7B already got 18 of 20, so for a format
this simple a large model with a good instruction may need no training
at all.

## Fitting a 7B on 8 GB

The 7B trained on the 8 GB card with 4-bit loading, batch size 1, and
gradient checkpointing, peaking at 7.9 GB of the card’s 8. At batch size
4 without checkpointing it failed on the first step. The 3B in 4-bit
peaked at 4.3 GB on the longest document prompts, so it fits a 6 GB
card. In the app, the Training step sets all three when you pick a 7B.
In code:

``` r

run <- dragon_train(ds, "Qwen/Qwen2.5-7B-Instruct",
                    hardware = dragon_hardware(load_in_4bit = TRUE),
                    args = dragon_train_args(batch_size = 1, grad_accum = 16,
                                             gradient_checkpointing = TRUE))
```

4-bit loading needs an NVIDIA GPU. On Apple Silicon or a CPU, the 1.5B
and 3B are the practical choices, and the advice above about declining
unanswerable questions applies with more force.

## How this was measured

- One laptop, an RTX 4060 with 8 GB, Windows 11, one job at a time.
- Answers at temperature 0, four retrieved excerpts, the package’s
  default instruction to answer only from the excerpts and to say when
  they do not cover the question.
- Scoring by pattern: a figure or a function name for answerable
  questions, a phrase such as “do not cover” for the rest. We read every
  answer to check the patterns and widened four that were too strict.
- The ticket set is synthetic, built from templates, so the JSON result
  shows how quickly each size learns a format, not how it copes with
  messy real tickets.
- These are one family of models on a few hundred questions. Measure on
  your own documents before you rely on any of it:
  [`dragon_ask()`](https://dragonfarm.dev/reference/dragon_ask.md) and
  the app’s Try it step make that quick.
