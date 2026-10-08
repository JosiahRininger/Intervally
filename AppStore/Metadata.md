# Intervally — App Store Connect listing

Everything App Store Connect asks for, in the order it asks. Character counts are checked
against Apple's limits: `MetadataTests` holds every block and every counted field below to
the limit in its heading or label, and every stated count to the real one.

> **Ship gate for Intervally Pro: settle this before promising Pro at launch.** App Store
> Connect's help page "Submit an In-App Purchase" says In-App Purchases and subscriptions
> aren't supported on Apple Watch, and asks for them to be removed from an Apple Watch app
> version's submission. The same page says a first non-consumable must be submitted with a
> new app version. Intervally is watch-only. A developer-forum thread (842983, August 2026)
> shows a watch-only app blocked exactly this way, with `Product.products(for:)` coming back
> empty in review. Whether it applies to this account is unverified, so:
>
> 1. Create the app record (a watch-only app is created as an iOS app).
> 2. Create the In-App Purchase from the record at the end of this file.
> 3. Upload one TestFlight build that contains `ProStore`.
> 4. On the In-App Purchase's page, click **Add for Review** and check whether version 1.0
>    can join the same draft submission.
> 5. If App Store Connect refuses, ask App Review (Contact Us) and DTS for the supported
>    path. Then rewrite the "Open question" paragraph of the reviewer notes to describe the
>    path actually taken (Guideline 2.1(b)).
>
> Charging up front, or an iOS companion app (unverified to help), are fallbacks only.

## App information

| Field | Value |
|---|---|
| Name (30) | `Intervally: Interval Timer` (26) |
| Subtitle (30) | `HIIT & Tabata for Apple Watch` (29) |
| Bundle ID | `com.josiahrininger.intervally` |
| SKU | `intervally-watch` |
| Primary category | Health & Fitness |
| Secondary category | Sports |
| Age rating | 4+ (no objectionable content) |
| Content rights | Does not contain third-party content |
| Price | Free |
| In-App Purchase | Intervally Pro, one non-consumable (see the record at the end) |

## URLs

| Field | Value |
|---|---|
| Privacy Policy URL | https://josiahrininger.com/intervally/privacy |
| Support URL | https://josiahrininger.com/intervally/support |
| Marketing URL | *(optional — leave blank)* |

Both pages are live (verified 200, `noindex`). Before Pro ships, make sure the Support page
says where Restore Purchases is (Settings > Intervally Pro) and that refunds go through
Apple at reportaproblem.apple.com: watchOS has no in-app refund sheet.

## Promotional text (170)

```
Set your work, rest, and rounds, then train with your watch in your pocket. Every interval
change taps your wrist — even with your wrist down or the screen off.
```
(160)

## Description (4000)

```
Intervally is an interval timer built for Apple Watch. Set how long to work, how long to rest, and how many rounds — then put your phone away and train. Every interval change taps your wrist, so you never have to look.

KEEPS GOING, WHATEVER YOU DO
Lower your wrist, let the screen go dark, or close the app mid-set. Intervally keeps exact time regardless, and picks up right where you were if the app is closed. With Apple Health on, it runs as a workout, so it can tap your wrist at every change even when you are not looking.

KNOW WHERE YOU ARE AT A GLANCE
A large countdown sits inside a ring that runs down with it. Each phase has its own color — amber to get ready, blue to work, green to rest — so a quick glance tells you everything mid-burpee.

FEEL THE CHANGE
Distinct taps for work and rest, plus a three-second countdown before each change, so you can tell what's next without looking. Skip ahead to the next interval whenever you're ready.

PRESETS FOR HOW YOU TRAIN
Start with Classic, Tabata, or EMOM and adjust any interval with the Digital Crown. Intervally Pro, a one-time purchase, adds unlimited presets, warmup and cooldown phases, and stronger taps.

COUNTS TOWARD YOUR RINGS
With Apple Health, every completed workout is saved as High Intensity Interval Training, with each work and rest interval recorded separately so you can see the breakdown in Fitness. Your heart rate shows live while you train.

START IT YOUR WAY
• Say "Start my Intervally workout" to Siri
• Add the button to Control Center, or to the Action button on Apple Watch Ultra
• Pause with a Double Tap on supported watches
• Tap the Smart Stack widget to start your preset in one tap
• Add the complication to your watch face to see the interval you're on

PRIVATE BY DESIGN
No account, no ads, no tracking, and no servers. Your presets and workouts stay on your watch and in Apple Health.

Intervally is a timer, not a medical device. Check with a healthcare provider before starting a new exercise program.
```

## Keywords (100)

```
hiit,tabata,emom,workout,circuit,boxing,crossfit,training,rounds,rest,gym,stopwatch,countdown,amrap
```
(99) — omits words already in the name/subtitle (interval, timer, watch), which Apple indexes anyway.

## What's New in 1.0 (4000)

```
The first release.
```

## App Privacy (nutrition label)

**Data Not Collected.**

Health data is read and written only on the device through HealthKit and never transmitted,
which is what "collected" means in Apple's definition. Intervally Pro doesn't change that:
it is bought through Apple's In-App Purchase and verified on the watch with StoreKit 2, and
the app keeps only an on-device flag saying Pro is unlocked. There is no analytics SDK, no
advertising identifier, and no network code of the app's own. This matches
`Supporting/PrivacyInfo.xcprivacy`.

## App Review information

**Sign-in required:** No.

**In-App Purchases:** add Intervally Pro to this version's submission, if App Store Connect
allows it (see the ship gate at the top).

### Notes for the reviewer (4000)

Paste this verbatim. It pre-empts the questions HealthKit, the background modes and the
In-App Purchase attract:

```
Intervally is a standalone Apple Watch interval timer. No account or sign-in is needed.

HOW TO TEST
1. Tap Start. Allow notifications and Apple Health when asked.
2. The timer counts down a 10-second lead-in, then alternates work and rest intervals.
3. Lower your wrist or let the screen turn off — the watch taps at each interval change.
4. Tap the X (bottom left) to end, or let it finish to see the summary and the workout saved
   to Health. The button at top right skips to the next interval.

IN-APP PURCHASE
This version includes one In-App Purchase, Intervally Pro
(com.josiahrininger.intervally.pro), a one-time, non-consumable unlock. To reach it, tap the
list icon (top left of the setup screen), then New Preset: the 3 starter presets fill the
free limit, so the Intervally Pro screen opens. The In-App Purchase's own review notes list
the other ways in and the sandbox steps.

Open question: App Store Connect's help ("Submit an In-App Purchase") says In-App Purchases
aren't supported on Apple Watch and asks for them to be removed from an Apple Watch app
version's submission. Intervally is watch-only, so there is no iPhone app to carry the
purchase. If it can't be reviewed with this version, please tell us the supported path. If
the product doesn't load, the Intervally Pro screen says "Pro isn't available right now" and
offers Try Again, and every free feature still works.

HEALTHKIT
Health access is optional. Intervally saves each completed interval workout to Health as a
High Intensity Interval Training workout, with each work and rest interval, and any warmup
or cooldown, as its own segment, and reads heart rate to display it during the workout. If
Health is declined, the timer still works fully and alerts through notifications instead.
No health data leaves the device.

BACKGROUND MODES
- workout-processing: while a workout runs, the app taps the wrist at each interval change
  even with the screen off. watchOS only allows an app to play haptics in the background
  during an active workout session, which is why one is used.
- physical-therapy: the fallback when Health access is declined. It keeps the timer running
  with the screen off so interval changes are still signaled, for users who choose not to
  share workouts with Health.
- audio: Apple's Running workout sessions documentation requires the Audio background mode
  for apps that provide haptic feedback during a workout session; Intervally plays no audio.
```

**Contact:** Josiah Rininger · josiahrininger@gmail.com

## Screenshots

`AppStore/Screenshots/` — 416×496, the Apple Watch Series 46mm size App Store Connect
accepts. Upload in numeric order; each is a real capture of the app, not a mockup.

| File | Shows |
|---|---|
| `1-setup.png` | The workout as a dial: its shape as a segmented ring, total time, Start |
| `2-work.png` | Work phase: blue ring running down, large countdown, round dots, live heart rate |
| `3-rest.png` | Rest phase: green ring — the colour language that makes a glance enough |
| `4-complete.png` | Summary: the ring closes white, total time, "Saved" to Health |

Optional captions if you want text over them: *Set it. Start it. Train.* / *Taps your
wrist at every change* / *Work and rest, told apart at a glance* / *Counts toward your
rings*.

All four show only the free app. Any new screenshot that shows a Pro feature, such as a
warmup or cooldown, must be captioned "Intervally Pro" (Guideline 2.3.2).

## In-App Purchase: Intervally Pro

Created under the app record's In-App Purchases, before the version is submitted.
`StoreKit/Intervally.storekit` mirrors these values for local testing, and `MetadataTests`
keeps the two in step. Selling anything needs the Paid Apps Agreement active in Business;
that is assumed here, not checked.

| Field | Value |
|---|---|
| Type | Non-Consumable |
| Reference Name | `Intervally Pro` |
| Product ID | `com.josiahrininger.intervally.pro` — immutable and never reusable: confirm before saving |
| Display Name (30) | `Intervally Pro` (14) |
| Description (45) | `Unlimited presets, warmups, stronger taps` (41) |
| Price | USD 4.99, auto-equalized for other storefronts |
| Availability | All storefronts |
| Tax category | Match the app (the default option's name is unverified) |
| Family Sharing | **On** — it can never be turned off again: confirm before saving |
| Review screenshot | 416×496 PNG flattened to RGB, no alpha: the Intervally Pro screen opened from Settings, free, with the price showing. Run from Xcode on a 46mm simulator so the StoreKit configuration supplies the price |
| Promotional image | Skip in 1.0 |

Wording rule (Guideline 4.10): free users still get a tap at every interval change, so Pro's
taps are always described as a repeated pattern ("repeats the tap"), never as unlocking
haptics.

### Review notes (4000)

```
Intervally Pro (com.josiahrininger.intervally.pro) is a one-time, non-consumable unlock with Family Sharing turned on. Intervally is a standalone Apple Watch app with no account, sign-in, or server.

FREE vs PRO
The free app is the complete interval timer with up to 3 presets (the starters Classic, Tabata and EMOM). Pro adds:
- Unlimited presets
- Optional warmup and cooldown phases in any preset
- Tap Strength: Strong or Strongest repeats the tap at every interval change. Every change still taps once for free users.

HOW TO REACH THE PURCHASE SCREEN (any one works)
1. Tap the list icon (top left of the setup screen), then New Preset. The 3 starters fill the free limit, so the Intervally Pro screen opens.
2. Tap the Settings button (top right: a gear, or an orange bell if notifications are off), then Intervally Pro (the first row).
3. On the setup screen, turn the Digital Crown down twice to the Warm & Cool page, then tap Warmup, Cooldown, or Unlock Pro.
4. Open Settings the same way, then choose Tap Strength.

BUYING IN THE SANDBOX
Tap the price button and confirm on the system purchase sheet. The screen you came from then finishes what you started: New Preset creates a copy and opens Rename; Warmup or Cooldown opens its editor; Tap Strength shows Standard, Strong and Strongest. Settings > Intervally Pro then shows Unlocked.

RESTORE
Restore Purchases is at the bottom of the Intervally Pro screen. Purchases are verified on the watch with StoreKit 2.

The Pro screen never appears on launch or during a workout. Starting, pausing, skipping and finishing a workout never require Pro.
```
(1606)
