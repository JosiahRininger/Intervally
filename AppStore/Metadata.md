# Intervally — App Store Connect listing

Everything App Store Connect asks for, in the order it asks. Character counts are checked
against Apple's limits: `MetadataTests` holds every block and every counted field below to
the limit in its heading or label, and every stated count to the real one.
`PhoneMetadataTests` holds the iPhone's words in the notes to the app, and `ShipAssetsTests`
holds every screenshot on disk to the size App Store Connect takes and to this file.

Intervally is one iOS app record: the iPhone app, `IntervallyPhone`, carries the Apple Watch
app inside its build. Archive and upload the `IntervallyPhone` scheme only.

> **Ship gate (gate 1): not run yet. Settle it before anything below goes into a
> submission.** App Store Connect doesn't take In-App Purchases with an Apple Watch app
> version ("Submit an In-App Purchase"), which is why Intervally now ships as an iPhone app
> that embeds the watch app. A first non-consumable must still be submitted with a new app
> version, and whether App Store Connect accepts one alongside an iOS 1.0 whose build embeds
> a watch app that also uses StoreKit is unverified. So:
>
> 1. Create the iOS app record with the bundle ID and SKU in the table below. Neither can
>    change afterwards.
> 2. Create the In-App Purchase from the record at the end of this file.
> 3. Upload a build archived from the `IntervallyPhone` scheme.
> 4. On the In-App Purchase's page, click **Add for Review** and check whether iOS version
>    1.0 can join the same draft submission. Don't submit yet.
> 5. Replace this block with what happened. If App Store Connect refuses, ask App Review
>    (Contact Us) and DTS for the supported path, quoting Apple's "Creating independent
>    watchOS apps" ("the in-app purchases are universal"). Charging up front, with Pro for
>    everyone, is the fallback.

## App information

| Field | Value |
|---|---|
| Name (30) | `Intervally: Interval Timer` (26) |
| Subtitle (30) | `HIIT & Tabata for Apple Watch` (29) |
| Platform | iOS: the iPhone app, with the Apple Watch app in the same build |
| Bundle ID | `com.josiahrininger.intervally` — the iPhone app's; the watch app is `….watchkitapp` |
| SKU | `intervally` |
| Primary category | Health & Fitness |
| Secondary category | Sports |
| Age rating | 4+ (no objectionable content; Health or Wellness Topics: No) |
| Content rights | Does not contain third-party content |
| Price | Free |
| Availability | All storefronts; Apple silicon Mac and Apple Vision Pro turned off |
| In-App Purchase | Intervally Pro, one non-consumable (see the record at the end) |

## URLs

| Field | Value |
|---|---|
| Privacy Policy URL | https://josiahrininger.com/intervally/privacy |
| Support URL | https://josiahrininger.com/intervally/support |
| Marketing URL | *(optional — leave blank)* |

Both pages were live on 2026-10-06 (200, `noindex`), written for the watch-only app. Before
submitting, update them through a josiahrininger.com pull request to say:

- History reads Apple Health on the iPhone, only reads, and nothing leaves the device.
- Presets sync directly between the user's own iPhone and Apple Watch, with no server.
- Restore Purchases is in Settings on iPhone, and on the Intervally Pro screen on both
  devices (on the watch: Settings > Intervally Pro).
- Refunds: Settings > Request a Refund on iPhone, or reportaproblem.apple.com. The watch
  has no refund sheet.

## Promotional text (170)

```
Build your intervals on iPhone, then train with your phone in your pocket. Every interval change taps your wrist, even with your wrist down or the screen off.
```
(158)

## Description (4000)

```
Intervally is an interval timer for Apple Watch, with an iPhone app for planning your workouts and looking back on them. Set how long to work, how long to rest, and how many rounds, then put your phone away and train. Every interval change taps your wrist, so you never have to look.

PLAN ON IPHONE, TRAIN ON YOUR WRIST
Build workouts on the big screen, with a tile for work, rest, rounds and the get-ready countdown, and the same values the Digital Crown offers. Tap Put on Watch and it's the next workout your watch starts. Changes reach your watch on their own, and each app keeps working without the other.

SEE EVERY SESSION
History on iPhone shows the interval workouts your Apple Watch saves to Apple Health: the rounds you finished, your average and highest heart rate, the energy you burned, and your heart rate for every interval.

KEEPS GOING, WHATEVER YOU DO
Lower your wrist, let the screen go dark, or close the app mid-set. Intervally keeps exact time regardless, and picks up right where you were if the app is closed. With Apple Health on, it runs as a workout, so it can tap your wrist at every change even when you are not looking.

KNOW WHERE YOU ARE AT A GLANCE
A large countdown sits inside a ring that runs down with it. Each phase has its own color — amber to get ready, blue to work, green to rest — so a quick glance tells you everything mid-burpee.

FEEL THE CHANGE
Distinct taps for work and rest, plus a three-second countdown before each change, so you can tell what's next without looking. Skip ahead to the next interval whenever you're ready.

PRESETS FOR HOW YOU TRAIN
Start with Classic, Tabata, or EMOM and adjust any interval on your iPhone or with the Digital Crown. Intervally Pro, a one-time purchase, adds unlimited presets, warmup and cooldown phases, stronger taps, and Pastel, a theme in soft colors. Buy it once, on your iPhone or your watch, and it unlocks both.

COUNTS TOWARD YOUR RINGS
With Apple Health, every completed workout is saved as High Intensity Interval Training, with each work and rest interval recorded separately so you can see the breakdown in Fitness. Your heart rate shows live while you train.

START IT YOUR WAY
• Say "Start my Intervally workout" to Siri
• Add the button to Control Center, or to the Action button on Apple Watch Ultra
• Pause with a Double Tap on supported watches
• Tap the Smart Stack widget to start your preset in one tap
• Add the complication to your watch face to see the interval you're on

PRIVATE BY DESIGN
No account, no ads, no tracking, and no servers. Your presets and workouts stay on your iPhone and Apple Watch and in Apple Health, and presets travel directly between your own devices.

Workouts run on Apple Watch. Intervally is a timer, not a medical device. Check with a healthcare provider before starting a new exercise program.
```

## Keywords (100)

```
hiit,tabata,emom,workout,circuit,boxing,training,rounds,rest,gym,countdown,amrap,cardio,sprint,yoga
```
(99) — omits words already in the name/subtitle (interval, timer, watch), which Apple indexes anyway.

## What's New in 1.0 (4000)

```
The first release.
```

## App Privacy (nutrition label)

**Data Not Collected.**

Health data is read and written only on the user's devices through HealthKit and never
transmitted, which is what "collected" means in Apple's definition. The watch writes each
workout and reads heart rate; the iPhone only reads the workouts, heart rate and energy
History shows. Presets go from one of the user's devices to the other over
WatchConnectivity and reach no server, so they aren't collected either. Intervally Pro
doesn't change that: it is bought through Apple's In-App Purchase and verified on each device
with StoreKit 2, and each app keeps only an on-device flag saying Pro is unlocked. There is
no analytics SDK, no advertising identifier, and no network code of the app's own. This
matches both privacy manifests, `Phone/Resources/PrivacyInfo.xcprivacy` (iPhone) and
`Supporting/PrivacyInfo.xcprivacy` (watch app and widget).

## App Review information

**Sign-in required:** No (uncheck it: it has defaulted to checked before).

**In-App Purchases:** add Intervally Pro to the same submission as iOS version 1.0.

### Notes for the reviewer (4000)

Paste this verbatim. It pre-empts the questions HealthKit, the background modes and the
In-App Purchase attract:

```
Intervally is an interval timer for Apple Watch with a companion iPhone app. No account or sign-in is needed. Workouts run on the watch. On iPhone you build workouts, look back at sessions, and buy Intervally Pro. Every iPhone screen works without a paired Apple Watch, including on iPad.

ON IPHONE
1. Workouts lists the presets. Tap one to edit it: each tile (Work, Rest, Rounds, Get Ready) opens a picker, and changes save as they are made. Put on Watch makes it the workout the watch starts next. + adds a workout.
2. History reads the interval workouts Intervally on Apple Watch saved to Apple Health. Tap Connect Apple Health; the iPhone app only reads Health. Until the watch has saved a workout, History explains where sessions come from.
3. Settings (the gear at top left) has Intervally Pro, Theme, Apple Watch, Apple Health, Restore Purchases, Redeem Code, Support and the Privacy Policy.
4. Settings > Theme switches between Classic and Pastel. Pastel is part of Intervally Pro, and also changes the Home Screen icon.

ON APPLE WATCH
1. Tap Start. Allow notifications and Apple Health when asked.
2. The timer counts down a 10-second lead-in, then alternates work and rest intervals.
3. Lower your wrist or let the screen turn off — the watch taps at each interval change.
4. Tap the X (bottom left) to end, or let it finish to see the summary and the workout saved to Health. The button at top right skips to the next interval.
Presets sync between the two apps over WatchConnectivity, directly between the user's own devices. Each app keeps its own copy and works on its own.

IN-APP PURCHASE
This version includes one In-App Purchase, Intervally Pro (com.josiahrininger.intervally.pro), a one-time, non-consumable unlock for both the iPhone app and the Apple Watch app. The quickest way in is on iPhone: tap + (top right of Workouts), and because the 3 starter presets fill the free limit, the Intervally Pro screen opens. On the watch, tap the list icon (top left of the setup screen), then New Preset. The In-App Purchase's own review notes list the other ways in. If the product doesn't load, the Intervally Pro screen says "Pro isn't available right now" and offers Try Again, and every free feature still works.

MORE THAN A TIMER
- Each work and rest interval is saved to Apple Health as its own segment of one workout, with heart rate.
- A workout session taps the wrist at every interval change with the screen off.
- A complication, a Smart Stack widget, Siri, a Control Center control and the Action button on Apple Watch Ultra start the workout or show where it is.

HEALTHKIT
Health access is optional on both devices. The watch saves each completed interval workout to Health as a High Intensity Interval Training workout, with each work and rest interval, and any warmup or cooldown, as its own segment, and reads heart rate to display it during the workout. To Health the two apps are one app, so the watch's request also covers what iPhone History reads: workouts, heart rate and active energy. The iPhone app never writes to Health. If Health is declined, the timer still works fully and alerts through notifications instead. No health data leaves the user's devices or goes to iCloud.

BACKGROUND MODES (the Apple Watch app)
- workout-processing: while a workout runs, the app taps the wrist at each interval change
  even with the screen off. watchOS only allows an app to play haptics in the background
  during an active workout session, which is why one is used.
- physical-therapy: the fallback when Health access is declined. It keeps the timer running
  with the screen off so interval changes are still signaled, for users who choose not to
  share workouts with Health.
- audio: Apple's Running workout sessions documentation requires the Audio background mode
  for apps that provide haptic feedback during a workout session; Intervally plays no audio.
The iPhone app declares no background modes.
```

**Contact:** Josiah Rininger · josiahrininger@gmail.com · phone number entered by Josiah

## Screenshots

Every file is a real capture of the app, flattened to RGB (`sips -g hasAlpha` says no).
None shows a price (Guideline 2.3.7). Upload each set in numeric order.

### iPhone 6.9" — 1320 × 2868, `AppStore/Screenshots/iPhone-6.9/`

Captured on an iPhone 17 Pro Max simulator (iOS 26.3), with the status bar at 9:41 and a
full battery. The 6.9" set is the one App Store Connect requires.

### iPhone 6.3" — 1206 × 2622, `AppStore/Screenshots/iPhone-6.3/`

The same five shots from an iPhone 17 Pro simulator.

| File | Caption | Shows |
|---|---|---|
| `1-workouts.png` | WORKOUTS · Plan on iPhone. Train on your wrist. | The library, and the workout up next on the watch |
| `2-editor.png` | EDITOR · Build it here. Put it on your watch. | Tabata's editor: its ring, a tile per number, Put on Watch; Warmup and Cooldown marked PRO |
| `3-pro-editor.png` | INTERVALLY PRO · Add a warmup and a cooldown | EMOM with a 5-minute warmup and a 3-minute cooldown. A Pro feature, so the caption names Intervally Pro (Guideline 2.3.2) |
| `4-history.png` | HISTORY · Every session, interval by interval | History grouped by week, an early end included |
| `5-session.png` | SESSION · Your heart rate, every interval | A session's ring, totals and heart rate per interval |
| `6-pastel.png` | INTERVALLY PRO · Make it yours with Pastel | Workouts in the Pastel theme. A Pro feature, so the caption names Intervally Pro (Guideline 2.3.2) |

The captions are drawn by `AppStore/Screenshots/compose.py`, which turns the raw captures
into these files at the same size. To retake them, in a Debug build:

- Launch with `-phone.welcomeSeen.v1 YES -qaWatch installed` and `-qaPro free`, or
  `-qaPro pro` for shot 3.
- Shot 3 sets its bookends with `-qaEdit "warmup 2 300; cooldown 2 180"`. Open Tabata
  (shot 2) and EMOM (shot 3) from the library. Nothing needs scrolling: the editor hides
  the tab bar and sizes its ring so the whole editor fits on both phones.
- Shots 4 and 5 use `-qaHistory sample -qaOpen history` and `-qaOpen session`. The sample
  sessions are a fixture: nothing is read from or written to Health (Guideline 5.1.3(ii)).
- Override the status bar with `simctl status_bar <udid> override --time 9:41
  --batteryState discharging --batteryLevel 100`.

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

ON IPHONE (the main way to buy; no Apple Watch needed)
1. On Workouts, tap + (top right). The 3 starters fill the free limit, so the Intervally Pro screen opens.
2. Tap a workout, then its Warmup or Cooldown tile, marked PRO.
3. Tap Settings (the gear at top left), then Intervally Pro (the first row).
4. Tap Settings, then Theme, then Pastel, marked PRO.
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
