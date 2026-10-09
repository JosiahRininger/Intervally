//
//  PresetEditorView.swift
//  IntervallyPhone
//

import SwiftUI

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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var sheet: Sheet?
    @State private var followUp = PaywallFollowUp<FollowUp>()
    @State private var confirmingDelete = false
    @State private var name = ""
    @FocusState private var nameFocused: Bool
    /// Coming back from the copy Duplicate opened must not empty and refocus the name again.
    @State private var hasAppeared = false

    enum Sheet: Hashable, Identifiable {
        case picker(PresetField)
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

    /// At the accessibility sizes the capsule wraps to two lines and a pinned one would cover
    /// a third of the screen, so it follows the tiles instead.
    private var pinsPutOnWatch: Bool { !typeSize.isAccessibilitySize }

    var body: some View {
        Group {
            if let workout {
                editor(workout)
            } else {
                // Deleted, here or on the watch: the screen closes itself.
                Color.black
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
                }
            case .paywall(let context):
                NavigationStack {
                    PhonePaywallView(context: context, isSheet: true) {
                        followUp.unlocked()
                        self.sheet = nil
                    }
                }
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
                hero(runs)
                nameField(workout)
                tiles(workout, fields: [.work, .rest, .rounds, .prepare])
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Warmup & Cooldown")
                    tiles(workout, fields: [.warmup, .cooldown])
                }
                if sync.peer.hasWatch && !pinsPutOnWatch {
                    putOnWatch(workout)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .blackCanvas()
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.hard, for: .bottom)
        // Pinned, so the one thing this screen sends to the watch is never below the fold. A
        // bar rather than an inset, so the tiles fade out under it instead of showing through
        // its glass.
        .safeAreaBar(edge: .bottom) {
            // Not while the name is typed: it would ride on the keyboard over the tiles.
            if sync.peer.hasWatch && pinsPutOnWatch && !nameFocused {
                putOnWatch(workout)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        // Kept for the back button and VoiceOver; the name field right under the ring is the
        // visible title.
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbar { menu(workout) }
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
    private func hero(_ runs: IntervalWorkout) -> some View {
        let side: CGFloat = 220
        return ZStack {
            SegmentedRing(plan: IntervalPlan(workout: runs), strokeRatio: 0.07)
            VStack(spacing: 4) {
                Text("Total")
                    .font(.phaseLabel)
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(.secondary)
                Text(DurationFormat.timer(runs.totalSeconds))
                    .font(.hero(52))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                RhythmLine(workout: runs)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, side * 0.15)
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

    // MARK: - Put on Watch

    /// The screen's one tinted control while it does something. Once this is the preset the
    /// watch starts next it says so, in neutral glass: there is nothing left to tap.
    @ViewBuilder
    private func putOnWatch(_ workout: IntervalWorkout) -> some View {
        if actions.isUpNext(workout) {
            Label("Up next on your watch", systemImage: "checkmark")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .glassEffect(.regular, in: .capsule)
                .accessibilityElement(children: .combine)
        } else {
            Button {
                actions.putOnWatch(workout)
            } label: {
                Label(WorkoutsContent.putOnWatchTitle, systemImage: "applewatch")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .prominentCapsule()
            .accessibilityHint("Makes this the workout your watch starts next")
        }
    }

    // MARK: - Menu

    @ToolbarContentBuilder
    private func menu(_ workout: IntervalWorkout) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
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
}
