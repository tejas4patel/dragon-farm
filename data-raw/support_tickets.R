# Generates inst/extdata/support_tickets.jsonl: 200 synthetic support tickets
# for a fictional smart-home company. Deterministic. Run from the package root:
#   Rscript data-raw/support_tickets.R

set.seed(20260913)

glue_fill <- function(tpl, p) gsub("{p}", p, tpl, fixed = TRUE)

products <- c("Ember thermostat", "Lumen bulb pack", "Sentry doorbell", "Breeze air purifier", "Nook speaker")

issues <- list(
  list(
    key = "wifi",
    subjects = c("{p} keeps dropping off Wi-Fi", "{p} won't connect to my network", "Constant disconnects on {p}"),
    bodies = c(
      "My {p} connects fine for a few hours and then drops off the network. I have to power cycle it to get it back. Router is a fairly new mesh system.",
      "I've tried setting up my {p} three times and it never gets past the Wi-Fi step. The app just says 'connection failed'. My phone is on the same 2.4 GHz network.",
      "Since last week the {p} disconnects several times a day. Nothing changed on my end. Other devices on the network are fine."
    ),
    reply = "Thanks for the details. Wi-Fi drops on the {p} are almost always a 2.4 GHz band-steering issue with mesh routers. Please try these steps: (1) In your router app, create a dedicated 2.4 GHz network or temporarily disable band steering. (2) Hold the reset button on the {p} for 10 seconds until the light blinks amber. (3) Set it up again in the app on that 2.4 GHz network. If it still drops after 24 hours, reply with your router model and we will escalate to our network team."
  ),
  list(
    key = "billing",
    subjects = c("Charged twice for {p}", "Invoice total is wrong", "Unexpected charge on my card"),
    bodies = c(
      "I ordered one {p} but my card statement shows two charges of the same amount on the same day. Order number is in my account.",
      "The invoice for my {p} shows a higher total than the price on the checkout page. Looks like tax was applied twice.",
      "I see a charge from you that I don't recognize. I only bought a {p} last month and that was already paid."
    ),
    reply = "Sorry about the confusion with your {p} charge. I've looked at the order on our side. When a payment is authorized and then captured, some banks show both as separate pending lines for 2 to 3 business days before the authorization drops off. If both charges are still showing after 3 business days, reply here with the last four digits of the card and the order number and we will refund the duplicate within one business day. Either way, you will only ever be charged once for the {p}."
  ),
  list(
    key = "damaged",
    subjects = c("{p} arrived damaged", "Broken {p} in the box", "Package was crushed"),
    bodies = c(
      "The box for my {p} arrived crushed on one corner and the device has a crack across the front. Haven't tried powering it on.",
      "Opened my {p} today and the casing is split. The packaging looked fine from the outside so it must have happened before shipping.",
      "My {p} was delivered with visible damage and a rattling sound inside. I'd like a replacement."
    ),
    reply = "I'm sorry your {p} arrived damaged. We will replace it at no cost. Please reply with a photo of the damage and one of the shipping label so we can file the carrier claim on our side. As soon as we have those, we ship a replacement {p} with a prepaid return label for the damaged unit. You do not need to wait for the return to arrive before the new one ships. Typical turnaround is 2 business days."
  ),
  list(
    key = "app",
    subjects = c("App won't show my {p}", "{p} missing from the app after update", "App crashes when I open the {p} page"),
    bodies = c(
      "After the latest app update my {p} no longer appears in the device list. The device itself still works on its own.",
      "The app crashes every time I tap on my {p}. Reinstalling didn't help. iPhone, latest iOS.",
      "My {p} shows as offline in the app but it is clearly working. Restarting the phone did nothing."
    ),
    reply = "Thanks for reporting this. We are aware of a sync issue in the current app release that can hide a {p} or show it offline. The fix is in version 4.12.2, which is rolling out now. In the meantime: sign out of the app, force close it, sign back in, and pull down on the device list to refresh. That re-syncs the {p} for most people. If it is still missing after updating to 4.12.2, reply with the email on your account and we will re-link the device from our side."
  ),
  list(
    key = "return",
    subjects = c("How do I return my {p}?", "Want to return {p}, changed my mind", "Return window for {p}"),
    bodies = c(
      "I bought a {p} two weeks ago and it's not what I need. Is it still returnable and how do I start?",
      "I'd like to return the {p} I ordered. It is unopened. What is the process?",
      "Can I return my {p} if I've already set it up? It works but I don't use it."
    ),
    reply = "Yes, the {p} can be returned within 30 days of delivery, opened or unopened, for a full refund. To start: go to Orders in your account, pick the {p} order, and choose Start a return. You'll get a prepaid label to print or show at any drop-off point. Refunds go back to the original payment method within 5 business days of the return being scanned in. If you set the {p} up already, please remove it from the app first so the next owner can pair it."
  ),
  list(
    key = "warranty",
    subjects = c("{p} stopped working after 8 months", "Is my {p} under warranty?", "{p} dead, no lights at all"),
    bodies = c(
      "My {p} just stopped responding. No lights, no sound, nothing. Bought it about 8 months ago.",
      "The {p} I got last year has started rebooting itself every few minutes. Is this covered?",
      "Is there a warranty on the {p}? Mine has become unreliable and I'd rather not buy another one."
    ),
    reply = "Sorry to hear the {p} has failed. Every {p} carries a 2-year limited warranty from the delivery date, so you are covered. To start a claim, reply with the order number or the serial number on the base of the unit and a short description of the symptoms. We'll send a replacement {p} with a prepaid label for the faulty one. You keep using the original until the replacement arrives, if it still works at all."
  ),
  list(
    key = "howto",
    subjects = c("How do I schedule my {p}?", "Can the {p} work with voice assistants?", "Setting up automations for {p}"),
    bodies = c(
      "I'd like my {p} to turn on at sunset and off at 11 pm. Is that possible without a third-party app?",
      "Does the {p} work with Alexa or Google Home? I can't find it in the skill list.",
      "Can I trigger the {p} when my doorbell rings? I have both devices."
    ),
    reply = "You can do this from the app without any third-party tools. Open the {p}, tap Automations, then Add. Choose a trigger (a time, sunrise or sunset, or an event from another device such as the doorbell), then choose what the {p} should do. Save it and it runs on the device itself, so it keeps working even when your phone is away. For voice control, enable the Nook Home skill in Alexa or the Nook Home action in Google Home and the {p} will appear automatically after you link your account."
  )
)

n_target <- 200
rows <- list()
i <- 0
while (length(rows) < n_target) {
  for (iss in issues) {
    if (length(rows) >= n_target) break
    p <- sample(products, 1)
    subj <- glue_fill(sample(iss$subjects, 1), p)
    body <- glue_fill(sample(iss$bodies, 1), p)
    rows[[length(rows) + 1]] <- list(
      id = sprintf("T-%04d", length(rows) + 1),
      product = p,
      category = iss$key,
      subject = subj,
      body = body,
      reply = glue_fill(iss$reply, p)
    )
  }
}

out <- file.path("inst", "extdata", "support_tickets.jsonl")
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
con <- file(out, open = "w", encoding = "UTF-8")
for (r in rows) writeLines(as.character(jsonlite::toJSON(r, auto_unbox = TRUE)), con)
close(con)
cat("wrote", length(rows), "rows to", out, "\n")
