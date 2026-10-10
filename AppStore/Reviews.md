# Ratings and reviews: the playbook

How Intervally earns five-star reviews without breaking App Store rules. The in-app part is
code (`Phone/Reviews/`, `ReviewPromptTests`); the rest is a routine.

## The rules that shape it

- **Only Apple's prompt.** Guideline 5.6.1 allows the system rating prompt and nothing else:
  no custom "Enjoying Intervally?" pop-up, and no gate that sends happy users to the App
  Store and unhappy ones to email. The system shows its prompt at most three times in 365
  days, and decides on its own whether to show it at all.
- **Never in TestFlight.** The system prompt doesn't appear in TestFlight builds, so it can
  only be seen once the app is live (or in a Debug build run from Xcode).
- **Not on the watch.** `RequestReviewAction` is unavailable on watchOS. Workouts happen on
  the wrist, so the iPhone asks later, at its own good moments.
- **No incentives, no friends-and-family campaigns.** Paying, rewarding or asking people to
  post reviews (5.6.2) risks removal. Sharing the App Store link is fine.

## In the app (shipped)

The iPhone asks only when all of these hold (`ReviewPolicy`):

| Gate | Value |
|---|---|
| Installed for at least | 3 days |
| Not already asked in | this version |
| Last ask at least | 120 days ago |
| Moment | **Done** after a workout finished on iPhone, from the **third** one; back from a session in History with **3+ sessions** saved; or just after **Put on Watch** once the app has been opened on **5 different days** (for people without Health) |

It asks a second after the moment, so the prompt never lands mid-transition, and counts the
ask whether or not the system showed anything, so it never nags. QA launches never ask.

Always there, in Settings:

- **Rate Intervally** opens the App Store's Write a Review page (user-initiated, allowed).
- **Send Feedback** opens a mail draft with the app and iOS versions. An unhappy user who
  can reach the developer in one tap usually emails instead of posting one star.

## The routine

- **Launch week:** read new reviews daily (App Store Connect app, notifications on for
  Ratings & Reviews). Reply to every one within a day.
- **After that:** weekly. Reply to every 1–3 star review: thank them, say what you'll do,
  and when a fix ships, edit the reply ("Fixed in 1.0.1, thanks for the report"). Reviewers
  are notified of replies and often raise their rating.
- **Feedback emails:** answer within a day. When their problem is fixed, it's fine to say a
  rating helps an indie app; never offer anything for it.
- **Ship small updates every 4–6 weeks.** Each new version is one more chance for the prompt
  (once per version, 120 days apart), and an active app ranks better.
- **Resetting the summary rating** (App Store Connect, per version) only if the average is
  below 4.0 and the cause is fixed in that version.
- **What's New:** name what reviewers asked for. It shows people are heard.
