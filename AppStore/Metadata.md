# Intervally — App Store Connect listing

Everything App Store Connect asks for, in the order it asks. Character counts are checked
against Apple's limits: `MetadataTests` holds every block and every counted field below to
the limit in its heading or label, and every stated count to the real one.
`PhoneMetadataTests` holds the iPhone's words in the notes to the app, and `ShipAssetsTests`
holds every screenshot on disk to the size App Store Connect takes and to this file.

Intervally is one iOS app record: the iPhone app, `IntervallyPhone`, carries the Apple Watch
app inside its build. Archive and upload the `IntervallyPhone` scheme only.

> **Ship gate (gate 1): passed on 2026-10-09.** App Store Connect took Intervally Pro and
> iOS 1.0 (build 2), which embeds the watch app, in one review submission: the In-App
> Purchase's page, **Add for Review**, then the version's **Add for Review** into the same
> draft, then **Submit for Review**. Version 1.0 also needed the Regulated Medical Device
> declaration (App Information): No.

> **1.1: workouts run on iPhone too.** The iPhone runs a workout itself, with tones, a Pro
> voice coach, a Live Activity, and an iOS 26 workout session that saves it to Health. The
> listing below was 1.1's. 1.0 was pulled from review for it before App Review saw it, so
> Intervally Pro went in again with 1.1.

> **1.2 replaced 1.1 in review on 2026-10-12, before App Review saw either.** New: name
> every interval and give it an icon, choose what Health records a workout as, cues lower
> other audio while they play, and the duration pickers turn minutes and seconds. Neither
> 1.0 nor 1.1 reached a reviewer, so 1.2 is Intervally's first release (no What's New
> field), and Intervally Pro goes in with it. The listing below is 1.2's.

> **1.3 (build 14) is the first update.** New: Pause, Resume and Skip Interval on the Lock
> Screen and in the Dynamic Island; End can save the workout so far; deleting asks first;
> cues land on the second; Hear the Coach before buying; "Saved to Health" only when it was.
> Intervally Pro is approved and on the store, so this submission leaves it out. The rest of
> the 1.3 plan (sets and circuits, History without Health, goals and reminders, Siri starts,
> workout files) moves to 1.4.

## App information

| Field | Value |
|---|---|
| Name (30) | `Intervally: Interval Timer` (26) |
| Subtitle (30) | `HIIT, Tabata & EMOM Workouts` (28) |
| Platform | iOS: the iPhone app, with the Apple Watch app in the same build |
| Bundle ID | `com.josiahrininger.intervally` — the iPhone app's; the watch app is `….watchkitapp` |
| SKU | `intervally` |
| Primary category | Health & Fitness |
| Secondary category | Sports |
| Age rating | 4+ (no objectionable content; Health or Wellness Topics: Yes, as App Review asked 2026-10-20) |
| Content rights | Does not contain third-party content |
| Regulated medical device | No (App Information; asked of Health & Fitness apps) |
| Price | Free |
| Availability | All storefronts; Apple silicon Mac and Apple Vision Pro turned off |
| In-App Purchase | Intervally Pro, one non-consumable (see the record at the end) |

## URLs

| Field | Value |
|---|---|
| Privacy Policy URL | https://josiahrininger.com/intervally/privacy |
| Support URL | https://josiahrininger.com/intervally/support |
| Marketing URL | *(optional — leave blank)* |

Both pages cover the iPhone app since josiahrininger.com#41. For 1.1 they must also say,
through a josiahrininger.com pull request merged before submitting:

- Workouts run on iPhone as well as on Apple Watch, and a workout finished on iPhone is
  saved to Apple Health on that iPhone. Nothing leaves the user's devices.
- The Lock Screen countdown is a Live Activity, drawn on the device; no push server.
- Sounds & Voice in Settings: beeps, the 3-2-1 countdown, the Pro voice coach, Keep Screen On.

## Promotional text (170)

```
No subscription: Pro is a one-time purchase. Cues play over your music, and your music keeps playing. On Apple Watch, every change taps your wrist, screen off or not.
```
(166)

## Description (4000)

```
Intervally is an interval timer for iPhone, iPad and Apple Watch. Set how long to work, how long to rest, and how many rounds, press Start, and train. Every interval change is marked for you, with a tone on your iPhone or a tap on your wrist, so you never have to watch the clock.

NO SUBSCRIPTION, NO ADS
Intervally is free to use, with no ads and no account. Intervally Pro is a one-time purchase, not a subscription: buy it once and it unlocks iPhone, iPad and Apple Watch, shared with your family.

TRAIN WITH YOUR IPHONE OR IPAD
Press Start and put your phone down. A tone marks each change, higher for work and lower for rest, with a 3-2-1 countdown before it. The cues play right over your music, and the music keeps playing, with Intervally open or your phone locked. The countdown stays on your Lock Screen and in the Dynamic Island, where you can pause, resume or skip an interval without unlocking.

OR ON YOUR WRIST
With Apple Watch, every interval change taps your wrist, even with your wrist down or the screen off. Build workouts on iPhone, then tap Start on Watch to run one on your wrist right away. Tap Put on Watch and it's the next workout your watch starts. Workouts sync between iPhone and Apple Watch, and each app keeps working without the other. On iPad, they stay on the iPad.

KNOW WHERE YOU ARE AT A GLANCE
A large countdown sits inside a ring that runs down with it. Each phase has its own color: amber to get ready, blue to work, green to rest. A quick glance tells you everything mid-burpee.

SEE EVERY SESSION
Every workout you finish is saved to Apple Health. End a workout early and you choose: save what you did, or discard it. History on iPhone shows them all: the rounds you finished and the calories you burned in every interval, and with Apple Watch your average and highest heart rate and your heart rate for every interval.

NAME EVERY INTERVAL
Call each interval what it is, Run and Walk, Brisk and Easy for Japanese interval walking, Lift and Breathe, Sprint and Recover, and give it an icon. Its name shows on the run screen, your Lock Screen and your watch, and the voice coach says it.

PRESETS FOR HOW YOU TRAIN
Start with Classic, Tabata, or EMOM and adjust any interval. Intervally Pro, a one-time purchase, adds unlimited presets, warmup and cooldown phases, a voice coach that calls out every interval on iPhone, stronger taps on Apple Watch, and Pastel, a theme in soft colors. Buy it once, on your iPhone or your watch, and it unlocks both.

KEEPS GOING, WHATEVER YOU DO
Lock your phone, lower your wrist, or switch apps mid-set. Intervally keeps exact time regardless, lands every cue on the second, and picks up right where you were if the app is closed. With Apple Health on, it runs as a workout, so every change is marked even when you are not looking.

SAVED THE WAY YOU TRAIN
With Apple Health, every completed workout is saved as the activity you choose for it, from HIIT to running, cycling, rowing, strength or yoga, with each work and rest interval recorded separately so you can see the breakdown in Fitness. With Apple Watch, your workouts count toward your Activity rings.

START IT YOUR WAY ON APPLE WATCH
• Say "Start my Intervally workout" to Siri
• Add the button to Control Center, or to the Action button on Apple Watch Ultra
• Pause with a Double Tap on supported watches
• Tap the Smart Stack widget to start your preset in one tap
• Add the complication to your watch face to see the interval you're on

PRIVATE BY DESIGN
No account, no ads, no tracking, and no servers. Your presets and workouts stay on your iPhone, iPad and Apple Watch and in Apple Health, and presets travel directly between your iPhone and your Apple Watch.

Workouts run on iPhone, iPad or Apple Watch, whichever you start them on. Made for every iPhone, iPhone Duo included, and for iPad in any orientation. Intervally is a timer, not a medical device. Check with a healthcare provider before starting a new exercise program.
```

## Keywords (100)

```
run,walk,walking,japanese,round,boxing,circuit,amrap,wod,watch,rest,sprint,training,cardio,countdown
```
(100) — omits words already in the name and subtitle (interval, timer, hiit, tabata, emom, workouts), which Apple indexes anyway, and every es-MX keyword (below).

## What's New in 1.3 (4000)

```
• Pause, resume or skip an interval right from your Lock Screen or the Dynamic Island.
• End a workout early and keep it: End now offers Save Workout, so a session you cut short still counts in Apple Health.
• Every cue lands right on the second, even after a pause or a skip.
• Deleting a workout always asks first, on iPhone, iPad and Apple Watch.
• Hear the voice coach before you buy Intervally Pro. At the free limit, you can edit a starter workout instead.
• If Apple Health couldn't save a workout, the summary says so.
• Workouts sync more reliably between iPhone and Apple Watch, and long workouts keep their final alert.
```
(630)

## Listing localizations

en-GB, en-AU and en-CA reuse the en-US name, subtitle, promotional text, description,
keywords, What's New and screenshots. es-MX reuses the en-US copy and screenshots with
keywords of its own, which share no word with the en-US keywords, the name or the subtitle:
the US storefront indexes es-MX too, so they widen what Intervally is found for.

| Field | Value |
|---|---|
| es-MX Keywords (100) | `rowing,cycling,spin,rope,jump,kettlebell,plank,stretch,strength,core,pilates,kickboxing,dance,stairs` (100) |

## Accessibility Nutrition Labels

Declared only for what the app does by default and the audits back
(`AccessibilityAuditTests`: contrast, descriptions and the largest text size on iPhone).

| Device | Declared |
|---|---|
| iPhone | Dark Interface, Larger Text, Sufficient Contrast |
| iPad | Dark Interface |
| Apple Watch | Dark Interface |

Not declared yet: VoiceOver, Voice Control, Reduced Motion, Differentiate Without Color
Alone, Captions and Audio Descriptions. The accessibility work planned for 1.4 (p52 to p55
in the 1.3 plan) and audits on iPad and the watch are what would earn them.

## Analytics Reports

An ONGOING Analytics Reports request was filed with the Admin API key on 2026-10-30
(`e9d40318-256d-448e-9e4e-85bd2c27247c`). Apple starts producing the reports a day or two
later; they hold no personal data.

## App Privacy (nutrition label)

**Data Not Collected.**

Health data is read and written only on the user's devices through HealthKit and never
transmitted, which is what "collected" means in Apple's definition. Each device writes the
workouts it runs; the watch reads heart rate during a workout; the iPhone reads the
workouts, heart rate and energy History shows. Presets go from one of the user's devices to
the other over WatchConnectivity and reach no server, so they aren't collected either. The
Live Activity is started and updated by the app on the device, with no push service.
Intervally Pro doesn't change that: it is bought through Apple's In-App Purchase and verified
on each device with StoreKit 2, and each app keeps only an on-device flag saying Pro is
unlocked. There is no analytics SDK, no advertising identifier, and no network code of the
app's own. This matches both privacy manifests, `Phone/Resources/PrivacyInfo.xcprivacy`
(iPhone app and its Live Activity extension) and `Supporting/PrivacyInfo.xcprivacy` (watch
app and widget).

## App Review information

**Sign-in required:** No (uncheck it: it has defaulted to checked before).

**In-App Purchases:** Intervally Pro is approved and on the store (approved 2026-10-27, with
1.2), so a version goes in without it. Add it to a submission only when its own record
changes; through the API, an In-App Purchase that has been approved before goes in on its own.

### Notes for the reviewer (4000)

Paste this verbatim. It pre-empts the questions HealthKit, the background modes, the Live
Activity and the In-App Purchase attract:

```
Intervally is an interval timer for iPhone, iPad and Apple Watch. No account, sign-in or Apple Watch is needed.

ON IPHONE
1. Tap Start on the workout up next, or the play button on any workout, to run it; the first run asks for notifications and Apple Health.
2. A 10-second lead-in, then work and rest alternate: a tone at each change, a 3-2-1 tick before it. Locked, the Lock Screen and Dynamic Island show the countdown with Pause or Resume and Skip Interval, and the tones go on. X (bottom left) ends the run and asks first: after a minute with Health on, Save Workout keeps what was done; or Discard, or Keep Going. Bottom right skips an interval.
3. Tap a workout to edit it: each tile (Work, Rest, Rounds, Get Ready) opens a picker, and changes save as made. In a phase's picker, tap its name to rename it. With a paired watch, Start on Watch runs it there, and Put on Watch makes it the workout the watch starts next. + adds a workout; Delete always asks first.
4. History reads the interval workouts either device saved to Apple Health. Tap Connect Apple Health.
5. Settings (the gear at top left) has Intervally Pro, Theme, Sounds & Voice, Apple Watch, Apple Health, Restore Purchases, Redeem Code, Support and the Privacy Policy.
6. Settings > Theme switches between Classic and Pastel. Pastel is part of Intervally Pro and also changes the Home Screen icon.
7. Settings > Sounds & Voice turns the beeps, the 3-2-1 countdown and Keep Screen On on or off. Its Voice Coach, which calls out each interval as it starts, is part of Intervally Pro. Free users can tap Hear the Coach to hear it.

ON APPLE WATCH
1. Tap Start; allow notifications and Apple Health when asked. A 10-second lead-in, then work and rest alternate.
2. Lower your wrist or let the screen turn off: the watch taps at each change.
3. X (bottom left) ends the run; let it finish to see the summary. Top right skips an interval.
Presets sync between the user's iPhone and watch over WatchConnectivity; each app works on its own.

IN-APP PURCHASE
Intervally Pro (com.josiahrininger.intervally.pro), a one-time unlock for both apps, is approved and on the store, so it isn't in this submission. On iPhone, tap + (top right of Workouts): the 3 starter presets fill the free limit, so the Intervally Pro screen opens. On the watch, tap the list icon (top left), then New Preset. If the product doesn't load, the screen says "Pro isn't available right now" with Try Again, and every free feature still works.

HEALTHKIT
Health is optional on both devices. Each device saves the workouts it runs (High Intensity Interval Training by default), each interval its own segment. The watch reads heart rate during a workout; iPhone History reads workouts, heart rate and active energy. If Health is declined, the timer still works: on iPhone its sounds mark each change in the background, and notifications take over if they can't play; on the watch, notifications do. No health data leaves the user's devices.

BACKGROUND MODES
iPhone app:
- audio: each interval change is a tone, or the voice coach's words, played while the phone is locked or another app is in front. iOS won't start an app's audio from the background, so a workout's audio output stays open from Start to the end, mixed with other audio: cues play over music without lowering it. Voice coach phrases are prepared only while no other audio plays and kept on the device, so the app never pauses or lowers other audio; a phrase not ready while music plays is skipped and the tone still marks the change. The workout session (HKWorkoutSession) saves the workout to Health.
Apple Watch app:
- workout-processing: taps the wrist at each change with the screen off; watchOS allows background haptics only during a workout session.
- physical-therapy: the fallback when Health is declined, so changes are still signaled.
- audio: required by Apple's Running workout sessions documentation for haptic feedback during a workout session; the watch app plays no audio.
```

**Contact:** Josiah Rininger · josiahrininger@gmail.com · phone number entered by Josiah

## Screenshots

Every file is a real capture of the app, flattened to RGB (`sips -g hasAlpha` says no).
None shows a price (Guideline 2.3.7). Upload each set in numeric order.

### iPhone — 1206 × 2622, `AppStore/Screenshots/iPhone-6.3/`

Captured on an iPhone 17 Pro simulator (iOS 26.3), with the status bar at 9:41 and a full
battery, on the "iPhone with Dynamic Island (medium display)" tab. App Store Connect uses
these for every iPhone size, so there is no 6.9" set. 1.1's set leads with a run on iPhone.

| File | Caption | Shows |
|---|---|---|
| `1-run.png` | TRAIN ON IPHONE · Press Start. Hear every interval. | Classic running on iPhone: work, round 3 of 8, the depleting ring, End, Pause and Skip |
| `2-lock.png` | LOCK SCREEN · Your countdown, phone locked | The run's Live Activity on the Lock Screen: the phase, its countdown and bar, the next interval |
| `3-workouts.png` | WORKOUTS · Every workout, one tap from Start | The workout up next with Start, and the library with a play button on each |
| `4-editor.png` | EDITOR · Name every interval and give it an icon | A run-walk workout's editor: Run and Walk tiles with their own icons, the Outdoor Run activity, Start and Start on Watch; Warmup and Cooldown marked PRO |
| `5-history.png` | HISTORY · Every session, interval by interval | History grouped by week, an early end included |
| `6-session.png` | SESSION · Your calories, every interval | A session's ring, totals and the calories burned in each interval |
| `7-pro-editor.png` | INTERVALLY PRO · Add a warmup and a cooldown | EMOM with a 5-minute warmup and a 3-minute cooldown. A Pro feature, so the caption names Intervally Pro (Guideline 2.3.2) |
| `8-pastel.png` | INTERVALLY PRO · Make it yours with Pastel | A run in the Pastel theme. A Pro feature, so the caption names Intervally Pro (Guideline 2.3.2) |

The captions are drawn by `AppStore/Screenshots/compose.py`, which turns the raw captures
into these files at the same size. To retake them, in a Debug build:

- Override the status bar with `simctl status_bar <udid> override --time 9:41
  --batteryState discharging --batteryLevel 100 --wifiBars 3 --cellularMode active
  --cellularBars 4`. Launch with `-phone.welcomeSeen.v1 YES -phone.editorTipSeen.v1 YES
  -qaWatch installed` and `-qaPro free`, or `-qaPro pro` for shots 7 and 8.
- Shots 1, 2 and 8: `-qaRunElapsed 100` restores Classic three rounds in (8 adds
  `-qaTheme pastel`). Allow notifications, Health and Live Activities once. For shot 2,
  lock the simulator. End each run with End, never by quitting the app: a simulator
  whose app was killed mid-workout keeps a stuck workout session until it is rebooted.
- Shots 4 and 7: `-qaOpen editor`. For 4, `-qaEdit "select 0; rename 0 Run Walk; work 0 60;
  rest 0 90; rounds 0 6; label 0 work run Run; label 0 rest walk Walk; activity 0
  outdoorRun"`; for 7, `-qaEdit "select 2; warmup 2 300; cooldown 2 180"` (EMOM with
  bookends). Every other shot resets them with `-qaEdit "select 0; warmup 2 0; cooldown 2
  0; rename 0 Classic; work 0 30; rest 0 15; rounds 0 8; unlabel 0; activity 0 hiit"`.
- Shots 5 and 6 use `-qaHistory sample -qaOpen history` and `-qaOpen session`. The sample
  sessions are a fixture: nothing is read from or written to Health (Guideline 5.1.3(ii)).

### iPad — 2064 × 2752, `AppStore/Screenshots/iPad-13/`

Captured on a 13-inch iPad Pro simulator (iPadOS 26.3) in portrait, the same eight states
the same way, without `-qaWatch` (iPad has no Apple Watch), on the "iPad 13-inch Display"
tab. Required now that the app runs on iPad. compose.py gives a 3:4 capture the iPad's
proportions and its own caption for the run, which would otherwise speak of iPhone.

| File | Caption | Shows |
|---|---|---|
| `iPad-13/1-run.png` | TRAIN ON IPAD · Press Start. Hear every interval. | Classic running on iPad |
| `iPad-13/2-lock.png` | LOCK SCREEN · Your countdown, phone locked | The run's Live Activity on the iPad Lock Screen |
| `iPad-13/3-workouts.png` | WORKOUTS · Every workout, one tap from Start | Workouts in a centred column, the tabs at the top |
| `iPad-13/4-editor.png` | EDITOR · Name every interval and give it an icon | The same run-walk editor; Warmup and Cooldown marked PRO |
| `iPad-13/5-history.png` | HISTORY · Every session, interval by interval | History grouped by week |
| `iPad-13/6-session.png` | SESSION · Your calories, every interval | A session's totals and calories per interval, with its interval list |
| `iPad-13/7-pro-editor.png` | INTERVALLY PRO · Add a warmup and a cooldown | EMOM with bookends (Guideline 2.3.2) |
| `iPad-13/8-pastel.png` | INTERVALLY PRO · Make it yours with Pastel | A run in Pastel (Guideline 2.3.2) |

### Apple Watch — 416 × 496, `AppStore/Screenshots/Watch/`

The Apple Watch Series 46mm size, uploaded on the version page's Apple Watch tab. Taken
from the 1.0 build on a paired Series 11 (46mm) simulator: Classic, free, a real run with
Health and notifications allowed. The simulator's red "iPhone not connected" glyph beside
the clock is painted out; nothing else is edited.

| File | Shows |
|---|---|
| `1-setup.png` | The workout as a dial: its shape as a segmented ring, total time, Start |
| `2-work.png` | Work phase: blue ring running down, large countdown, round dots, live heart rate in the corner |
| `3-rest.png` | Rest phase: green ring — the colour language that makes a glance enough |
| `4-complete.png` | Summary: the ring closes white, total time, "Saved" to Health |

All four show only the free app. Any new screenshot that shows a Pro feature, such as a
warmup or cooldown, must be captioned "Intervally Pro" (Guideline 2.3.2).

### In-App Purchase review screenshot — `AppStore/Screenshots/iap-review.png`

1320 × 2868: the iPhone's Intervally Pro screen, opened with + at the free limit, free,
showing the price from the StoreKit configuration. For the In-App Purchase's review
screenshot only, never the product page. Retake it with `ManualQAStoreKit` hosting a
StoreKit session in the app (README, "Intervally Pro").

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
| Review screenshot | `AppStore/Screenshots/iap-review.png` (above) |
| Promotional image | Skip in 1.0 |

Wording rule (Guideline 4.10): free users still get a tap at every interval change, so Pro's
taps are always described as a repeated pattern ("repeats the tap"), never as unlocking
haptics.

### Review notes (4000)

```
Intervally Pro (com.josiahrininger.intervally.pro) is a one-time, non-consumable unlock with Family Sharing turned on. Intervally is an iPhone app with an Apple Watch app, and one purchase unlocks Pro in both. There is no account, sign-in, or server.

FREE vs PRO
The free app is the complete interval timer with up to 3 presets (the starters Classic, Tabata and EMOM). Pro adds:
- Unlimited presets
- Optional warmup and cooldown phases in any preset
- Tap Strength: Strong or Strongest repeats the tap at every interval change. Every change still taps once for free users.
- Pastel, a theme in soft colors: light on iPhone, with a matching Home Screen icon, and the same colors on the watch's black screen
- Voice Coach (iPhone): calls out each interval as it starts. Every change still plays a tone for free users.

ON IPHONE (the main way to buy; no Apple Watch needed)
1. On Workouts, tap + (top right). The 3 starters fill the free limit, so the Intervally Pro screen opens.
2. Tap a workout, then its Warmup or Cooldown tile, marked PRO.
3. Tap Settings (the gear at top left), then Intervally Pro (the first row).
4. Tap Settings, then Theme, then Pastel, marked PRO.
5. Tap Settings, then Sounds & Voice, then Voice Coach, marked PRO.
Settings also has Restore Purchases and Redeem Code, and Request a Refund once Pro is bought.

ON APPLE WATCH
1. Tap the list icon (top left of the setup screen), then New Preset. The 3 starters fill the free limit, so the Intervally Pro screen opens.
2. Tap the Settings button (top right: a gear, or an orange bell if notifications are off), then Intervally Pro (the first row).
3. On the setup screen, turn the Digital Crown down twice to the Warm & Cool page, then tap Warmup, Cooldown, or Unlock Pro.
4. Open Settings the same way, then choose Tap Strength.
5. Open Settings the same way, then choose Theme, then Pastel, marked PRO.
If the App Store can't offer Pro on the watch, its Intervally Pro screen says Pro can also be unlocked in Intervally on iPhone.

BUYING IN THE SANDBOX
Tap the price button and confirm on the system purchase sheet. The screen you came from then finishes what you started. On iPhone, + opens the new workout's editor, and Warmup or Cooldown opens its picker. On the watch, New Preset creates a copy and opens Rename; Warmup or Cooldown opens its editor; Tap Strength shows Standard, Strong and Strongest; Pastel applies the Pastel theme on both devices. Settings > Intervally Pro then shows Unlocked.

RESTORE
Restore Purchases is at the bottom of the Intervally Pro screen on both devices. Purchases are verified on each device with StoreKit 2. A purchase made on iPhone reaches the watch through StoreKit; Restore Purchases on the watch picks it up at once.

The Pro screen never appears on launch or during a workout. Starting, pausing, skipping and finishing a workout never require Pro.
```
