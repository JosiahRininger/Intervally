//
//  WorkoutsView.swift
//  IntervallyPhone
//

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

    static func upNextTitle(peer: PeerState) -> String {
        peer.hasWatch ? "Up next on your watch" : "Up next"
    }

    /// Under the delete confirmation. Only an iPhone with a watch has one to remove it from.
    static func deleteMessage(peer: PeerState) -> String {
        peer.hasWatch ? "It's removed from your watch too." : "This can't be undone."
    }

    /// Until the watch has sent its presets once, its own edits are only on the watch. Shown
    /// only with the watch app installed: before that, Settings explains what to do.
    static func showsWatchHint(peer: PeerState, lastReceivedAt: Date?) -> Bool {
        peer == .ready && lastReceivedAt == nil
    }
}

/// The preset library: the preset the watch starts next, then every preset.
///
/// A list rather than a scroll view of cards, for swipe to delete and Edit's reorder. Only
/// adding is gated: + and Duplicate at the free limit open the paywall first, and finish
/// once a purchase there unlocks Pro.
struct WorkoutsView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(ProStore.self) private var pro
    @Environment(ReviewLedger.self) private var reviews
    @Environment(\.requestReview) private var requestReview
    @Environment(WatchSync.self) private var sync

    @State private var path: [WorkoutsRoute] = []
    @State private var sheet: Sheet?
    @State private var followUp = PaywallFollowUp<FollowUp>()
    @State private var editMode: EditMode = .inactive

    enum Sheet: String, Identifiable {
        case paywall, settings
        var id: Self { self }
    }

    /// What a paywall opened from here was on the way to.
    enum FollowUp: Equatable {
        case addNew
        case duplicate(UUID)
    }

    private var actions: PresetActions { PresetActions(store: store, pro: pro) }

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
            .listStyle(.plain)
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
            case .paywall:
                NavigationStack {
                    PhonePaywallView(context: .presets, isSheet: true) {
                        followUp.unlocked()
                        self.sheet = nil
                    }
                }
                .paletteSheet()
            case .settings:
                PhoneSettingsView()
                    .paletteSheet()
            }
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
        return Button {
            path.append(.editor(selected.id, isNew: false))
        } label: {
            UpNextCard(
                content: PresetCardContent(workout: selected, isPro: pro.isPro),
                title: WorkoutsContent.upNextTitle(peer: sync.peer),
                showsWatch: sync.peer.hasWatch
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the editor")
    }

    private func libraryCard(_ workout: IntervalWorkout) -> some View {
        Button {
            path.append(.editor(workout.id, isNew: false))
        } label: {
            PresetCard(
                content: PresetCardContent(workout: workout, isPro: pro.isPro),
                isUpNext: sync.peer.hasWatch && actions.isUpNext(workout)
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if actions.canDelete {
                Button(role: .destructive) {
                    actions.delete(workout)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .contextMenu {
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
                    actions.delete(workout)
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
            sheet = .paywall
        }
    }

    /// Runs as a sheet closes. Only a paywall that unlocked Pro leaves anything to finish.
    private func finishFollowUp() {
        switch followUp.closed() {
        case .addNew:
            addNew()
        case .duplicate(let id):
            if let source = store.workouts.first(where: { $0.id == id }) { duplicate(source) }
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
