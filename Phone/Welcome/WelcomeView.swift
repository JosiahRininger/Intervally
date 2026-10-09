//
//  WelcomeView.swift
//  IntervallyPhone
//

import SwiftUI

/// Whether the first-launch welcome has been seen. Per iPhone: nothing about it syncs.
enum Welcome {
    static let seenKey = "phone.welcomeSeen.v1"

    /// The ring's side, for a visible height above Continue: whatever the words and the
    /// watch's install steps leave (about 410 points at the default text size), from 140 to
    /// 220. At 220 on an iPhone SE the install steps ran under Continue.
    static func ringSide(forHeight height: CGFloat) -> CGFloat {
        min(220, max(140, (height - 410).rounded()))
    }
}

/// The first launch, once: what Intervally is, where the watch stands, and Continue. No
/// permission prompts and no dead end: Continue always leads to the workouts.
struct WelcomeView: View {
    let onContinue: () -> Void

    @Environment(WatchSync.self) private var sync
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How much of the ring is drawn: it draws itself in once, then stays.
    @State private var drawn: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                ring
                    .padding(.top, 32)

                VStack(spacing: 12) {
                    Text("An interval timer for Apple Watch.")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Build workouts here. Train on your wrist.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                WatchStatusCard(content: WatchStatusContent(
                    peer: sync.peer,
                    lastSentAt: sync.lastSentAt,
                    lastReceivedAt: sync.lastReceivedAt
                ))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .appCanvas()
        .safeAreaBar(edge: .bottom) {
            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .prominentCapsule()
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .onAppear {
            guard drawn == 0 else { return }
            if reduceMotion {
                drawn = 1
            } else {
                withAnimation(.easeOut(duration: 1.4).delay(0.2)) { drawn = 1 }
            }
        }
    }

    /// Classic, the first starter, as the watch draws it.
    private var ring: some View {
        SegmentedRing(plan: IntervalPlan(workout: WorkoutStore.starterWorkouts[0]), strokeRatio: 0.07)
            .mask {
                Circle()
                    .trim(from: 0, to: drawn)
                    .stroke(style: StrokeStyle(lineWidth: 40))
                    .rotationEffect(.degrees(-90))
                    .padding(8)
            }
            .aspectRatio(1, contentMode: .fit)
            .containerRelativeFrame(.vertical) { height, _ in Welcome.ringSide(forHeight: height) }
            .accessibilityHidden(true)
    }
}

#Preview {
    let store = WorkoutStore(defaults: UserDefaults(suiteName: "preview.welcome") ?? .standard)
    WelcomeView {}
        .environment(WatchSync(store: store))
}
