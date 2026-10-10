# Intervally

An interval timer for Apple Watch, with an iPhone app to plan workouts and look back on
them. Set work, rest and rounds; the watch counts you through them with distinct haptics
for each phase and keeps time correctly whether or not you're looking at your wrist. The
iPhone edits the same presets, shows each session the watch saved to Health, and sells Pro.
Intervally Pro, a one-time purchase, adds unlimited presets, warmup and cooldown phases,
stronger taps, and Pastel, a theme in soft colours.

## Tech stack

watchOS 26 + iOS 26 companion · Swift 6 (strict concurrency) · SwiftUI · Observation ·
HealthKit · WidgetKit · App Intents · StoreKit 2 · XcodeGen

## Getting started

The Xcode project is generated, not checked in:

```bash
xcodegen generate
```

```bash
# The watch app: Tests/ and SyncTests/
xcodebuild test -project Intervally.xcodeproj -scheme Intervally -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.2'
# The iPhone app (also builds the embedded watch app): PhoneTests/ and SyncTests/
xcodebuild test -project Intervally.xcodeproj -scheme IntervallyPhone -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The watch suite runs 564 tests (24 skipped: the StoreKit suite that can't run in a
companion watch app, and the opt-in manual QA) and the iPhone suite 297 (2 skipped: the one
purchase Xcode's test server cancels, and its manual QA), all Swift Testing, on Xcode 26.2.

The watch app ships inside an iPhone companion, `IntervallyPhone`, which owns the root
bundle ID `com.josiahrininger.intervally` and the App Store record; the watch app is
`….watchkitapp` and its widget `….watchkitapp.widget`. The watch app still installs and runs
without the iPhone app (`WKRunsIndependentlyOfCompanionApp`). Archive the `IntervallyPhone`
scheme only: its archive carries the watch app at `IntervallyPhone.app/Watch/Intervally.app`.
`CompanionBundleTests` (watch) and `EmbeddedWatchAppTests` (iPhone) pin the bundle rules a
Simulator build never checks.

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
Sharing on. The free app is the whole timer. Pro adds four things, each gated in one place:

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
- **Pastel.** A second theme ([Themes](#themes)). `ThemeStore.effective(isPro:)` shows the
  stored choice with Pro and Classic without, so a refund falls back to Classic and a
  restore brings Pastel back. A free user's Pastel in Settings > Theme opens the paywall
  (`PaywallContext.themes`), and a purchase there chooses it.

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
test bundles only, and both schemes' Run actions use it for local purchases. The app's own
store never starts in either test host (`INTERVALLY_UNIT_TESTS`).
`ProStorePhoneStoreKitTests` drives the real `ProStore` against it with `SKTestSession` in
the iPhone app, in one serialized suite because a process has a single StoreKit test
environment. The simulator build signs with `Supporting/IntervallyPhone-Simulator.entitlements`
(the app's entitlements plus `get-task-allow`): without it the iOS 26.3 simulator refuses
every StoreKit test call ("not installed for development"). `Product.purchase()` itself
can't complete in a test session with dialogs off (Xcode's server cancels it), so that one
test is disabled; `ManualQAStoreKit` hosts a live session for buying through the real sheet
by hand. The watch's twin, `ProStoreStoreKitTests`, is disabled: a companion watch app's
StoreKit is served as the iPhone app's, and Xcode 26.2's test service refuses the session
(the reason is in the suite).

Debug builds accept QA launch flags, none of which exist in Release. On the watch,
`-qaPro pro|free` pins the entitlement for one launch, `-qaTheme classic|pastel` pins the
theme shown for one launch (whatever is stored or bought; nothing is saved or synced, and a
choice in Settings ends it) and
`-qaPreset work,rest,rounds[,prepare[,warmup,cooldown]]` rewrites the selected preset. On
iPhone, `-qaPro pro|free`, `-qaTheme classic|pastel` (as on the watch; it never changes the
Home Screen icon), `-qaWatch unsupported|unpaired|notInstalled|installed|firstSync`
(a stand-in watch that never reaches a real one), `-qaWelcome YES`, `-qaOpen
editor|picker|bookends|paywall|settings|watch|pro|health|theme|history|session`,
`-qaHistory sample|empty|connect|unavailable|failed` (History from a fixture; Health is never
read or written) and `-qaEdit "rename 0 Sprint; warmup 0 300"` (`PhoneQA.swift`,
`QAEdit.swift`, `SampleHistory.swift`).

Pro is sold in both apps, under one product. App Store Connect doesn't take In-App
Purchases with an Apple Watch app version, which is why Intervally ships as an iPhone app
that embeds the watch app: Apple's "Creating independent watchOS apps" says a watch app's
purchases are shared with its companion iOS app. Nothing about Pro crosses WatchConnectivity.
Each device asks StoreKit, whose `Transaction.updates` also delivers a purchase made on the
other device, and the watch keeps Restore. App Store Connect took the first purchase with
iOS 1.0, whose build embeds the watch app, in one review submission (2026-10-09; the ship
gate at the top of `AppStore/Metadata.md`). On iPhone, Pro adds the voice coach; on the
watch, stronger taps.

## The iPhone app

The iPhone is where workouts are planned, run, looked back on and paid for. Since 1.1 a
workout runs on whichever device it is started on. Guideline 4.3(b) turns away "simple
timers"; Intervally answers it with the watch app, sync, Health and a Live Activity. Two
tabs, each with a gear for Settings:

- **Workouts.** The workout up next with Start, then the library, each card with a play
  button. Starting a workout makes it the one up next, here and on the watch. A preset's editor has a
  tile per number; each opens a wheel with exactly the values the crown turns over
  (`PresetField`, `ValueSteps`). Put on Watch makes it the watch's next workout. The
  editor hides the tab bar and sizes its ring to fit (`EditorLayout`), so on a 6.3" iPhone
  nothing is below the fold. Each tile a tap opens a picker for carries an up-and-down
  chevron, and until the first tile is tapped a line under the name says the name and
  tiles can be changed. Adding is
  gated as on the watch, and a purchase finishes what the paywall interrupted.
- **History.** The interval workouts either device saved to Health, grouped by week, each
  with its rounds, heart rate per interval and energy. History itself only reads. To Health
  the two apps are one app, and the newest request for a type decides it, so every request,
  a run's or History's, on either device, asks for the same types (`HealthAccess`).
- **Settings.** Intervally Pro, Theme, Sounds & Voice, the watch's status, the Apple Health
  explainer, Restore, Redeem Code and Request a Refund (iOS-only StoreKit sheets), Support
  and Privacy.

### Running on iPhone

The run is the watch's own `RunCoordinator`, compiled into both apps from `Run/` with the
engine, the Health workout session and the notification backstop. Only the edges differ:

- **What keeps it going.** iOS 26 runs an `HKWorkoutSession` on iPhone, which keeps the app
  executing with the phone locked and saves the workout, segmented by interval, to Health.
  With Health declined there is no second tier (`ForegroundRuntime`): the run counts in front
  and the notification backstop marks each change while the app is away. iOS hands back a
  session that outlived a crash through `UIScene.ConnectionOptions.shouldHandleActiveWorkoutRecovery`
  (`PhoneAppDelegate`), and a run interrupted by a termination is restored from its snapshot.
- **Cues** (`PhoneCuePlayer`, `CuePlan`, `CueAudio`). Synthesized tones, higher for work and
  lower for rest, a 3-2-1 tick, a finish chime, and with Pro the voice coach ("Work", "Rest",
  "Last round"). The audio session ducks other audio only while a cue sounds. The `audio`
  background mode is for those cues: the app never plays silence to stay running. A change
  announced late, after the app was away, plays nothing.
- **Live Activity** (`IntervallyPhoneWidget`, `LiveActivityPresenter`). The phase, its
  countdown and bar on the Lock Screen, in the Dynamic Island and in a paired watch's Smart
  Stack, updated at each change through one serial chain. Its stale date is a moment after
  the phase ends, when it falls back to the whole workout's countdown, which no update can
  make wrong. Leftover activities are settled at launch, before a run is restored.
- **The screen** (`PhoneRunView`). The watch's dial at iPhone size, with End, Pause and Skip,
  a flash of the phase's colour at each change, and the screen kept awake (Settings > Sounds
  & Voice). Never close a simulator's app mid-run in QA: the simulator keeps the dead
  process's workout session until it is rebooted.

Every screen works with no paired watch, and on iPad, where the app runs in compatibility
mode and `WCSession.isSupported()` is false: only the words about a watch go. The first
launch shows one welcome screen with the watch's status, and never a permission prompt.

## Sync

The iPhone and the watch keep the same presets and the same next workout over
WatchConnectivity, with no server. Each device's own store stays primary: with no
counterpart, as on iPad or a Family Setup watch, sync simply idles.

- **What travels.** One `SyncDocument`: every preset as a last-writer-wins record whose
  place in the list is a register of its own, so a reorder on the iPhone and an edit on the
  watch both survive; deletes as tombstones; and the selection as one more register. All are
  stamped by a hybrid logical clock so a watch whose clock runs behind still wins with a
  later edit. The three starters have
  fixed IDs, so two fresh installs merge to three presets, not six. A merge is commutative,
  idempotent and associative (`SyncDocumentTests` runs 2,000 seeded two-device histories).
- **How.** `WatchSync` sends the whole document with `updateApplicationContext(_:)`, both
  ways. It reaches an app that isn't running and replaces anything older still undelivered.
  The receiver merges, never replaces, and replies only when the merge holds something the
  sender lacks, so the two settle within two exchanges. A burst of edits, such as the crown
  turning through values, goes as one send.
- **The watch in the background.** A WatchConnectivity wake is held until the context has
  merged, and handed back after at most 15 s (`ConnectivityWakes`). The complication reloads
  only when the next workout changed.
- **The theme** travels beside the document, under a context key of its own
  (`SyncWire.themeKey`): one last-writer-wins register (`ThemeStore`), stamped later than
  any choice the device has made or seen. A version that predates themes reads only the
  document, so it ignores the theme and its document still compares equal; it is never
  answered for the theme's sake, and a theme never chosen is never a reason to send. A
  value from a later version is kept and passed on, and shows as Classic.
- **Never synced:** a run in progress (it carries its own copy of the workout), Pro (StoreKit
  answers on each device), the other settings and Health data. A stored document that won't
  decode suspends sync rather than being overwritten.

## Themes

Classic is the free look: black, with blue for work. Pastel, Intervally Pro, puts pink where
the blue is and soft versions of the other phase colours. One choice, in Settings > Theme on
either device; the other follows over sync. Each device stores it beside its presets (on the
watch in the App Group, so the complication wears it too).

- **Every colour comes from a `Palette`** (Theme.swift): fills for rings, flashes and the
  one tinted control; dimmed fills for Always-On; inks for phase-coloured text; and the
  iPhone's surfaces. Each root sets `\.palette` from the effective theme, and every view
  reads it, so a new theme redraws every screen in place, sheets and pushed screens
  included. `Theme`'s statics stay as Classic's colours.
- **iPhone Pastel is a light appearance:** warm white canvas, pale pink cards, dark text,
  deeper inks for coloured text, and `.preferredColorScheme(.light)` at the root so bars,
  glass and lists follow (the Info.plist keeps the app Dark for Classic). Bar buttons and
  neutral glass stay in the label colour (`neutralGlass()`), as in Classic. The Home Screen
  icon follows the theme: Pastel's alternate icon while Pastel shows, the dumbbell otherwise
  (`AppIconFollower`; a change that lands in the background waits for the foreground).
- **The watch keeps its black screen** in Pastel, as Apple's watchOS guidance asks of a
  workout app, and wears Pastel's colours on it: rings, labels, tinted controls, the flash,
  the completion screen (pink where Classic's is blue) and the Always-On variants. Titles
  take the accent through `accentTitle()`; Setup's paged titles ignore every SwiftUI tint
  (watchOS draws them in the asset catalog's AccentColor), so Pastel draws those two itself
  where the system's go (`PageTitle`). watchOS has no alternate icons.
- **Contrast** is measured and pinned for both themes (`PaletteContrastTests`): every fill
  at 7:1 or better on black, black text on every fill and dimmed fill, and every iPhone ink
  at 5:1 or better on Pastel's cards.

## Layout

```
Core/       model compiled into the iPhone app, the watch app and the widget
  IntervalWorkout.swift    settings (lead-in, warmup, work/rest/rounds, cooldown), clamped
  IntervalPlan.swift       immutable expanded schedule + pure position(atElapsed:)
  WorkoutStore.swift       presets and in-flight run persistence; local edits stamp the
                           sync document, merge(_:) folds in the other device's
  SyncDocument.swift       the presets and selection the iPhone and watch replicate:
                           last-writer-wins records + tombstones on a hybrid logical clock
  ValueSteps.swift         the crown's and the pickers' value tables
  PresetField.swift        a preset's numbers as tiles show them: title, colour, range and
                           values, shared by the watch's setup tiles and the iPhone's editor
  PresetNaming.swift       "Tabata" → "Tabata 2" for duplicates
  HealthMetadata.swift     the tags the watch writes to Health and History reads back
  HealthAccess.swift       what each app asks Health for: the watch's request covers the
                           iPhone's, since both are one app to Health
  SharedDefaults.swift     the App Group on the watch; the app's own defaults on iPhone
  Theme.swift              Classic's colours, and every theme's `Palette` for each device
  ThemeStore.swift         the chosen theme: a last-writer-wins register both devices share
  UnitTestHost.swift       keeps the real ProStore off in either test host
Shared/     watch app and widget only
  RunProgress.swift        what a persisted run looks like at an instant (drives the widget)
  StartWorkoutIntent.swift App Intents + Siri phrases
Phone/                     the iPhone companion: App/ (services, the two tabs, DEBUG QA
                           flags), Welcome/, Workouts/, Editor/, History/ (sessions read
                           from Health, SessionSummary, Session Detail), Pro/ (paywall,
                           offer codes and refunds), Settings/ (incl. Watch Status and the
                           Apple Health explainer), Components/, Resources/
Sources/                   the watch app (Pro/, Sync/ and Views/ProgressRing.swift also build
                           for iPhone)
  App/                     @main App + WKApplicationDelegate; ConnectivityWakes holds a
                           WatchConnectivity background wake until sync has merged it
  Model/TimerEngine.swift  anchor-based run state machine
  Pro/                     Intervally Pro: the free tier's limits and ProGating, ProStore
                           (the only StoreKit code, with Phone/Pro's iOS-only extension), and
                           PaywallContent, the paywall's words for the watch and the iPhone
  Sync/                    WatchSync: the presets over WatchConnectivity, one application
                           context each way, merged and never replaced; SyncTransport wraps
                           WCSession so the tests can stand in for it
  Session/                 workout session, extended runtime, notifications, haptics
    HapticPlayer.swift     plays a boundary's taps, repeats included, and cancels them
    RunDependencies.swift  the protocols RunCoordinator is built against, so its tier and
                           backstop logic is testable without HealthKit or WatchKit
  Views/                   setup, run, presets, settings, paywall, tap strength, ring,
                           shared dial geometry
StoreKit/                  local StoreKit configuration (test bundle and Run action only)
Widget/                    Smart Stack complication + Control Center control
Tests/                     Swift Testing, watch app
PhoneTests/                Swift Testing, iPhone app
SyncTests/                 Swift Testing, compiled into both bundles: sync runs on both devices
TestSupport/               helpers for both bundles: the App Store listing's parser
AppStore/                  Metadata.md (the App Store Connect listing, checked by tests) and
                           Screenshots/ (iPhone 6.9" and 6.3", Watch, the purchase's review
                           shot, and compose.py, which captions the iPhone captures)
Design/AppIcon/            the icon's generator; one PNG serves the iPhone and the watch
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
  Buy; and the Rename sheet that opens after a purchase from New Preset. ("COOLDOWN" on the
  40mm run screen used to truncate to "COOLDO…": a tracked Text ignored its
  minimumScaleFactor. `PhaseWord` now drops the tracking before it shrinks; seen whole on
  the 40mm simulator, and `PhaseWordTests` measures every phase word against the 40mm line.)
- Pastel's Home Screen icon switches in the iPhone simulator, but the simulator can't show
  iOS's "You have changed the icon" alert: the call reports an error although the icon
  changes, and after that the simulator's `lsd` can refuse later changes ("Resource
  temporarily unavailable") until it restarts. Check the alert and both directions on a
  device.
- A privacy manifest ships in each bundle: `Supporting/PrivacyInfo.xcprivacy` in the watch
  app and the widget, `Phone/Resources/PrivacyInfo.xcprivacy` in the iPhone app. Nothing is
  collected; presets go only between the user's own devices.
- Only devices can show: WatchConnectivity's background wakes and their limits, watch
  switching, Health bringing a watch workout to the iPhone, and an iPhone purchase reaching
  the watch. Simulators passed each data path; none of them enforces the real limits.

## Shipping

- Privacy policy: https://josiahrininger.com/intervally/privacy
- Support: https://josiahrininger.com/intervally/support
- App Store listing copy, review notes, the In-App Purchase record and screenshots:
  `AppStore/`. `MetadataTests` checks the listing against Apple's field limits and the app;
  `PhoneMetadataTests` checks the iPhone's words in it, and `ShipAssetsTests` the icon and
  every screenshot's size and alpha.
- Archive the `IntervallyPhone` scheme only. Its archive carries the watch app, so one
  upload is one iOS version with both apps.
