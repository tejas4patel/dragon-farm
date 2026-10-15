<div class="df-landing">
<section class="df-hero">
<div class="df-wrap">
<p class="df-eyebrow"><span class="df-dot"></span>R package · on CRAN · MIT licensed</p>
<h1 class="df-h1">Fine-tune a language model<br>from R. <span class="df-grad">In minutes.</span></h1>
<p class="df-lede">Drop in your documents, ask them questions with cited sources, then teach a model from them: a 7B fits an 8 GB laptop GPU. Or start from a table of prompts and replies. dragonfarm runs on your own GPU or a free cloud one, and the model you get is yours.</p>
<div class="df-cta">
<div class="df-install"><code>install.packages(&quot;dragonfarm&quot;)</code><button class="df-copy" type="button" data-copy="install.packages(&quot;dragonfarm&quot;)">Copy</button></div>
<a class="df-btn df-btn-primary" href="articles/quickstart.html">Get started</a>
<a class="df-btn df-btn-ghost" href="https://github.com/tejas4patel/dragon-farm">View on GitHub</a>
</div>
<div class="df-stage">
<svg id="df-stepper" role="img" aria-label="The six steps: Documents, Ask, Teach, Train, Monitor, Try it"></svg>
<div class="df-screen">
<div class="df-chrome"><span></span><span></span><span></span><em>dragon_app()</em></div>
<div class="df-shots">
<img class="on" src="demo/01-documents.png" alt="Step 1, Documents: a set of PDFs and pages read into chunks">
<img src="demo/02-ask.png" alt="Step 2, Ask: an answer with numbered sources under it">
<img src="demo/03-teach.png" alt="Step 3, Teach: generated questions grouped by chunk, with checkboxes and the reasons for rejected ones">
<img src="demo/04-train.png" alt="Step 4, Train: training settings with the training rows built from the reviewed questions">
<img src="demo/05-monitor.png" alt="Step 5, Monitor: the loss curve of a finished run">
<img src="demo/06-tryit.png" alt="Step 6, Try it: the fine-tuned and base model replies side by side, each with sources">
</div>
</div>
<p class="df-stagecap" id="df-cap" aria-live="polite"></p>
</div>
</div>
</section>
<section class="df-section">
<div class="df-wrap df-reveal">
<p class="df-kicker">Same model, same ticket</p>
<h2 class="df-h2">Teach it your house style.</h2>
<p class="df-sub">A 0.5B-parameter model, before and after training on 190 example support tickets. This ticket was not in the training data. It is the median of the 10 held-out tickets by word overlap with the reference reply, and both replies are at temperature 0.</p>
<div class="df-ticket"><b>Ticket</b>Lumen bulb pack arrived damaged. Opened my Lumen bulb pack today and the casing is split. The packaging looked fine from the outside so it must have happened before shipping.</div>
<div class="df-ba">
<div class="df-reply"><span class="df-who">Base model</span>I'm sorry to hear that your Lumen bulb pack has been damaged. It's important to take any damage seriously and report it to the manufacturer or seller as soon as possible. Here are some steps you can follow: 1. <strong>Contact the Manufacturer</strong>: Reach out to the company that sold you the Lumen bulb pack. They may be able to provide a replacement or offer a repair service. 2. <strong>Report the Damage</strong>: &hellip; (shortened)</div>
<div class="df-reply after"><span class="df-who">After fine-tuning</span>I'm sorry your Lumen bulb pack arrived damaged. We will replace it at no cost. Please reply with a photo of the damage and one of the shipping label so we can file the carrier claim on our side. As soon as we have those, we ship a replacement Lumen bulb pack with a prepaid return label for the damaged unit. Usually a business day after the return is scanned in.<span class="df-note">Policy and tone are right. The last sentence mixes in a detail from another ticket type (the real policy is two business days), which is why small models still need review.</span></div>
</div>
<p class="df-fine">The example tickets are synthetic and built from templates, so this shows a model picking up a house style and policy, not open-ended reliability. Use your own data and check the output before relying on it.</p>
</div>
</section>
<section class="df-section alt">
<div class="df-wrap df-reveal">
<p class="df-kicker">Three ways in</p>
<h2 class="df-h2">Start where you're comfortable.</h2>
<p class="df-sub">Documents first, a table if you have one, the cloud if you have no GPU. Everything the app does is also an R function, and every run is a plain folder of files you can inspect.</p>
<div class="df-grid3 df-ways">
<div class="df-card"><span class="df-tag">Documents</span><h3>Ask, then teach</h3><p>Drop in files or pages, ask with cited sources, write and review training questions, fine-tune.</p>
<pre><code>docs &lt;- dragon_documents("policies/")
dragon_ask(docs, "How long is the
  return window?")
qa &lt;- dragon_questions(docs)   # review
run &lt;- dragon_train(
  dragon_questions_dataset(qa, docs),
  "Qwen/Qwen2.5-0.5B-Instruct")</code></pre></div>
<div class="df-card"><span class="df-tag">App</span><h3>No code needed</h3><p>Opens on Documents: drop files, ask, review the generated questions, train, try, chat. Have a table instead? One link switches to the drag-and-drop route.</p>
<pre><code>library(dragonfarm)
dragon_app()</code></pre></div>
<div class="df-card"><span class="df-tag">Cloud</span><h3>No GPU? No problem.</h3><p>Send the run to a free Colab or Kaggle GPU and bring the adapter home. Colab trains the example in about four minutes.</p>
<pre><code>run &lt;- dragon_bundle(tickets,
  "Qwen/Qwen2.5-0.5B-Instruct")
dragon_remote(run, "colab")
dragon_import(run, "results.zip")</code></pre></div>
</div>
</div>
</section>
<section class="df-section">
<div class="df-wrap df-reveal">
<p class="df-kicker">Go further</p>
<h2 class="df-h2">When one pass isn't enough.</h2>
<p class="df-sub">Preference tuning, reinforcement learning with rewards you can check, judges, chat, and publishing to the Hugging Face Hub are all in the box.</p>
<div class="df-grid3">
<a class="df-card" href="articles/post-training-loop.html" style="text-decoration:none"><h3>Fine-tune, judge, prefer, repeat</h3><p>DPO and ORPO on top of a fine-tuned run, with a judge that checks the result.</p></a>
<a class="df-card" href="articles/reinforcement-learning.html" style="text-decoration:none"><h3>Rewards you can check</h3><p>GRPO with exact, numeric, JSON, length, and test-runner rewards.</p></a>
<a class="df-card" href="reference/index.html" style="text-decoration:none"><h3>Every function, documented</h3><p>The full reference, from <code>dragon_check()</code> to <code>dragon_publish()</code>.</p></a>
</div>
</div>
</section>
<section class="df-final">
<div class="df-wrap df-reveal">
<h2 class="df-h2">Your first fine-tune is ten minutes away.</h2>
<p>Install the package, run <code>dragon_check()</code>, and open the app. The first run sets up Python for you.</p>
<div class="df-cta">
<div class="df-install"><code>install.packages(&quot;dragonfarm&quot;)</code><button class="df-copy" type="button" data-copy="install.packages(&quot;dragonfarm&quot;)">Copy</button></div>
<a class="df-btn df-btn-primary" href="articles/quickstart.html">Get started</a>
</div>
<div class="df-links"><a href="https://CRAN.R-project.org/package=dragonfarm">CRAN</a><a href="https://github.com/tejas4patel/dragon-farm">GitHub</a><a href="news/index.html">News</a><a href="https://github.com/tejas4patel/dragon-farm/issues">Report an issue</a></div>
</div>
</section>
</div>
