# Intervally

An interval timer for Apple Watch. Set work, rest and rounds; it counts you through them
with distinct haptics for each phase and keeps time correctly whether or not you're looking
at your wrist. Intervally Pro, a one-time purchase, adds unlimited presets, warmup and
cooldown phases, and stronger taps.

## Tech stack

watchOS 26 · Swift 6 (strict concurrency) · SwiftUI · Observation · HealthKit · WidgetKit ·
App Intents · StoreKit 2 · XcodeGen

## Getting started

The Xcode project is generated, not checked in:

```bash
xcodegen generate
```

```bash
xcodebuild test -project Intervally.xcodeproj -scheme Intervally -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.2'
```

## How the timer survives backgrounding

This was the problem that stalled the original version. It has two halves, and they need
different answers.

**Keeping time correct.** The engine never counts down. It stores an anchor `Date` and
derives everything — current phase, seconds remaining, ring progress — as a pure function
of `now - anchor`. Time that passes while the app is suspended, the screen is off, or the
process has been killed outright is simply time that elapsed; nothing has to be running for
the workout to progress. The original decremented a `Timer.publish` counter, so every tick
the system withheld was a second the workout silently lost.

**Alerting you at a boundary.** That does need execution, and watchOS is strict about it:
`WKInterfaceDevice.play(_:)` is documented as a no-op when the app isn't active, with
exactly one exception — an app with an active workout session. So the app layers three
mechanisms and picks the best one available:

| Tier | Mechanism | What it buys | When |
|---|---|---|---|
| 1 | `HKWorkoutSession` + `HKLiveWorkoutBuilder` | Unlimited runtime, survives leaving the app, **background haptics**, Always-On, saves to Health | Health access granted |
| 2 | `WKExtendedRuntimeSession` (`physical-therapy`) | Runs with the screen off and wrist down; ends if you leave the app | Health declined |
| 3 | Local notifications (`.timeSensitive`) | Boundaries still alert if the app is suspended or terminated | Whenever tier 1 isn't active |

Tier 3 is scheduled only when tier 1 isn't running — under a workout session the app plays
its own haptics, and scheduling notifications as well would double-alert at every boundary.

A `RunSnapshot` is persisted to the shared App Group on every state change, so relaunching
after termination resumes the run exactly where it had got to, and the Smart Stack
complication can render a live countdown without the app being awake. If the system kept a
workout session alive across that termination it is *adopted* rather than replaced — starting
a second session orphans the first, and everything recorded before the crash never reaches
Health.

Each interval is its own `HKWorkoutActivity`, so the saved workout carries real per-interval
splits instead of one undifferentiated block. The warmup and cooldown are activities too,
but keep the workout's HIIT type — every activity of an interval workout shares it, and
another type would switch the sensor algorithm mid-session — and carry their phase in
`IntervallyPhase` metadata, with no `IntervallyRound`.

`UIBackgroundModes: [audio]` is declared alongside `WKBackgroundModes`, because Apple's
"Running workout sessions" article requires it: "If your app plays audio or provides haptic
feedback during the workout session, you must also add the Audio background mode." The app
taps the wrist at every interval change during the session and plays no sound. This is not
the old silent-audio-session trick, and the App Review notes in `AppStore/Metadata.md` cite
the article so the mode isn't read as an unbacked one (Guideline 2.5.4). Declaring it is
what Apple asks for; that taps then fire with the wrist down is still to be confirmed on a
real watch (see [Notes for building on device](#notes-for-building-on-device)).

## Intervally Pro

One non-consumable In-App Purchase, `com.josiahrininger.intervally.pro`, with Family
Sharing on. The free app is the whole timer. Pro adds three things, each gated in one place:

- **Unlimited presets.** Free holds three, which the starters fill, so the paywall appears
  only when someone asks for a fourth. Only adding is gated (`ProGating.canAddPreset`): a
  device that already holds more, after a refund say, keeps, edits, runs and deletes every
  one.
- **Warmup and cooldown.** Optional easy phases before the first interval and after the
  last, edited on Setup's third page. They're stored on the preset, but `RunCoordinator`
  runs `store.selected.effective(isPro:)`, which zeroes them without Pro. That is the only
  gate on what runs: the snapshot, the complication, notifications and a restored run all
  inherit the effective workout, and nothing stored is erased if Pro lapses. A run in
  progress keeps its plan.
- **Tap Strength.** Strong and Strongest play the boundary tap two or three times
  (`Haptics.plan`, played by `HapticPlayer`). The app has one player, and the Settings and
  paywall previews go through it too, so a live run's boundary always replaces a preview
  rather than being masked by it. The strength is read at every boundary, so it
  drops to Standard at the next interval change if Pro lapses mid-run. Every change still
  taps once for free users: Pro sells a repeated pattern, never haptics (Guideline 4.10).

`ProStore` is the app's only contact with StoreKit, and no SwiftUI file imports StoreKit —
where both are imported, `Transaction` is ambiguous. `isPro` starts from a cached flag,
because a workout recovered in the background picks its tap strength before StoreKit can
answer. After that StoreKit wins, with one exception: a cached Pro that StoreKit reports
gone is read again 3 s later before it drops, so one transient empty answer can't downgrade
a paying user mid-workout, and the entitlement is read again whenever the app comes
forward, so a longer outage doesn't outlast it either. The paywall is always pushed onto
the navigation stack it was opened from, and never appears on launch, during a run, on the
summary, or from Siri, Control Center or the complication: a start from any of those first
closes whatever sheet or pushed screen was left open (`RootNavigation`).

`StoreKit/Intervally.storekit` mirrors the App Store Connect record. It is a resource of the
test bundle only, and the scheme's Run action uses it for local purchases.
`ProStoreStoreKitTests` drives the real `ProStore` against it with `SKTestSession`, in one
serialized suite because a process has a single StoreKit test environment, and the app's own
store never starts in the test host (`INTERVALLY_UNIT_TESTS`). Debug builds accept
`-qaPro pro` or `-qaPro free` to pin the entitlement for one launch, and
`-qaPreset work,rest,rounds[,prepare[,warmup,cooldown]]` to rewrite the selected preset;
neither exists in Release.

Shipping Pro is not settled: App Store Connect's help says In-App Purchases aren't supported
on Apple Watch app versions. The ship gate at the top of `AppStore/Metadata.md` lists what
to check before promising Pro at launch.

## Layout

```
Shared/     model compiled into both the app and the widget
  IntervalWorkout.swift    settings (lead-in, warmup, work/rest/rounds, cooldown), clamped
  IntervalPlan.swift       immutable expanded schedule + pure position(atElapsed:)
  RunProgress.swift        what a persisted run looks like at an instant (drives the widget)
  WorkoutStore.swift       presets and in-flight run persistence
  StartWorkoutIntent.swift App Intents + Siri phrases
Sources/
  App/                     @main App + WKApplicationDelegate
  Model/TimerEngine.swift  anchor-based run state machine
  Pro/                     Intervally Pro: the free tier's limits and ProGating, and
                           ProStore, the app's only StoreKit code
  Session/                 workout session, extended runtime, notifications, haptics
    HapticPlayer.swift     plays a boundary's taps, repeats included, and cancels them
    RunDependencies.swift  the protocols RunCoordinator is built against, so its tier and
                           backstop logic is testable without HealthKit or WatchKit
  Views/                   setup, run, presets, settings, paywall, tap strength, ring,
                           shared dial geometry
StoreKit/                  local StoreKit configuration (test bundle and Run action only)
Widget/                    Smart Stack complication + Control Center control
Tests/                     Swift Testing — 357 tests
```

## Design notes

Every screen with a ring — Setup, Run, Summary — is laid out by one `DialLayout`, measured
from the full display. The ring sits in the same place at the same size on all three, so
Start reads as the ring changing state rather than a new screen arriving, and the bottom
control row (Start; End and Pause; Done) never moves under the thumb. It is sized from the
full height: ~100pt on a 40mm watch, ~140pt on 46mm, ~144pt on an Ultra. `DialGeometryTests`
pins those numbers and checks that nothing overflows on all eight screen sizes.

The ring is a timer, not an Activity ring: one ring, flat colour, round caps, and it
*depletes* toward twelve o'clock as the interval runs down. No concentric rings, no
Move/Exercise/Stand colours, no gradient along the arc (Apple's HIG and App Review 5.2.5
both reserve that look for Activity). The workout's shape on Setup is one segmented ring —
lead-in, warmup, then work and rest arcs in proportion, then cooldown — not a stack of
rings. A warmup or cooldown is drawn at no more than 15% of the ring
(`SegmentedRing.bookendCap`), and the other phases share what's left in proportion, so a
30-minute warmup can't shrink the rounds to slivers. The ring then under-draws a long
bookend on purpose; the total inside it stays exact.

Phase colour is the app's language: amber lead-in, ember warmup, blue work, green rest,
lavender cooldown, carried by the ring, the phase word and the one tinted control on each
screen. Everything else is grey glass. Ember is deeper than the amber lead-in it follows;
lavender sits away from both work and rest, because it follows the last work interval
directly. The sun rising and setting gives the two a matching pair of glyphs. Prominent
buttons use dark text on the bright variant — white on the dark variant measured below
3:1, and black clears 8.5:1 on both bookend colours. Text inside a ring is limited to the
chord at its height (`DialLayout.chord(atOffset:)`), so nothing touches the stroke on a
small watch.

## Notes for building on device

- The App Group `group.com.josiahrininger.intervally` needs to be registered for the signing team.
  Without it the app still works; the complication just won't see the running workout.
- HealthKit and Time Sensitive Notifications capabilities must be enabled on the App ID.
- StoreKit 2 needs no entitlement, so the project adds neither one nor Xcode's In-App
  Purchase capability. Whether watchOS archive validation agrees is unverified.
- Background haptics and the workout session can only be verified on a real watch —
  the simulator has no Taptic Engine and does not enforce background execution limits.
  Before Stronger taps is sold, check on a watch that taps fire with the wrist down at all
  three tap strengths, and how far apart the repeats feel; the spacing is a starting point.
- Also only checkable on a watch, or in an Xcode run: a real purchase, restore and Ask to
  Buy; the Rename sheet that opens after a purchase from New Preset; and "COOLDOWN" fitting
  the 40mm run screen.
- `PrivacyInfo.xcprivacy` ships in both the app and the widget; nothing is collected and
  nothing leaves the watch.

## Shipping

- Privacy policy: https://josiahrininger.com/intervally/privacy
- Support: https://josiahrininger.com/intervally/support
- App Store listing copy, review notes, the In-App Purchase record and screenshots:
  `AppStore/`. `MetadataTests` checks the listing against Apple's field limits and the app.
