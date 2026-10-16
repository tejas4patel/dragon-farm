# No GPU? Train in the cloud

Google Colab has been tested end to end with this workflow (a free T4
trains the example in about four minutes). Kaggle, Lightning AI, and
RunPod use the same notebook.

The run directory is the whole contract between R and the trainer, so a
run can be trained on any machine with a GPU and its results copied
back.
[`dragon_bundle()`](https://dragonfarm.dev/reference/dragon_bundle.md)
zips the run,
[`dragon_remote()`](https://dragonfarm.dev/reference/dragon_remote.md)
opens a provider with the dragonfarm notebook and prints the steps, and
[`dragon_import()`](https://dragonfarm.dev/reference/dragon_import.md)
puts the trained adapter into place. Nothing else changes:
[`dragon_generate()`](https://dragonfarm.dev/reference/dragon_generate.md)
and [`dragon_merge()`](https://dragonfarm.dev/reference/dragon_merge.md)
work on the imported run as if it had trained locally.

``` r

run <- dragon_dataset(dragon_example_data()) |>
  dragon_map(prompt = "{subject}\n\n{body}", response = "reply") |>
  dragon_bundle("Qwen/Qwen2.5-0.5B-Instruct")

dragon_remote(run, "colab")   # opens Colab with the notebook, prints the steps
# ... upload the zip it names, Run all, download dragonfarm-results-<id>.zip ...
dragon_import(run, "~/Downloads/dragonfarm-results-<id>.zip")
```

| Provider | Cost | What the link opens |
|----|----|----|
| Google Colab | Free tier with a T4; paid tiers for longer sessions | The notebook, directly |
| Kaggle | Free: about 30 GPU hours a week (T4 x2 or P100) | The notebook, directly |
| Lightning AI | Free monthly credits, then pay as you go | The dragonfarm repo in a new Studio |
| RunPod | Pay per hour, wide choice of GPUs | The RunPod console |

The app has the same path: the Train panel’s “No GPU here?” section
prepares the bundle and gives you the download and the provider link,
and the Monitor panel imports the results zip.
[`dragon_check()`](https://dragonfarm.dev/reference/dragon_check.md)
points here when it finds no GPU, and a run that failed locally for lack
of memory can be sent to the cloud as is with `dragon_remote(run, ...)`.
