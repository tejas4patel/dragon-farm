# Generates inst/extdata/support_tickets.jsonl: 200 distinct synthetic support
# tickets for a fictional smart-home company, each answered in one of three
# wordings of that issue's policy. Deterministic. Run from the package root:
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
    replies = c(
      "Thanks for the details. Wi-Fi drops on the {p} are almost always a 2.4 GHz band-steering issue with mesh routers. Please try these steps: (1) In your router app, create a dedicated 2.4 GHz network or temporarily disable band steering. (2) Hold the reset button on the {p} for 10 seconds until the light blinks amber. (3) Set it up again in the app on that 2.4 GHz network. If it still drops after 24 hours, reply with your router model and we will escalate to our network team.",
      "Thanks for the details, and sorry for the dropouts. A {p} that keeps leaving the network is usually fighting with band steering on a mesh router. Try this: (1) Give your 2.4 GHz band its own network name in the router app, or switch band steering off for now. (2) Press and hold the reset button on the {p} for 10 seconds, until the light flashes amber. (3) Pair it again in the app, this time on the 2.4 GHz network. Still dropping a day later? Send us your router model and we will pass it to our network team.",
      "Sorry about the connection trouble with your {p}. Mesh routers often cause this because they push devices onto the wrong band, and the {p} connects on 2.4 GHz. Here is what usually fixes it: (1) Create a separate 2.4 GHz network, or turn band steering off for a while. (2) Reset the {p} by holding its button for 10 seconds until you see an amber blink. (3) Set it up again from the app on the 2.4 GHz network. If it drops again within 24 hours, reply with your router model and our network team will take a look."
    )
  ),
  list(
    key = "billing",
    subjects = c("Charged twice for {p}", "Invoice total is wrong", "Unexpected charge on my card"),
    bodies = c(
      "I ordered one {p} but my card statement shows two charges of the same amount on the same day. Order number is in my account.",
      "The invoice for my {p} shows a higher total than the price on the checkout page. Looks like tax was applied twice.",
      "I see a charge from you that I don't recognize. I only bought a {p} last month and that was already paid."
    ),
    replies = c(
      "Sorry about the confusion with your {p} charge. I've looked at the order on our side. When a payment is authorized and then captured, some banks show both as separate pending lines for 2 to 3 business days before the authorization drops off. If both charges are still showing after 3 business days, reply here with the last four digits of the card and the order number and we will refund the duplicate within one business day. Either way, you will only ever be charged once for the {p}.",
      "Sorry for the worry over your {p} charge. I checked the order on our side. When a payment is first authorized and then captured, some banks list both as pending charges for 2 to 3 business days until the authorization drops off. If you still see both after 3 business days, reply with the last four digits of the card and your order number, and we will refund the duplicate within one business day. You will only ever pay once for the {p}.",
      "Thanks for flagging this, and apologies for the confusion about the {p} charge. I looked at the order and this pattern is common: a bank shows the authorization and the final charge as two pending lines for 2 to 3 business days, then drops one. If both are still there after 3 business days, send us the last four digits of the card and the order number and we will refund the duplicate within one business day. Rest assured, the {p} is only charged once."
    )
  ),
  list(
    key = "damaged",
    subjects = c("{p} arrived damaged", "Broken {p} in the box", "Package was crushed"),
    bodies = c(
      "The box for my {p} arrived crushed on one corner and the device has a crack across the front. Haven't tried powering it on.",
      "Opened my {p} today and the casing is split. The packaging looked fine from the outside so it must have happened before shipping.",
      "My {p} was delivered with visible damage and a rattling sound inside. I'd like a replacement."
    ),
    replies = c(
      "I'm sorry your {p} arrived damaged. We will replace it at no cost. Please reply with a photo of the damage and one of the shipping label so we can file the carrier claim on our side. As soon as we have those, we ship a replacement {p} with a prepaid return label for the damaged unit. You do not need to wait for the return to arrive before the new one ships. Typical turnaround is 2 business days.",
      "Sorry that your {p} arrived damaged. We will replace it at no charge. Please reply with a photo of the damage and a photo of the shipping label so we can open the carrier claim from our end. Once we have both, we send a new {p} with a prepaid return label for the damaged one. There is no need to wait for the return to reach us before the replacement ships. It usually takes 2 business days.",
      "I'm sorry your {p} showed up damaged. A replacement is on us. Reply with a photo of the damage and one of the shipping label, and we will file the carrier claim ourselves. When we have those, we ship you a replacement {p} along with a prepaid return label for the damaged unit, and you do not have to wait for the return to arrive first. Turnaround is typically 2 business days."
    )
  ),
  list(
    key = "app",
    subjects = c("App won't show my {p}", "{p} missing from the app after update", "App crashes when I open the {p} page"),
    bodies = c(
      "After the latest app update my {p} no longer appears in the device list. The device itself still works on its own.",
      "The app crashes every time I tap on my {p}. Reinstalling didn't help. iPhone, latest iOS.",
      "My {p} shows as offline in the app but it is clearly working. Restarting the phone did nothing."
    ),
    replies = c(
      "Thanks for reporting this. We are aware of a sync issue in the current app release that can hide a {p} or show it offline. The fix is in version 4.12.2, which is rolling out now. In the meantime: sign out of the app, force close it, sign back in, and pull down on the device list to refresh. That re-syncs the {p} for most people. If it is still missing after updating to 4.12.2, reply with the email on your account and we will re-link the device from our side.",
      "Thanks for letting us know. The current app release has a sync bug that can hide a {p} or show it as offline, and version 4.12.2, rolling out now, fixes it. Until you get the update: sign out of the app, force close it, sign back in, and pull down on the device list to refresh. That re-syncs the {p} for most people. If it is still missing after you update to 4.12.2, reply with the email on your account and we will re-link the device from our side.",
      "Sorry about the trouble, and thank you for reporting it. We know about a sync problem in the latest app release that can make a {p} disappear or look offline. The fix ships in version 4.12.2, which is rolling out now. For now, sign out, force close the app, sign in again, and pull down on the device list to refresh, which re-syncs the {p} for most people. If it is still missing once you are on 4.12.2, reply with your account email and we will re-link the device for you."
    )
  ),
  list(
    key = "return",
    subjects = c("How do I return my {p}?", "Want to return {p}, changed my mind", "Return window for {p}"),
    bodies = c(
      "I bought a {p} two weeks ago and it's not what I need. Is it still returnable and how do I start?",
      "I'd like to return the {p} I ordered. It is unopened. What is the process?",
      "Can I return my {p} if I've already set it up? It works but I don't use it."
    ),
    replies = c(
      "Yes, the {p} can be returned within 30 days of delivery, opened or unopened, for a full refund. To start: go to Orders in your account, pick the {p} order, and choose Start a return. You'll get a prepaid label to print or show at any drop-off point. Refunds go back to the original payment method within 5 business days of the return being scanned in. If you set the {p} up already, please remove it from the app first so the next owner can pair it.",
      "Yes, you can return the {p} within 30 days of delivery for a full refund, whether it is opened or not. To begin, open Orders in your account, select the {p} order, and choose Start a return. A prepaid label will be issued for you to print or show at any drop-off point. The refund goes to your original payment method within 5 business days after the return is scanned in. If you already set the {p} up, please remove it from the app first so the next owner can pair it.",
      "Happy to help. The {p} is returnable for a full refund for 30 days after delivery, opened or unopened. Go to Orders in your account, pick the {p} order, and tap Start a return to get a prepaid label you can print or show at a drop-off point. Your refund is sent to the original payment method within 5 business days of the return being scanned. If the {p} is already set up, remove it from the app first so the next person can pair it."
    )
  ),
  list(
    key = "warranty",
    subjects = c("{p} stopped working after 8 months", "Is my {p} under warranty?", "{p} dead, no lights at all"),
    bodies = c(
      "My {p} just stopped responding. No lights, no sound, nothing. Bought it about 8 months ago.",
      "The {p} I got last year has started rebooting itself every few minutes. Is this covered?",
      "Is there a warranty on the {p}? Mine has become unreliable and I'd rather not buy another one."
    ),
    replies = c(
      "Sorry to hear the {p} has failed. Every {p} carries a 2-year limited warranty from the delivery date, so you are covered. To start a claim, reply with the order number or the serial number on the base of the unit and a short description of the symptoms. We'll send a replacement {p} with a prepaid label for the faulty one. You keep using the original until the replacement arrives, if it still works at all.",
      "Sorry the {p} has stopped working. Each {p} comes with a 2-year limited warranty counted from the delivery date, so this is covered. To start a claim, reply with the order number or the serial number on the base of the unit, plus a short description of what it is doing. We will send a replacement {p} with a prepaid label for the faulty one, and you can keep using the original until the new one arrives, if it still runs.",
      "I'm sorry to hear the {p} is failing. Good news: every {p} has a 2-year limited warranty from the delivery date, so you are covered. Reply with the order number or the serial number on the base of the unit and a short description of the symptoms, and we will ship a replacement {p} with a prepaid label for the faulty one. If the original still works, keep using it until the replacement arrives."
    )
  ),
  list(
    key = "howto",
    subjects = c("How do I schedule my {p}?", "Can the {p} work with voice assistants?", "Setting up automations for {p}"),
    bodies = c(
      "I'd like my {p} to turn on at sunset and off at 11 pm. Is that possible without a third-party app?",
      "Does the {p} work with Alexa or Google Home? I can't find it in the skill list.",
      "Can I trigger the {p} when my doorbell rings? I have both devices."
    ),
    replies = c(
      "You can do this from the app without any third-party tools. Open the {p}, tap Automations, then Add. Choose a trigger (a time, sunrise or sunset, or an event from another device such as the doorbell), then choose what the {p} should do. Save it and it runs on the device itself, so it keeps working even when your phone is away. For voice control, enable the Nook Home skill in Alexa or the Nook Home action in Google Home and the {p} will appear automatically after you link your account.",
      "That works from the app, no third-party tools needed. Open the {p}, tap Automations, then Add. Pick a trigger (a time, sunrise or sunset, or an event from another device such as the doorbell) and choose what the {p} should do. Save, and the automation runs on the device itself, so it carries on working even when your phone is out of range. For voice control, enable the Nook Home skill in Alexa or the Nook Home action in Google Home, and the {p} shows up automatically once you link your account.",
      "Good news: you can set that up inside the app without any third-party tools. Open the {p}, tap Automations, then Add. Choose a trigger (a time, sunrise or sunset, or an event from another device such as the doorbell) and what the {p} should do in response. Once saved, it runs on the device itself, so your phone does not need to be nearby. For voice control, turn on the Nook Home skill in Alexa or the Nook Home action in Google Home, and the {p} will appear after you link your account."
    )
  )
)

n_target <- 200
per_issue <- ceiling(n_target / length(issues))

# Each issue has 3 subjects x 3 bodies x 5 products = 45 distinct tickets.
# Draw per_issue of them without replacement, so no ticket appears twice, and
# give each a randomly chosen one of the issue's reply wordings.
pools <- lapply(issues, function(iss) {
  combos <- expand.grid(p = products, s = seq_along(iss$subjects), b = seq_along(iss$bodies), stringsAsFactors = FALSE)
  combos[sample(nrow(combos), per_issue), , drop = FALSE]
})

rows <- list()
for (i in seq_len(per_issue)) {
  for (k in seq_along(issues)) {
    if (length(rows) >= n_target) break
    iss <- issues[[k]]
    cb <- pools[[k]][i, ]
    p <- cb$p
    rows[[length(rows) + 1]] <- list(
      id = sprintf("T-%04d", length(rows) + 1),
      product = p,
      category = iss$key,
      subject = glue_fill(iss$subjects[cb$s], p),
      body = glue_fill(iss$bodies[cb$b], p),
      reply = glue_fill(sample(iss$replies, 1), p)
    )
  }
}

out <- file.path("inst", "extdata", "support_tickets.jsonl")
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
con <- file(out, open = "w", encoding = "UTF-8")
for (r in rows) writeLines(as.character(jsonlite::toJSON(r, auto_unbox = TRUE)), con)
close(con)
cat("wrote", length(rows), "rows to", out, "\n")
