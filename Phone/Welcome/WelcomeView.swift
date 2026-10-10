//
//  WelcomeView.swift
//  IntervallyPhone
//

import SwiftUI

/// Whether the first-launch welcome has been seen. Per iPhone: nothing about it syncs.
enum Welcome {
    static let seenKey = "phone.welcomeSeen.v1"

    /// A no-break space in "Apple Watch": the title wrapped as "Apple / Watch." on a 6.3".
    static let title = "An interval timer for iPhone and Apple\u{00A0}Watch."
    static let subtitle = "Press Start and hear every interval. With a watch, feel them on your wrist."

    /// What a run on this iPhone does, a line each. Beeps, never the voice coach: that is Pro.
    static let highlights: [(systemImage: String, text: String)] = [
        ("speaker.wave.2.fill", "Beeps that cut through music"),
        ("lock.iphone", "Countdown on your Lock Screen"),
        ("heart.fill", "Every session saved to Health"),
    ]

    static let ringSides: ClosedRange<CGFloat> = 120...220
    /// The ring's top padding and the gap under it.
    static let chrome: CGFloat = 32 + 28

    /// The ring's side, for the visible height above Continue and the height of everything
    /// under the ring: as large as lets it all show without scrolling, from 120 to 220. Until
    /// both are measured, the full size.
    static func ringSide(visibleHeight: CGFloat, belowRing: CGFloat) -> CGFloat {
        guard visibleHeight > 0, belowRing > 0 else { return ringSides.upperBound }
        let room = (visibleHeight - belowRing - chrome).rounded(.down)
        return min(ringSides.upperBound, max(ringSides.lowerBound, room))
    }
}

/// The first launch, once: what Intervally is, what a run here does, where the watch stands
/// when there is one, and Continue. No permission prompts and no dead end: Continue always
/// leads to the workouts.
struct WelcomeView: View {
    let onContinue: () -> Void

    @Environment(WatchSync.self) private var sync
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How much of the ring is drawn: it draws itself in once, then stays.
    @State private var drawn: CGFloat = 0
    @State private var visibleHeight: CGFloat = 0
    @State private var belowRing: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                ring(side: Welcome.ringSide(visibleHeight: visibleHeight, belowRing: belowRing))
                    .padding(.top, 32)

                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Text(Welcome.title)
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        Text(Welcome.subtitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                    highlights

                    // Only with a watch to speak of: without one, "No Apple Watch paired" on
                    // the first screen would read as something missing.
                    if sync.peer.hasWatch {
                        WatchStatusCard(content: WatchStatusContent(
                            peer: sync.peer,
                            lastSentAt: sync.lastSentAt,
                            lastReceivedAt: sync.lastReceivedAt
                        ))
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { belowRing = $0 }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { visibleHeight = $0 }
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

    private var highlights: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Welcome.highlights, id: \.text) { highlight in
                HStack(spacing: 14) {
                    Image(systemName: highlight.systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.workInk)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    Text(highlight.text)
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileBackground()
    }

    /// Classic, the first starter, as the watch draws it.
    private func ring(side: CGFloat) -> some View {
        SegmentedRing(plan: IntervalPlan(workout: WorkoutStore.starterWorkouts[0]), strokeRatio: 0.07)
            .mask {
                Circle()
                    .trim(from: 0, to: drawn)
                    .stroke(style: StrokeStyle(lineWidth: 40))
                    .rotationEffect(.degrees(-90))
                    .padding(8)
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

#Preview {
    let store = WorkoutStore(defaults: UserDefaults(suiteName: "preview.welcome") ?? .standard)
    WelcomeView {}
        .environment(WatchSync(store: store))
}
