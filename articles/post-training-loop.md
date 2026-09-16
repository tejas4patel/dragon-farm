# The post-training loop: fine-tune, judge, prefer, repeat

A fine-tune teaches a small model what a good reply looks like. It
rarely makes the model good on its own. What does is the loop the labs
run at large scale: train, look hard at the output, turn what you
learned into more data, train again. This vignette runs that loop on a
support-ticket dataset with a 0.5B model. Every step is one function,
and every step leaves a run directory you can inspect, compare, and
continue from.

## The shape of the loop

1.  **Fine-tune** on prompt and response rows
    ([`dragon_train()`](https://dragonfarm.dev/reference/dragon_train.md)).
2.  **Measure** with held-out loss, task metrics, and a judge model
    ([`dragon_evaluate()`](https://dragonfarm.dev/reference/dragon_evaluate.md),
    [`dragon_judge()`](https://dragonfarm.dev/reference/dragon_judge.md)).
3.  **Make preference data** without hand labelling: sample the model’s
    own replies and let a judge rank them
    ([`dragon_synthesize_pairs()`](https://dragonfarm.dev/reference/dragon_synthesize_pairs.md)).
4.  **Preference-optimize** on those pairs, starting from the fine-tuned
    run
    ([`dragon_prefer()`](https://dragonfarm.dev/reference/dragon_prefer.md)).
5.  **Compare** the stages
    ([`dragon_compare()`](https://dragonfarm.dev/reference/dragon_compare.md)),
    then go around again.

Each stage’s run becomes the starting point of the next. Passing a run
where a model id is expected folds its adapters into the weights before
the new stage adds its own.

## 1. Fine-tune

``` r

library(dragonfarm)

tickets <- dragon_dataset(dragon_example_data()) |>
  dragon_map(prompt = "{subject}\n\n{body}", response = "reply",
             system = "You are a concise, warm support agent for a smart-home company.")

sft <- dragon_train(tickets, "Qwen/Qwen2.5-0.5B-Instruct", wait = TRUE)
```

If the data is thin, let a stronger model write the replies first.
[`dragon_synthesize()`](https://dragonfarm.dev/reference/dragon_synthesize.md)
asks a teacher to answer your prompts and returns a mapped dataset:

``` r

persona <- "You are a concise, warm support agent for a smart-home company."
teacher <- dragon_llm_anthropic(system = persona)   # reads ANTHROPIC_API_KEY
synth <- dragon_synthesize(tickets, teacher, system = persona)
sft <- dragon_train(synth, "Qwen/Qwen2.5-0.5B-Instruct", wait = TRUE)
```

Any model can be the teacher: an `ellmer` chat through
[`dragon_llm_ellmer()`](https://dragonfarm.dev/reference/dragon_llm_anthropic.md),
a local model by id, a finished run, or any function from prompts to
replies.

## 2. Measure

Held-out loss says the model learned the data. It does not say the
replies got better. Two more views:

``` r

dragon_evaluate(sft, metrics = c("token_f1", "length_ratio"))
```

Task metrics are deterministic checks over every held-out row: exact
match, containment, token overlap, JSON validity, numeric answers,
length. Add your own as functions of `(generated, reference, prompt)`.

``` r

judge <- dragon_judge_anthropic(model = "claude-sonnet-5")
dragon_judge(sft, judge = judge,
             rubric = "Reward replies that give concrete next steps and stay under 120 words.")
```

A judge scores each reply from 1 to 10 against a rubric. With
`against =`, it compares two models pairwise instead. Each pair is asked
twice with the replies swapped, and only consistent verdicts count, so a
judge that favours whichever answer comes first produces ties rather
than wins. A local model works as a judge too:
`judge = "Qwen/Qwen2.5-1.5B-Instruct"`.

## 3. Make preference pairs from the model’s own replies

Preference optimization needs, per prompt, a better and a worse reply.
You do not have to write them:

``` r

pairs <- dragon_synthesize_pairs(
  dragon_prompts(sft, "train", n = 200),   # prompts the run already has
  student = sft, judge = judge,
  n_samples = 4, min_gap = 2
)
pairs
```

The fine-tuned run answers each prompt four times at a non-zero
temperature, the judge scores every sample, and the best and worst
become chosen and rejected. Prompts whose samples are too close or
identical are dropped. The result is written under `synth/` in the runs
directory and returned mapped, ready for the next stage.

If a teacher is clearly stronger than the student, skip the judge: pass
`teacher = teacher` and the teacher’s reply is chosen, the student’s
rejected.

## 4. Preference-optimize on top of the fine-tune

``` r

dpo <- dragon_prefer(pairs, sft, method = "dpo", beta = 0.1, wait = TRUE)
dragon_evaluate(dpo)   # preference accuracy and reward margin on held-out pairs
```

`sft` as the model means the DPO stage starts from the fine-tuned
weights. Two methods are available. DPO is the standard and wants a
fine-tuned start. ORPO folds preference into the supervised loss, needs
no reference model, and works from a base model directly. `beta` is how
hard the model is pushed; 0.1 is a sensible start for both.

## 5. Compare, then go around again

``` r

dragon_judge(dpo, against = "base", judge = judge)   # DPO run versus the fine-tune it started from
dragon_compare()                                     # every run, side by side
```

If the DPO run wins the pairwise judgement and the metrics did not
regress, it becomes the new student: sample from it, judge, make pairs,
run DPO again. Two or three rounds are typical before the gains flatten.

## The same loop in one call

``` r

p <- dragon_pipeline("Qwen/Qwen2.5-0.5B-Instruct", list(
  dragon_step_train(tickets),
  dragon_step_synthesize_pairs(prompts = "train", n = 200, judge = judge),
  dragon_step_prefer(method = "dpo"),
  dragon_step_judge(against = "base", judge = judge),
  dragon_step_evaluate(metrics = c("token_f1", "length_ratio"))
), background = TRUE)

dragon_pipeline_status(p)   # while it runs
dragon_compare(p)           # when it is done
```

The pipeline writes a record after every step, so it can be watched from
the app’s Pipeline panel or another session.

## Talk to the result

``` r

chat <- dragon_chat(dpo, system = persona)
chat$say("My thermostat keeps dropping off Wi-Fi.")
chat$say("I tried that already. What else?")   # the model sees the first exchange
```

Conversations keep their history, so the model has context. The local
worker keeps the model loaded between turns. To serve the model
somewhere faster than the training machine, `dragon_serve_ollama(dpo)`
registers it with Ollama and returns a backend;
[`dragon_backend_server()`](https://dragonfarm.dev/reference/dragon_backend.md)
points at any OpenAI-compatible endpoint.

## When this loop is the wrong tool

Preference optimization moves a model towards a judge’s taste. When the
goal is something you can check, a correct number, valid JSON, a format,
a length budget, reinforcement learning with verifiable rewards is the
better fit. See the reinforcement learning vignette.
