//
//  WorkoutsView.swift
//  IntervallyPhone
//

import StoreKit
import SwiftUI

/// A screen pushed on the Workouts stack.
enum WorkoutsRoute: Hashable {
    /// A preset's editor. `isNew` focuses the name, as the preset was just added.
    case editor(UUID, isNew: Bool)
}

/// What the Workouts screen says about the watch, worked out apart from the view.
enum WorkoutsContent {
    static let watchHint = "Open Intervally on your watch to bring your presets over."
    /// Makes a preset the one the watch starts next, from the library's menu and the editor.
    static let putOnWatchTitle = "Put on Watch"
    /// Wakes the watch and runs the workout there, shown live on this iPhone.
    static let startOnWatchTitle = "Start on Watch"
    /// Runs a workout on this iPhone.
    static let startTitle = "Start"

    /// The same words with a watch or without: the workout up next is the one either device
    /// starts. Where there is a watch the card adds its glyph.
    static func upNextTitle(peer: PeerState) -> String {
        "Up next"
    }

    /// Under the delete confirmation (`confirmsDelete`). Only an iPhone with a watch has one
    /// to remove it from.
    static func deleteMessage(on device: DeviceKind, peer: PeerState) -> String {
        guard device == .phone else { return "It will be removed from this iPad." }
        return peer.hasWatch ? "It will be removed from this iPhone and your Apple Watch." : "It will be removed from this iPhone."
    }

    /// Until the watch has sent its presets once, its own edits are only on the watch. Shown
    /// only with the watch app installed: before that, Settings explains what to do.
    static func showsWatchHint(peer: PeerState, lastReceivedAt: Date?) -> Bool {
        peer == .ready && lastReceivedAt == nil
    }
}

/// The preset library: the workout up next with Start, then every preset, each with its own
/// play button.
///
/// A list rather than a scroll view of cards, for swipe to delete and Edit's reorder. Only
/// adding is gated: + and Duplicate at the free limit open the paywall first, and finish
/// once a purchase there unlocks Pro. The paywall from + also offers to edit a preset
/// instead. Delete, from a swipe or the menu, only asks: the preset goes once the question
/// is answered.
struct WorkoutsView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(PhoneRun.self) private var run
    @Environment(ProStore.self) private var pro
    @Environment(ReviewLedger.self) private var reviews
    @Environment(\.requestReview) private var requestReview
    @Environment(WatchSync.self) private var sync
    @Environment(\.palette) private var palette

    @State private var path: [WorkoutsRoute] = []
    @State private var sheet: Sheet?
    @State private var followUp = PaywallFollowUp<FollowUp>()
    @State private var editMode: EditMode = .inactive
    /// The preset a swipe or the menu asked to delete, until the question is answered.
    @State private var deleting: IntervalWorkout?

    enum Sheet: String, Identifiable {
        /// The paywall from + at the free limit, which also offers Edit a Starter Instead.
        case paywall
        /// The paywall from Duplicate at the free limit.
        case duplicatePaywall
        case settings
        var id: Self { self }

        /// Edit a Starter Instead, on the paywall from + alone: Duplicate was on the way to a
        /// copy of its own preset.
        var offersEditInstead: Bool { self == .paywall }
    }

    /// What a paywall opened from here was on the way to.
    enum FollowUp: Equatable {
        case addNew
        case duplicate(UUID)
        /// Edit a Starter Instead: this preset's editor, in place of a new one.
        case edit(UUID)
    }

    private var actions: PresetActions { PresetActions(store: store, pro: pro) }

    /// No editor pushed, and no sheet or delete question over the list.
    private var libraryInFront: Bool { path.isEmpty && sheet == nil && deleting == nil }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if WorkoutsContent.showsWatchHint(peer: sync.peer, lastReceivedAt: sync.lastReceivedAt) {
                    watchHint
                        .cardRow()
                }

                upNext
                    .cardRow()

                SectionLabel("Library")
                    .padding(.top, 14)
                    .cardRow()
                ForEach(store.workouts) { workout in
                    libraryCard(workout)
                        .cardRow()
                }
                .onMove { actions.move(fromOffsets: $0, toOffset: $1) }
            }
            // On the list, once, for every row's swipe and menu.
            .confirmsDelete(of: $deleting) { actions.delete($0) }
            .listStyle(.plain)
            .readableList()
            .environment(\.editMode, $editMode)
            .appCanvas()
            .navigationTitle("Workouts")
            .toolbar { toolbar }
            .navigationDestination(for: WorkoutsRoute.self) { route in
                switch route {
                case .editor(let id, let isNew):
                    PresetEditorView(presetID: id, isNew: isNew) { copy in
                        path.append(.editor(copy, isNew: false))
                    }
                }
            }
        }
        .sheet(item: $sheet, onDismiss: finishFollowUp) { sheet in
            switch sheet {
            case .paywall, .duplicatePaywall:
                NavigationStack {
                    PhonePaywallView(
                        context: .presets,
                        isSheet: true,
                        onUnlock: {
                            followUp.unlocked()
                            self.sheet = nil
                        },
                        // Read from the sheet itself: state set as it was presented isn't
                        // seen here yet.
                        editInstead: editInsteadAction(on: sheet)
                    )
                }
                .paletteSheet()
            case .settings:
                PhoneSettingsView()
                    .paletteSheet()
            }
        }
        // A rating prompt lands on the library only while nothing is over it.
        .onChange(of: libraryInFront, initial: true) { _, inFront in
            reviews.show(inFront ? .library : .other, in: .workouts)
        }
        #if DEBUG
        .modifier(WorkoutsQAOpen(path: $path, sheet: $sheet))
        #endif
    }

    // MARK: - Rows

    private var watchHint: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(WorkoutsContent.watchHint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .tileBackground()
    }

    private var upNext: some View {
        let selected = store.selected
        return UpNextCard(
            content: PresetCardContent(workout: selected, isPro: pro.isPro),
            title: WorkoutsContent.upNextTitle(peer: sync.peer),
            showsWatch: sync.peer.hasWatch,
            open: { path.append(.editor(selected.id, isNew: false)) },
            start: { run.start(selected) },
            startOnWatch: sync.peer == .ready ? { run.startOnWatch(selected) } : nil
        )
    }

    private func libraryCard(_ workout: IntervalWorkout) -> some View {
        // Side by side in one row, never one over the other: a list sends a tap anywhere in a
        // row to the row's button, and a play button laid over the card opened the editor.
        ZStack(alignment: .trailing) {
            Button {
                path.append(.editor(workout.id, isNew: false))
            } label: {
                PresetCard(
                    content: PresetCardContent(workout: workout, isPro: pro.isPro),
                    isUpNext: sync.peer.hasWatch && actions.isUpNext(workout),
                    reservesStart: !editMode.isEditing
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the editor")
            // The UI tests find a preset's card and its play button by the preset's name.
            .accessibilityIdentifier("workouts.preset.\(workout.name)")

            if !editMode.isEditing {
                Button {
                    run.start(workout)
                } label: {
                    // Drawn at an exact size, unlike a glass button style, which pads the
                    // circle past the room the card leaves for it.
                    Image(systemName: "play.fill")
                        .font(.body.weight(.bold))
                        .foregroundStyle(palette.onTint)
                        .frame(width: PresetCard.startSide, height: PresetCard.startSide)
                        .glassEffect(.regular.tint(palette.brand).interactive(), in: .circle)
                }
                .buttonStyle(.borderless)
                .padding(.trailing, PresetCard.startMargin)
                .accessibilityLabel("Start \(workout.name)")
                .accessibilityIdentifier("workouts.start.\(workout.name)")
            }
        }
        // No full swipe: in 1.2 it deleted the preset, on both devices, with nothing asked.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if actions.canDelete {
                // Red, without the destructive role: a destructive swipe button takes its row
                // off the list as it is tapped, so Cancel left the preset missing, and Delete
                // crashed the list, told to remove the row a second time.
                Button {
                    deleting = workout
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
        }
        .contextMenu {
            Button {
                run.start(workout)
            } label: {
                Label(WorkoutsContent.startTitle, systemImage: "play.fill")
            }
            if sync.peer == .ready {
                Button {
                    run.startOnWatch(workout)
                } label: {
                    Label(WorkoutsContent.startOnWatchTitle, systemImage: "applewatch")
                }
            }
            if sync.peer.hasWatch, !actions.isUpNext(workout) {
                Button {
                    actions.putOnWatch(workout)
                    reviews.ask(.sentToWatch, using: requestReview)
                } label: {
                    Label(WorkoutsContent.putOnWatchTitle, systemImage: "applewatch")
                }
            }
            Button {
                duplicate(workout)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            if actions.canDelete {
                Divider()
                Button(role: .destructive) {
                    deleting = workout
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                sheet = .settings
            } label: {
                Image(systemName: "gearshape")
            }
            .neutralGlass()
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("workouts.settings")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(editMode.isEditing ? "Done" : "Edit") {
                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
            }
            .neutralGlass()
            Button(action: addNew) {
                Image(systemName: "plus")
            }
            .neutralGlass()
            .accessibilityLabel("New Workout")
            .accessibilityHint(actions.canAdd ? "" : "Opens Intervally Pro")
            .accessibilityIdentifier("workouts.new")
        }
    }

    // MARK: - Actions

    private func addNew() {
        switch actions.addNew() {
        case .edit(let workout):
            editMode = .inactive
            path.append(.editor(workout.id, isNew: true))
        case .paywall:
            followUp.open(for: .addNew)
            sheet = .paywall
        }
    }

    /// The copy lands at the end of the list, here: Duplicate is a list action.
    private func duplicate(_ workout: IntervalWorkout) {
        if actions.duplicate(workout) == .paywall {
            followUp.open(for: .duplicate(workout.id))
            sheet = .duplicatePaywall
        }
    }

    private func editInsteadAction(on sheet: Sheet) -> (() -> Void)? {
        guard sheet.offersEditInstead, let starter = actions.starterToEdit else { return nil }
        return { editInstead(starter) }
    }

    /// Edit a Starter Instead, on the paywall from + at the free limit: the paywall closes and
    /// `starter` opens in its editor (`PresetActions.starterToEdit`). Nothing is added.
    private func editInstead(_ starter: IntervalWorkout) {
        followUp.instead(.edit(starter.id))
        sheet = nil
    }

    /// Runs as a sheet closes. Only a paywall that unlocked Pro, or whose Edit a Starter
    /// Instead was tapped, leaves anything to finish.
    private func finishFollowUp() {
        switch followUp.closed() {
        case .addNew:
            addNew()
        case .duplicate(let id):
            if let source = store.workouts.first(where: { $0.id == id }) { duplicate(source) }
        case .edit(let id):
            editMode = .inactive
            path.append(.editor(id, isNew: false))
        case nil:
            break
        }
    }
}

#Preview {
    let store = WorkoutStore(defaults: UserDefaults(suiteName: "preview.workouts") ?? .standard)
    WorkoutsView()
        .environment(store)
        .environment(ProStore(defaults: UserDefaults(suiteName: "preview.pro") ?? .standard))
        .environment(WatchSync(store: store))
        .environment(ReviewLedger(defaults: UserDefaults(suiteName: "preview.reviews") ?? .standard))
}
