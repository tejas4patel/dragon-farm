# Talk to it, anywhere it runs

Training machines are rarely the right inference machines. Generation
goes through a backend you choose:

``` r

chat <- dragon_chat(run, system = "You are a concise support agent.")
chat$say("My thermostat keeps dropping off Wi-Fi.")
chat$say("I tried that. What else?")        # the model remembers the first exchange

backend <- dragon_serve_ollama(run)          # merge, register with Ollama, done
options(dragonfarm.backend = backend)        # every call now uses Ollama
dragon_generate(run, "Hello")

vllm <- dragon_backend_server("https://my-pod.example.com/v1", model = "me/support-0.5b")
dragon_chat(backend = vllm)$say("Hello")
```

The default backend is a local worker that keeps the last two models
loaded, so judge and synthesis loops stop paying a model load per call.
The app’s Chat panel offers the same choice of backend.

Conversations are also where human feedback comes from. Rate a reply,
fix it, and the verdict is saved;
[`dragon_feedback()`](https://dragonfarm.dev/reference/dragon_feedback.md)
turns the verdicts into data for the next stage:

``` r

chat$rate("down")
chat$regenerate()
chat$rate("up")
chat$edit("Hold the recessed button on the back for ten seconds.")

fb <- dragon_feedback()
better <- dragon_train(fb$sft, dpo, wait = TRUE)      # liked and edited replies, with context
dpo2 <- dragon_prefer(fb$pairs, better, wait = TRUE)  # liked versus disliked replies to the same prompt
```

Whole conversations work as training data too:
[`dragon_conversations()`](https://dragonfarm.dev/reference/dragon_conversations.md)
takes a list of message lists or a JSONL file of them.
