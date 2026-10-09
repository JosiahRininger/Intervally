//
//  WorkoutsView.swift
//  IntervallyPhone
//

import SwiftUI

/// The preset library, as the iPhone holds it: where the watch stands, the preset the watch
/// will start next, then every preset.
struct WorkoutsView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(ProStore.self) private var pro
    @Environment(WatchSync.self) private var sync

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    WatchStatusCard(content: WatchStatusContent(
                        peer: sync.peer,
                        lastSentAt: sync.lastSentAt,
                        lastReceivedAt: sync.lastReceivedAt
                    ))

                    SectionLabel("Up Next")
                    PresetCard(content: PresetCardContent(workout: store.selected, isPro: pro.isPro))

                    SectionLabel("Library")
                    ForEach(store.workouts) { workout in
                        PresetCard(content: PresetCardContent(workout: workout, isPro: pro.isPro))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            // Every phase colour's contrast was measured on black (Theme.swift).
            .background(.black)
            .navigationTitle("Workouts")
        }
    }
}

/// A small uppercase heading over a group of cards.
private struct SectionLabel: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.phaseLabel)
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(.secondary)
            .padding(.top, 12)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    let store = WorkoutStore(defaults: UserDefaults(suiteName: "preview.workouts") ?? .standard)
    WorkoutsView()
        .environment(store)
        .environment(ProStore(defaults: UserDefaults(suiteName: "preview.pro") ?? .standard))
        .environment(WatchSync(store: store))
}
