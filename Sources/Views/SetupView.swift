//
//  SetupView.swift
//  Intervally
//

import SwiftUI
import UserNotifications

/// The configuration screen: three vertical pages. The first is the workout as a dial —
/// its shape drawn as one segmented ring with Start beneath — the second is its four
/// numbers as a grid of tiles, and the third its warmup and cooldown, an Intervally Pro
/// feature.
///
/// No `List`. A list row has no room for a ring, and Start lived in one at a height that
/// did not fit its own capsule.
struct SetupView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(RunCoordinator.self) private var coordinator
    @Environment(ProStore.self) private var pro
    @Binding var isRunning: Bool
    /// Owned by the root, which closes it when a run starts from outside the app.
    @Binding var sheet: SetupSheet?

    @State private var page = 0

    /// A run is still going — the user swiped back from it. Start would only return them to
    /// it, so the button says so, rather than implying it begins the preset shown.
    ///
    /// Read when this screen appears rather than observed live. This view is the navigation
    /// root, and observing the engine made it a dependent of every state change a run
    /// makes — including the ones made while it is animating out underneath the run screen,
    /// which stalled the push for over a minute. `alertsOff` is read the same way for the
    /// same reason: the coordinator sets it from inside a run.
    @State private var hasActiveRun = false
    @State private var alertsOff = false

    var body: some View {
        TabView(selection: $page) {
            WorkoutPage(
                // What will run, so the ring and the total match it: without Pro, the
                // bookends are dropped here as they are when the run begins.
                workout: store.selected.effective(isPro: pro.isPro),
                hasActiveRun: hasActiveRun,
                alertsOff: alertsOff,
                start: { isRunning = true },
                showPresets: { sheet = .presets },
                showSettings: { sheet = .settings }
            )
            .tag(0)

            IntervalsPage()
                .tag(1)

            BookendsPage()
                .tag(2)
        }
        .tabViewStyle(.verticalPage)
        .containerBackground(Color.black, for: .navigation)
        .onAppear {
            hasActiveRun = coordinator.engine.isActive
            alertsOff = !coordinator.canNotify
        }
        .task {
            // The coordinator only learns this when a run asks for permission, so on a cold
            // launch it still reads as granted. Ask the system directly.
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if status == .denied { alertsOff = true }
        }
        .sheet(item: $sheet) { presented in
            NavigationStack {
                switch presented {
                case .presets: PresetListView()
                case .settings: SettingsView()
                }
            }
        }
    }
}

extension SetupView {
    /// What VoiceOver reads for the dial: the workout in the order it runs. A bookend is
    /// named only when it is on, as the ring only draws it then.
    nonisolated static func dialAccessibilityLabel(for workout: IntervalWorkout) -> String {
        var parts: [String] = []
        if workout.warmupSeconds > 0 {
            parts.append("\(DurationFormat.spoken(workout.warmupSeconds)) warmup")
        }
        parts.append("\(DurationFormat.spoken(workout.workSeconds)) work")
        parts.append(workout.restSeconds > 0 ? "\(DurationFormat.spoken(workout.restSeconds)) rest" : "no rest")
        parts.append(DurationFormat.rounds(workout.rounds))
        if workout.cooldownSeconds > 0 {
            parts.append("\(DurationFormat.spoken(workout.cooldownSeconds)) cooldown")
        }
        parts.append("total \(DurationFormat.spoken(workout.totalSeconds))")
        return "\(workout.name). " + parts.joined(separator: ", ")
    }

    /// The Settings button's glyph: a gear, or a bell once notifications are declined. The
    /// App Review notes describe the button by its place for that reason, and name both.
    nonisolated static func settingsSymbol(alertsOff: Bool) -> String {
        alertsOff ? "bell.slash.fill" : "gearshape.fill"
    }

    /// The word under a bookend in its editor. Nothing under "Off"; otherwise the unit the
    /// digits are read in, as for every other duration.
    nonisolated static func bookendUnit(_ seconds: Int) -> String {
        if seconds == 0 { return "" }
        return seconds < 60 ? "seconds" : "minutes"
    }
}

// MARK: - Page 1: the dial

/// The workout as a dial, on exactly the run screen's geometry: the same ring in the same
/// place, drawn as the workout's shape, with Start where Pause will be. Pressing Start
/// turns this ring into the countdown rather than replacing the screen.
///
/// There is no navigation title. The preset's name is the label inside the ring — the slot
/// that says WORK or REST once the run begins — which is what freed the ring to grow from
/// ~70pt to ~100pt on a 40mm watch.
private struct WorkoutPage: View {
    let workout: IntervalWorkout
    let hasActiveRun: Bool
    let alertsOff: Bool
    let start: () -> Void
    let showPresets: () -> Void
    let showSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let screen = CGSize(width: proxy.size.width, height: proxy.size.height + insets.top + insets.bottom)
            let dial = DialLayout(screen: screen)

            VStack(spacing: dial.gap) {
                ZStack {
                    SegmentedRing(
                        plan: IntervalPlan(workout: workout),
                        strokeRatio: 0.08
                    )
                    .frame(width: dial.diameter, height: dial.diameter)

                    dialContent(dial: dial)
                        .frame(width: dial.interior, height: dial.interior)
                }
                .frame(width: dial.diameter, height: dial.diameter)

                startButton(dial: dial)
            }
            .padding(.top, dial.ringTop)
            .padding(.bottom, dial.bottomMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: [.top, .bottom])
        }
        .containerBackground(Color.black, for: .tabView)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: showPresets) { Image(systemName: "list.bullet") }
                    .accessibilityLabel("Presets")
            }
            ToolbarItem(placement: .topBarTrailing) {
                // Notifications declined: the gear becomes the warning, and Settings explains
                // it. A line of text for this cost the 40mm a scrolling page that fought the
                // crown's paging.
                Button(action: showSettings) {
                    Image(systemName: SetupView.settingsSymbol(alertsOff: alertsOff))
                        .foregroundStyle(alertsOff ? Color.orange : Color.primary)
                }
                .accessibilityLabel(alertsOff ? "Settings, alerts are off" : "Settings")
            }
        }
    }

    /// Inside the ring, in the run screen's three slots: the preset's name where the phase
    /// word will be, the total where the countdown will be, and the work and rest times —
    /// in the colours the ring uses for them — where the round dots will be.
    private func dialContent(dial: DialLayout) -> some View {
        let interior = dial.interior
        let lineWidth = dial.chord(atOffset: 0.4 * interior)

        return VStack(spacing: 0) {
            Text(workout.name)
                .font(.phaseLabel)
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: lineWidth)

            // m:ss like the countdown it becomes, so the digits don't jump on Start.
            Text(DurationFormat.timer(workout.totalSeconds))
                .font(.hero(0.40 * interior))
                .foregroundStyle(.white)
                .lineLimit(1)
                // 99 rounds of an hour each is "198:03:00"; shrink rather than truncate.
                .minimumScaleFactor(0.45)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .snappy, value: workout.totalSeconds)
                .padding(.top, 2)

            ViewThatFits(in: .horizontal) {
                breakdown(withRounds: true)
                breakdown(withRounds: false)
            }
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .frame(maxWidth: lineWidth)
            .padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(SetupView.dialAccessibilityLabel(for: workout))
    }

    /// "30s · 15s · 8×". Rest is left out when there is none, rather than showing a green
    /// "0s" for a phase that never happens. The ring's segments already show the rounds,
    /// so a narrow dial drops them first. One `Text`, so a tight fit scales the whole line
    /// rather than truncating each number to "3…".
    private func breakdown(withRounds: Bool) -> some View {
        let separator = Text(" · ").foregroundStyle(.white.opacity(0.4))
        var line = Text(DurationFormat.clock(workout.workSeconds)).foregroundStyle(Theme.work)
        if workout.restSeconds > 0 {
            line = Text("\(line)\(separator)\(Text(DurationFormat.clock(workout.restSeconds)).foregroundStyle(Theme.rest))")
        }
        if withRounds {
            line = Text("\(line)\(separator)\(Text("\(workout.rounds)×").foregroundStyle(.white.opacity(0.7)))")
        }
        return line.minimumScaleFactor(0.7)
    }

    /// Centred where the run screen's End and Pause will sit, and the same height.
    private func startButton(dial: DialLayout) -> some View {
        Button(action: start) {
            Label(
                hasActiveRun ? "Resume" : "Start",
                systemImage: hasActiveRun ? "arrow.uturn.forward" : "play.fill"
            )
            .font(.headline)
            .frame(width: dial.capsuleWidth, height: dial.control)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(Theme.work)
        .foregroundStyle(Theme.onTint)
        // watchOS stretches bordered buttons to the full width unless told not to.
        .fixedSize()
        .handGestureShortcut(.primaryAction)
        .accessibilityHint(
            hasActiveRun
                ? "Returns to the workout in progress"
                : "Begins \(DurationFormat.rounds(workout.rounds)) of intervals"
        )
    }
}

// MARK: - Page 2: the grid

/// The four numbers as tiles, each pushing a crown editor bound to the stored workout.
private struct IntervalsPage: View {
    var body: some View {
        GeometryReader { proxy in
            // Two rows share the page. No total line: the total is page 1's hero. The tile
            // draws ~2pt inside its frame, so 48 keeps the visible card at the 44pt minimum.
            let tileHeight = max(48, (proxy.size.height - 8 - 4) / 2)

            VStack(spacing: 8) {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        PhaseTile(field: .work, height: tileHeight)
                        PhaseTile(field: .rest, height: tileHeight)
                    }
                    GridRow {
                        PhaseTile(field: .rounds, height: tileHeight)
                        PhaseTile(field: .prepare, height: tileHeight)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .scenePadding(.horizontal)
        .containerBackground(Color.black, for: .tabView)
        .navigationTitle("Intervals")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Page 3: warmup and cooldown

/// The two bookends: an easy phase before the first interval and one after the last. They
/// are Intervally Pro, so a free user sees them locked, with Unlock Pro beneath.
///
/// A page of their own rather than a third row on page 2, which would have needed 36pt
/// tiles (under the 48pt floor) or a scroll view, and a scroll view fought the crown's
/// paging before.
private struct BookendsPage: View {
    @Environment(ProStore.self) private var pro

    var body: some View {
        GeometryReader { proxy in
            // Page 2's tile height, so the two pages' tiles line up as the crown pages.
            let tileHeight = max(48, (proxy.size.height - 8 - 4) / 2)

            VStack(spacing: 8) {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    // Locked for a free user, but still a way in: each opens the paywall, which
                    // turns into the editor in place once Pro unlocks.
                    GridRow {
                        PhaseTile(field: .warmup, height: tileHeight)
                        PhaseTile(field: .cooldown, height: tileHeight)
                    }
                }

                if !pro.isPro {
                    unlockButton
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .scenePadding(.horizontal)
        .containerBackground(Color.black, for: .tabView)
        .navigationTitle("Warm & Cool")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// As wide as the tiles above it, so it is left to stretch: the glass style draws ~6pt
    /// outside its label on each side, so a fixed label that wide ran off the page.
    private var unlockButton: some View {
        NavigationLink(value: RootRoute.paywall(.bookends)) {
            Text("Unlock Pro")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(Theme.work)
        .foregroundStyle(Theme.onTint)
    }
}

// MARK: - Tiles

/// One tile of a setup grid, pushing its field's editor. Phase tiles carry the colour the
/// ring uses, which teaches the run screen's language before the workout starts.
private struct PhaseTile: View {
    let field: SetupField
    let height: CGFloat

    @Environment(WorkoutStore.self) private var store
    @Environment(ProStore.self) private var pro

    /// A free user's Pro tile: "PRO" and a lock where the value would be.
    private var locked: Bool { field.isPro && !pro.isPro }

    var body: some View {
        let value = store.selected[keyPath: field.keyPath]
        let title = field.title

        NavigationLink(value: RootRoute.field(field)) {
            VStack(alignment: .leading, spacing: 0) {
                // A 40mm tile is ~55pt inside, too narrow for "Get Ready"; it says "Ready"
                // there rather than truncating. No glyphs: the colour already says which
                // phase a tile is, and a glyph on three tiles of four looked like a mistake.
                ViewThatFits(in: .horizontal) {
                    tileTitle(title)
                    if let shortTitle = field.kind?.shortTitle, shortTitle != title {
                        tileTitle(shortTitle)
                    }
                }
                Spacer(minLength: 2)
                if locked {
                    Label("PRO", systemImage: "lock.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    // The value is the point of the tile, so it outranks the title clearly.
                    Text(field.tileText(value))
                        .font(.hero(min(30, 0.40 * height)))
                        .foregroundStyle(field.tint)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(locked ? "Locked" : field.spoken(value))
        .accessibilityHint(locked ? "Opens Intervally Pro" : "")
    }

    private func tileTitle(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            // "Rounds" has no shorter form and is ~2pt too wide for a 40mm tile; "Cooldown"
            // has none either and needs ~0.76 there. A shorter title wins before any of this
            // applies, so page 2 still says "Ready" rather than a shrunken "Get Ready".
            .minimumScaleFactor(0.75)
    }
}

// MARK: - Fields

/// A number the setup pages edit. A tile pushes its editor by value, which keeps the root
/// stack as data that a start from outside the app can clear (`RootNavigation`).
enum SetupField: Hashable, CaseIterable, Sendable {
    case work, rest, rounds, prepare, warmup, cooldown

    var title: String {
        switch self {
        case .work: "Work"
        case .rest: "Rest"
        case .rounds: "Rounds"
        case .prepare: "Get Ready"
        case .warmup: "Warmup"
        case .cooldown: "Cooldown"
        }
    }

    /// The phase it times. Rounds is structure, not a phase.
    var kind: IntervalPhase.Kind? {
        switch self {
        case .work: .work
        case .rest: .rest
        case .rounds: nil
        case .prepare: .prepare
        case .warmup: .warmup
        case .cooldown: .cooldown
        }
    }

    /// The warmup and cooldown are Intervally Pro.
    var isPro: Bool { self == .warmup || self == .cooldown }

    var keyPath: WritableKeyPath<IntervalWorkout, Int> {
        switch self {
        case .work: \.workSeconds
        case .rest: \.restSeconds
        case .rounds: \.rounds
        case .prepare: \.prepareSeconds
        case .warmup: \.warmupSeconds
        case .cooldown: \.cooldownSeconds
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .work: IntervalWorkout.workRange
        case .rest: IntervalWorkout.restRange
        case .rounds: IntervalWorkout.roundsRange
        case .prepare: IntervalWorkout.prepareRange
        case .warmup: IntervalWorkout.warmupRange
        case .cooldown: IntervalWorkout.cooldownRange
        }
    }

    /// The phase's colour. Rounds stays white rather than borrowing a meaning it doesn't have.
    var tint: Color { kind.map(Theme.light(for:)) ?? .white }

    /// The editor's glyph: the phase's own, or a loop for rounds.
    var symbolName: String { kind?.symbolName ?? "repeat" }

    /// The value as its tile shows it.
    func tileText(_ value: Int) -> String {
        switch self {
        case .rounds: "\(value)"
        case .warmup, .cooldown: DurationFormat.bookend(value)
        case .work, .rest, .prepare: DurationFormat.clock(value)
        }
    }

    /// The value as VoiceOver reads it, on the tile and in the editor.
    func spoken(_ value: Int) -> String {
        switch self {
        case .rounds: DurationFormat.rounds(value)
        case .warmup, .cooldown: DurationFormat.bookendSpoken(value)
        case .work, .rest, .prepare: DurationFormat.spoken(value)
        }
    }

    /// The crown editor its tile opens. The bookends turn over their own table in 30-second
    /// steps and say "Off" at zero; everything else keeps the editor's own schedule.
    @MainActor
    func editor(value: Binding<Int>) -> ValueEditorView {
        switch self {
        case .rounds:
            ValueEditorView(
                title: title, systemImage: symbolName, range: range, step: 1, tint: tint,
                format: { "\($0)" }, spoken: DurationFormat.rounds, value: value
            )
        case .work, .rest, .prepare:
            ValueEditorView(
                title: title, systemImage: symbolName, range: range, step: 5, tint: tint,
                format: DurationFormat.bare, spoken: DurationFormat.spoken, value: value
            )
        case .warmup, .cooldown:
            ValueEditorView(
                title: title, systemImage: symbolName, range: range, step: 30, tint: tint,
                format: DurationFormat.bookendEditor, spoken: DurationFormat.bookendSpoken,
                unit: SetupView.bookendUnit, valueTable: IntervalWorkout.bookendValues, value: value
            )
        }
    }
}

/// The editor a setup tile opens, bound to the selected preset. A bookend's sits behind
/// the Pro gate, which turns into the editor in place once Pro unlocks, so nothing has to
/// be resumed.
struct SetupFieldEditor: View {
    let field: SetupField

    @Environment(WorkoutStore.self) private var store

    var body: some View {
        if field.isPro {
            ProGate(context: .bookends) { editor }
        } else {
            editor
        }
    }

    private var editor: ValueEditorView {
        field.editor(value: store.selectedBinding(field.keyPath))
    }
}

private extension WorkoutStore {
    /// One field of the selected preset, saved on every change.
    func selectedBinding(_ keyPath: WritableKeyPath<IntervalWorkout, Int>) -> Binding<Int> {
        Binding {
            self.selected[keyPath: keyPath]
        } set: { newValue in
            var updated = self.selected
            updated[keyPath: keyPath] = newValue
            self.update(updated)
        }
    }
}
