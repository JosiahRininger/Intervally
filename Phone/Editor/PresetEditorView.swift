//
//  PresetEditorView.swift
//  IntervallyPhone
//

import StoreKit
import SwiftUI

/// The editor's ring: as large as lets the whole editor fit on screen, from 160 to 220 points.
/// At a fixed 220, a 6.3-inch iPhone had to scroll to reach Warmup and Cooldown, which sat
/// under the pinned buttons.
enum EditorLayout {
    /// Down to 120, as the welcome's: with the tab bar under the pinned Start, a 6.3-inch
    /// iPhone needs about that much to show every tile.
    static let ringSides: ClosedRange<CGFloat> = 120...220
    /// The first-run line under the name, and where its dismissal is kept (per iPhone).
    static let tip = "Tap the name or any tile to change it."
    static let tipSeenKey = "phone.editorTipSeen.v1"
    /// The ring's top padding, the gap below it and the stack's bottom padding.
    static let chrome: CGFloat = 8 + 24 + 24

    /// For the scroll view's visible height and the height of everything below the ring. Until
    /// both are measured, the full size.
    static func ringSide(visibleHeight: CGFloat, belowRing: CGFloat) -> CGFloat {
        guard visibleHeight > 0, belowRing > 0 else { return ringSides.upperBound }
        let room = (visibleHeight - belowRing - chrome).rounded(.down)
        return min(ringSides.upperBound, max(ringSides.lowerBound, room))
    }
}

/// One preset, edited in place: every change is saved and synced as it is made, as on the
/// watch, so there is nothing to save and nothing to lose.
///
/// The workout's shape as a large ring, its name, then a tile for each number. The warmup
/// and cooldown are Intervally Pro: locked for a free user, each opens the paywall, and a
/// purchase there goes straight on to the picker that was asked for.
struct PresetEditorView: View {
    let presetID: UUID
    /// Just added with +: the name field starts empty and focused, its default showing as the
    /// placeholder, so typing names it and leaving it alone keeps the default.
    var isNew = false
    /// Opens another preset's editor: the copy Duplicate made.
    var open: (UUID) -> Void = { _ in }

    @Environment(WorkoutStore.self) private var store
    @Environment(ProStore.self) private var pro
    @Environment(WatchSync.self) private var sync
    @Environment(PhoneRun.self) private var run
    @Environment(ReviewLedger.self) private var reviews
    @Environment(\.requestReview) private var requestReview
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.palette) private var palette

    @State private var sheet: Sheet?
    @State private var followUp = PaywallFollowUp<FollowUp>()
    @State private var confirmingDelete = false
    @State private var name = ""
    @FocusState private var nameFocused: Bool
    /// Coming back from the copy Duplicate opened must not empty and refocus the name again.
    @State private var hasAppeared = false
    /// Until the first picker opens on this iPhone, a line under the name says the tiles
    /// can be tapped. Once someone has found them it only takes room.
    @AppStorage(EditorLayout.tipSeenKey) private var tipSeen = false
    @State private var visibleHeight: CGFloat = 0
    @State private var belowRing: CGFloat = 0

    enum Sheet: Hashable, Identifiable {
        case picker(PresetField)
        case activity
        case paywall(PaywallContext)
        var id: Self { self }
    }

    /// What a paywall opened from here was on the way to.
    enum FollowUp: Equatable {
        case pick(PresetField)
        case duplicate
    }

    private var workout: IntervalWorkout? {
        store.workouts.first { $0.id == presetID }
    }

    private var actions: PresetActions { PresetActions(store: store, pro: pro) }

    /// At the accessibility sizes the capsules wrap to two lines and pinned ones would cover
    /// a third of the screen, so they follow the tiles instead.
    private var pinsActions: Bool { !typeSize.isAccessibilitySize }

    var body: some View {
        Group {
            if let workout {
                editor(workout)
            } else {
                // Deleted, here or on the watch: the screen closes itself.
                palette.canvas
            }
        }
        .onChange(of: workout == nil) { _, gone in
            if gone { dismiss() }
        }
        .sheet(item: $sheet, onDismiss: finishFollowUp) { sheet in
            switch sheet {
            case .picker(let field):
                if let workout {
                    ValuePickerSheet(field: field, value: workout[keyPath: field.keyPath]) { value in
                        set(field, to: value)
                    }
                    .paletteSheet()
                }
            case .activity:
                if let workout {
                    ActivityPickerSheet(current: workout.activityKind) { activity in
                        store.setActivity(workout.id, to: activity)
                    }
                    .paletteSheet()
                }
            case .paywall(let context):
                NavigationStack {
                    PhonePaywallView(context: context, isSheet: true) {
                        followUp.unlocked()
                        self.sheet = nil
                    }
                }
                .paletteSheet()
            }
        }
        #if DEBUG
        .modifier(EditorQAOpen(sheet: $sheet))
        #endif
    }

    private func editor(_ workout: IntervalWorkout) -> some View {
        let runs = workout.effective(isPro: pro.isPro)

        return ScrollView {
            VStack(spacing: 24) {
                hero(runs, side: EditorLayout.ringSide(visibleHeight: visibleHeight, belowRing: belowRing))
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        nameField(workout)
                        activityButton(workout)
                        if !tipSeen {
                            Text(EditorLayout.tip)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    tiles(workout, fields: [.work, .rest, .rounds, .prepare])
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Warmup & Cooldown")
                        tiles(workout, fields: [.warmup, .cooldown])
                    }
                    if !pinsActions {
                        actions(workout, stacked: true)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { belowRing = $0 }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .readableColumn()
        }
        // What shows between the navigation bar and the pinned bar, the tab bar under it too:
        // the scroll view's own height less its insets, however the bars come by them.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
        } action: { _, height in
            visibleHeight = height
        }
        .appCanvas()
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.hard, for: .bottom)
        // Pinned, so Start is never below the fold. A bar rather than an inset, so the tiles
        // fade out under it instead of showing through its glass.
        .safeAreaBar(edge: .bottom) {
            // Not while the name is typed: it would ride on the keyboard over the tiles.
            if pinsActions && !nameFocused {
                actions(workout, stacked: false)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .readableColumn()
            }
        }
        // Kept for the back button and VoiceOver; the name field right under the ring is the
        // visible title.
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbar { menu(workout) }
        // The tabs stay, as in Apple's own apps: hidden here, they only came back once Back's
        // animation had finished, a beat after the workouts were already showing. The ring
        // gives up the room they take (EditorLayout.ringSide).
        .confirmationDialog("Delete “\(workout.name)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Workout", role: .destructive) {
                if actions.delete(workout) { dismiss() }
            }
        } message: {
            Text(WorkoutsContent.deleteMessage(peer: sync.peer))
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            name = isNew ? "" : workout.name
            if isNew { nameFocused = true }
        }
        .onChange(of: workout.name) { _, stored in
            // A rename that arrived from the watch, while this field isn't being typed in.
            if !nameFocused { name = stored }
        }
    }

    // MARK: - Hero

    /// The workout that will run, as one ring with its total inside: without Pro, without its
    /// bookends, exactly as the watch would run it.
    private func hero(_ runs: IntervalWorkout, side: CGFloat) -> some View {
        ZStack {
            SegmentedRing(plan: IntervalPlan(workout: runs), strokeRatio: 0.07)
            VStack(spacing: 4) {
                Text("Total")
                    .font(.phaseLabel)
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(.secondary)
                Text(DurationFormat.timer(runs.totalSeconds))
                    .font(.hero((52 * side / EditorLayout.ringSides.upperBound).rounded()))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                RhythmLine(workout: runs)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            // Narrow enough for the ring's chord at the rhythm line's height at 160 points,
            // where 0.15 let the line touch the ring at the largest text size.
            .padding(.horizontal, side * 0.19)
            // The ring is a fixed size, so the words inside stop growing where they would no
            // longer fit; the tiles below carry the same values at any size.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .frame(width: side, height: side)
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(runs.spokenSummary)
    }

    // MARK: - Name

    private func nameField(_ workout: IntervalWorkout) -> some View {
        // The stored name is the placeholder: an emptied field shows what it will go back to.
        TextField(workout.name, text: $name)
            .font(.system(.title2, design: .rounded).weight(.bold))
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .focused($nameFocused)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .tileBackground()
            .onSubmit { commitName() }
            .onChange(of: nameFocused) { _, focused in
                if !focused { commitName() }
            }
            .onDisappear { commitName() }
            .accessibilityLabel("Name")
    }

    // MARK: - Activity

    /// What Health records it as, under the name: small, as most presets keep HIIT.
    private func activityButton(_ workout: IntervalWorkout) -> some View {
        let activity = workout.activityKind
        return Button {
            tipSeen = true
            sheet = .activity
        } label: {
            HStack(spacing: 8) {
                Image(systemName: activity.symbolName)
                    .foregroundStyle(palette.workInk)
                Text(activity.title)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(palette.card, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Activity, \(activity.title)")
        .accessibilityHint("Changes what Apple Health records this workout as")
    }

    /// Saved when typing ends rather than on every key, so a rename is one edit to sync. An
    /// empty name puts the old one back.
    private func commitName() {
        guard var workout else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            name = workout.name
            return
        }
        name = trimmed
        // A rename is the tip followed as much as a tile is: it has done its job.
        if trimmed != workout.name { tipSeen = true }
        workout.name = trimmed
        store.update(workout)
    }

    // MARK: - Tiles

    /// Two to a row, or one at the accessibility text sizes, where a half-width tile cut its
    /// value short.
    private func tiles(_ workout: IntervalWorkout, fields: [PresetField]) -> some View {
        let columns = typeSize.isAccessibilitySize ? 1 : 2
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
            ForEach(fields, id: \.self) { field in
                EditorTile(content: EditorTileContent(field: field, workout: workout, isPro: pro.isPro)) {
                    tap(field)
                }
            }
        }
    }

    private func tap(_ field: PresetField) {
        tipSeen = true
        if field.isPro && !pro.isPro {
            followUp.open(for: .pick(field))
            sheet = .paywall(.bookends)
        } else {
            sheet = .picker(field)
        }
    }

    private func set(_ field: PresetField, to value: Int) {
        guard var workout else { return }
        workout[keyPath: field.keyPath] = value
        store.update(workout)
    }

    // MARK: - Start and Put on Watch

    /// Start, the screen's one tinted control, and beside it, with a watch, Start on Watch;
    /// Put on Watch where the watch app can't be woken yet, and in the menu otherwise.
    private func actions(_ workout: IntervalWorkout, stacked: Bool) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Button {
                // A name still being typed is part of the workout that starts.
                commitName()
                run.start(workout)
            } label: {
                Label(WorkoutsContent.startTitle, systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .prominentCapsule()
            .accessibilityLabel("Start \(workout.name)")
            if sync.peer == .ready {
                Button {
                    commitName()
                    run.startOnWatch(workout)
                } label: {
                    Label(WorkoutsContent.startOnWatchTitle, systemImage: "applewatch")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .neutralGlass()
                .accessibilityLabel("Start \(workout.name) on Apple Watch")
            } else if sync.peer.hasWatch {
                putOnWatch(workout)
            }
        }
    }

    /// Neutral glass beside Start. Once this is the preset the watch starts next it says so,
    /// with nothing left to tap.
    @ViewBuilder
    private func putOnWatch(_ workout: IntervalWorkout) -> some View {
        if actions.isUpNext(workout) {
            Label("On your watch", systemImage: "checkmark")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 52)
                .glassEffect(.regular, in: .capsule)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Up next on your watch")
        } else {
            Button {
                actions.putOnWatch(workout)
                reviews.ask(.sentToWatch, using: requestReview)
            } label: {
                Label(WorkoutsContent.putOnWatchTitle, systemImage: "applewatch")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .neutralGlass()
            .accessibilityHint("Makes this the workout your watch starts next")
        }
    }

    // MARK: - Menu

    @ToolbarContentBuilder
    private func menu(_ workout: IntervalWorkout) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if sync.peer == .ready, !actions.isUpNext(workout) {
                    Button {
                        actions.putOnWatch(workout)
                        reviews.ask(.sentToWatch, using: requestReview)
                    } label: {
                        Label(WorkoutsContent.putOnWatchTitle, systemImage: "applewatch")
                    }
                }
                Button {
                    duplicate()
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(!actions.canDelete)
            } label: {
                Image(systemName: "ellipsis")
            }
            .neutralGlass()
            .accessibilityLabel("More")
        }
    }

    /// Opens the copy's editor, or the paywall at the free limit.
    private func duplicate() {
        // A name still being typed belongs to this preset, not to its copy.
        commitName()
        guard let workout else { return }
        switch actions.duplicate(workout) {
        case .edit(let copy):
            open(copy.id)
        case .paywall:
            followUp.open(for: .duplicate)
            sheet = .paywall(.presets)
        }
    }

    /// Runs as a sheet closes. Only a paywall that unlocked Pro leaves anything to finish.
    private func finishFollowUp() {
        switch followUp.closed() {
        case .pick(let field): sheet = .picker(field)
        case .duplicate: duplicate()
        case nil: break
        }
    }
}

#Preview {
    let store = WorkoutStore(defaults: UserDefaults(suiteName: "preview.editor") ?? .standard)
    NavigationStack {
        PresetEditorView(presetID: store.selected.id)
    }
    .environment(store)
    .environment(ProStore(defaults: UserDefaults(suiteName: "preview.pro") ?? .standard))
    .environment(WatchSync(store: store))
    .environment(ReviewLedger(defaults: UserDefaults(suiteName: "preview.reviews") ?? .standard))
}
