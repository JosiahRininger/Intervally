//
//  PresetListView.swift
//  Intervally
//

import SwiftUI

/// Choose, rename, duplicate, or remove saved interval presets.
///
/// Row actions live in swipe actions on both edges. watchOS dropped long-press menus in
/// version 7, so `.contextMenu` compiles here but never shows.
///
/// Free users keep up to three presets. At the limit, New Preset and Duplicate push the
/// paywall instead of adding; a purchase there pops back and makes the copy after all.
struct PresetListView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(ProStore.self) private var pro
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    /// The preset currently being renamed, if any.
    @State private var renaming: IntervalWorkout?
    @State private var copyGate = PresetCopyGate()

    var body: some View {
        let canAdd = pro.canAddPreset(currentCount: store.workouts.count)

        List {
            ForEach(store.workouts) { workout in
                row(for: workout, canAdd: canAdd)
            }

            Button {
                // A copy of the preset on screen, not a hard-coded 10/30/15/8: a new preset
                // is almost always a variant of the one the user was just looking at. The
                // rename sheet opens straight away so "Classic 2" need not stay that.
                copy(store.selected)
            } label: {
                HStack(spacing: 4) {
                    Label("New Preset", systemImage: "plus")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if !canAdd {
                        Spacer(minLength: 0)
                        ProBadge()
                    }
                }
            }
            .accessibilityHint(canAdd ? "" : "Opens Intervally Pro")
        }
        .accentTitle()
        .navigationTitle("Presets")
        .navigationBarTitleDisplayMode(.inline)
        // Pushed inside this sheet's own stack: a sheet over a sheet is unproven on watchOS,
        // and Back is the one-tap way out.
        .navigationDestination(item: $copyGate.paywallFor) { _ in
            PaywallView(context: .presets) { copyGate.unlocked() }
        }
        .onChange(of: copyGate.paywallFor) {
            // Runs as the paywall pops, by an unlock or by Back. The copy is added before
            // Rename is asked for, so even if watchOS drops a sheet presented mid-pop, the
            // copy exists and is selected.
            guard let id = copyGate.paywallClosed(),
                  let source = store.workouts.first(where: { $0.id == id }) else { return }
            renaming = duplicate(source)
        }
        .sheet(item: $renaming) { workout in
            RenamePresetView(workout: workout) { newName in
                // By id: `workout` is the copy from when the sheet opened, and the iPhone may
                // have changed the preset while the name was being dictated.
                store.rename(workout.id, to: newName)
                renaming = nil
            }
        }
    }

    private func row(for workout: IntervalWorkout, canAdd: Bool) -> some View {
        let isSelected = workout.id == store.selectedID

        return Button {
            store.selectedID = workout.id
            dismiss()
        } label: {
            HStack(spacing: 8) {
                // The workout's shape, so presets are told apart before their names are read.
                // The shape that will run: without Pro, that is without its bookends.
                SegmentedRing(
                    plan: IntervalPlan(workout: workout.effective(isPro: pro.isPro)),
                    strokeRatio: 0.15,
                    gap: 1
                )
                .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(workout.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle(for: workout))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.work)
                }
            }
        }
        .accessibilityLabel(workout.name)
        .accessibilityValue(subtitle(for: workout))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .swipeActions(edge: .leading) {
            Button {
                copy(workout)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .accessibilityHint(canAdd ? "" : "Opens Intervally Pro")
        }
        .swipeActions(edge: .trailing) {
            if store.workouts.count > 1 {
                Button(role: .destructive) {
                    store.delete(workout)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            Button {
                renaming = workout
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(palette.workDimmed)
        }
    }

    private func subtitle(for workout: IntervalWorkout) -> String {
        workout.rhythm
    }

    /// Copies `workout` and opens Rename, or — at the free limit — pushes the paywall. The
    /// gate is checked before `duplicate`, which adds to the store straight away.
    private func copy(_ workout: IntervalWorkout) {
        let canAdd = pro.canAddPreset(currentCount: store.workouts.count)
        guard copyGate.request(copyOf: workout.id, canAdd: canAdd) != nil else { return }
        renaming = duplicate(workout)
    }

    /// Appends a copy of `workout` under a name no other preset has. `add` also selects it.
    private func duplicate(_ workout: IntervalWorkout) -> IntervalWorkout {
        var copy = workout
        copy.id = UUID()
        copy.name = Self.uniqueName(after: workout.name, among: store.workouts.map(\.name))
        return store.add(copy)
    }

    /// "Tabata" → "Tabata 2". The rule lives in `PresetNaming`, shared with the iPhone; this
    /// forwarder keeps the watch's call sites and tests as they were.
    nonisolated static func uniqueName(after name: String, among taken: [String]) -> String {
        PresetNaming.uniqueName(after: name, among: taken)
    }
}

/// New Preset and Duplicate at the free limit, as a value so the flow is testable: the
/// paywall comes first, before anything is added, and the copy is made only after a
/// purchase has unlocked Pro and the paywall has popped. Back out without buying and
/// nothing is added.
struct PresetCopyGate: Equatable {
    /// The preset whose copy waits on the paywall. Non-nil pushes the paywall; nil pops it.
    var paywallFor: UUID?
    /// Set by an unlock and consumed once the paywall has popped.
    private(set) var pendingDuplicate: UUID?

    /// The preset to copy now, or nil when the paywall goes first.
    mutating func request(copyOf id: UUID, canAdd: Bool) -> UUID? {
        guard !canAdd else { return id }
        paywallFor = id
        return nil
    }

    /// Pro unlocked on the paywall: remember what to copy, and pop. An unlock that lands
    /// after the user already backed out (a slow purchase) remembers nothing, so it can't
    /// make a copy behind a later, unrelated paywall.
    mutating func unlocked() {
        pendingDuplicate = paywallFor
        paywallFor = nil
    }

    /// Once the paywall has popped, by an unlock or by Back: what to copy, if anything.
    mutating func paywallClosed() -> UUID? {
        guard paywallFor == nil else { return nil }
        defer { pendingDuplicate = nil }
        return pendingDuplicate
    }
}

/// Renames a preset. `TextField` on watchOS presents the system's own input methods —
/// dictation, Scribble and the keyboard — so no custom entry UI is needed.
struct RenamePresetView: View {
    let workout: IntervalWorkout
    let onCommit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            TextField("Name", text: $name)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit(commit)
                .scenePadding(.horizontal)
                .accentTitle()
                .navigationTitle("Rename")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // `.confirmationAction` is unavailable on watchOS; the sheet's own ✕
                    // takes the leading corner, so Save takes the trailing one. A glyph, not
                    // the word: "Save" as text clipped the title to "Renam" on a 40mm.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: commit) {
                            Image(systemName: "checkmark")
                        }
                        .disabled(trimmed.isEmpty)
                        .accessibilityLabel("Save")
                    }
                }
        }
        .onAppear { name = workout.name }
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commit() {
        guard !trimmed.isEmpty else { return }
        onCommit(trimmed)
        dismiss()
    }
}

#Preview {
    let store = WorkoutStore(defaults: UserDefaults(suiteName: "preview")!)
    let pro = ProStore()
    NavigationStack { PresetListView() }
        .environment(store)
        .environment(pro)
        // New Preset at the limit pushes the paywall, which plays Feel Strongest through it.
        .environment(RunCoordinator(store: store, pro: pro, haptics: HapticPlayer(strength: { .standard })))
}
