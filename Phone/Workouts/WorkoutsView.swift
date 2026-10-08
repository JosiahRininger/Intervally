//
//  WorkoutsView.swift
//  IntervallyPhone
//

import SwiftUI

/// The preset library, as the iPhone holds it.
struct WorkoutsView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(ProStore.self) private var pro

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
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

#Preview {
    WorkoutsView()
        .environment(WorkoutStore(defaults: UserDefaults(suiteName: "preview.workouts") ?? .standard))
        .environment(ProStore(defaults: UserDefaults(suiteName: "preview.pro") ?? .standard))
}
