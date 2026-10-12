# Did it help? Metrics, judges, and comparisons

Held-out loss says a stage trained. It does not say the replies got
better. Three tools answer that:

``` r

# Deterministic checks over every held-out row
dragon_evaluate(dpo, metrics = c("exact", "token_f1", "json_valid"))

# A stronger model as judge: did DPO beat the fine-tuned run it started from?
dragon_judge(dpo, against = "base", judge = dragon_judge_anthropic())
#> dpo vs sft on 20 prompts: wins 65% · ties 25% · losses 10%

# Or absolute scores against your own rubric, with a local judge
dragon_judge(sft, judge = "Qwen/Qwen2.5-1.5B-Instruct",
             rubric = "Reward concrete next steps; penalise anything over 120 words.")

# Everything the package knows about every run, side by side
dragon_compare()
```

Pairwise judging asks each question twice with the replies swapped, so a
judge that favours whichever answer comes first yields ties, not wins.
[`dragon_judge_anthropic()`](https://dragonfarm.dev/reference/dragon_llm_anthropic.md)
reads `ANTHROPIC_API_KEY`;
[`dragon_judge_ellmer()`](https://dragonfarm.dev/reference/dragon_llm_anthropic.md)
accepts any `ellmer` chat for other providers.
