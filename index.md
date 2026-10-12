# Fine-tune a language model from R. In minutes.

R package · on CRAN · MIT licensed

Drop in a table, drag its columns into Prompt and Response, press Train.
dragonfarm teaches a small model your format and your domain, on your
own GPU or a free cloud one.

`install.packages("dragonfarm")`

Copy

[Get started](https://dragonfarm.dev/articles/quickstart.md) [View on
GitHub](https://github.com/tejas4patel/dragon-farm)

![](data:image/svg+xml;base64,PHN2ZyBpZD0iZGYtc3RlcHBlciIgcm9sZT0iaW1nIiBhcmlhLWxhYmVsPSJUaGUgc2l4IHN0ZXBzOiBEYXRhLCBNYXAsIE1vZGVsLCBUcmFpbiwgTW9uaXRvciwgVHJ5IGl0Ij48L3N2Zz4=)

*dragon_app()*

![Step 1, Data: the example support tickets loaded into the
app](demo/01-data.png)![Step 2, Map: subject and body dragged into the
Prompt slot, reply into Response](demo/02-map.png)![Step 3, Model: a
base model chosen and the GPU detected](demo/03-model.png)![Step 4,
Train: training settings and the Start training
button](demo/04-train.png)![Step 5, Monitor: the loss curve of a
finished run](demo/05-monitor.png)![Step 6, Try it: the fine-tuned and
base model replies side by side](demo/06-compare.png)

Same model, same ticket

## Teach it your house style.

A 0.5B-parameter model, before and after training on 190 example support
tickets. This ticket was not in the training data. It is the median of
the 10 held-out tickets by word overlap with the reference reply, and
both replies are at temperature 0.

**Ticket**Lumen bulb pack arrived damaged. Opened my Lumen bulb pack
today and the casing is split. The packaging looked fine from the
outside so it must have happened before shipping.

Base modelI’m sorry to hear that your Lumen bulb pack has been damaged.
It’s important to take any damage seriously and report it to the
manufacturer or seller as soon as possible. Here are some steps you can
follow: 1. **Contact the Manufacturer**: Reach out to the company that
sold you the Lumen bulb pack. They may be able to provide a replacement
or offer a repair service. 2. **Report the Damage**: … (shortened)

After fine-tuningI’m sorry your Lumen bulb pack arrived damaged. We will
replace it at no cost. Please reply with a photo of the damage and one
of the shipping label so we can file the carrier claim on our side. As
soon as we have those, we ship a replacement Lumen bulb pack with a
prepaid return label for the damaged unit. Usually a business day after
the return is scanned in.Policy and tone are right. The last sentence
mixes in a detail from another ticket type (the real policy is two
business days), which is why small models still need review.

The example tickets are synthetic and built from templates, so this
shows a model picking up a house style and policy, not open-ended
reliability. Use your own data and check the output before relying on
it.

Three ways in

## Start where you’re comfortable.

Everything the app does is also an R function, and every run is a plain
folder of files you can inspect.

Code

### Five lines

Map your columns, train, generate.

    library(dragonfarm)
    run <- dragon_dataset(dragon_example_data()) |>
      dragon_map(prompt = "{subject}\n\n{body}",
                 response = "reply") |>
      dragon_train("Qwen/Qwen2.5-0.5B-Instruct",
                   wait = TRUE)
    dragon_generate(run,
      "My thermostat keeps dropping off Wi-Fi.")

App

### Drag and drop

Six numbered steps, from loading a table to comparing against the base
model. No code needed.

    library(dragonfarm)
    dragon_app()

Cloud

### No GPU? No problem.

Send the run to a free Colab or Kaggle GPU and bring the adapter home.
Colab trains the example in about four minutes.

    run <- dragon_bundle(tickets,
      "Qwen/Qwen2.5-0.5B-Instruct")
    dragon_remote(run, "colab")
    dragon_import(run, "results.zip")

Go further

## When one pass isn’t enough.

Preference tuning, reinforcement learning with rewards you can check,
judges, chat, and publishing to the Hugging Face Hub are all in the box.

[](https://dragonfarm.dev/articles/post-training-loop.md)

### Fine-tune, judge, prefer, repeat

DPO and ORPO on top of a fine-tuned run, with a judge that checks the
result.

[](https://dragonfarm.dev/articles/reinforcement-learning.md)

### Rewards you can check

GRPO with exact, numeric, JSON, length, and test-runner rewards.

[](https://dragonfarm.dev/reference/index.md)

### Every function, documented

The full reference, from `dragon_check()` to `dragon_publish()`.

## Your first fine-tune is ten minutes away.

Install the package, run
[`dragon_check()`](https://dragonfarm.dev/reference/dragon_check.md),
and open the app. The first run sets up Python for you.

`install.packages("dragonfarm")`

Copy

[Get started](https://dragonfarm.dev/articles/quickstart.md)

[CRAN](https://CRAN.R-project.org/package=dragonfarm)[GitHub](https://github.com/tejas4patel/dragon-farm)[News](https://dragonfarm.dev/news/index.md)[Report
an issue](https://github.com/tejas4patel/dragon-farm/issues)
