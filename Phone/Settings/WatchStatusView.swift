//
//  WatchStatusView.swift
//  IntervallyPhone
//

import SwiftUI

/// Settings > Apple Watch: where the watch stands, what to do about it, and when the presets
/// last went across. It follows the watch live, so installing the app from the Watch app
/// turns it to "You're set" while it is open.
struct WatchStatusView: View {
    @Environment(WatchSync.self) private var sync
    @State private var sends = 0

    var body: some View {
        let content = WatchStatusContent(peer: sync.peer, lastSentAt: sync.lastSentAt, lastReceivedAt: sync.lastReceivedAt)

        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: content.systemImage)
                        .font(.system(size: 56, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(height: 72)
                        .accessibilityHidden(true)
                    Text(content.title)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    // The steps say it better than the sentence where there are steps.
                    if content.installSteps.isEmpty {
                        Text(content.detail)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    TimelineView(.everyMinute) { timeline in
                        if let line = content.syncedLine(now: timeline.date) {
                            Text(line)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 24)

                if !content.installSteps.isEmpty {
                    steps(content.installSteps)
                }

                if content.offersSendNow {
                    Button {
                        sync.push(force: true)
                        sends += 1
                    } label: {
                        Label("Send to Watch Now", systemImage: "arrow.up.circle")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .neutralGlass()
                    .accessibilityHint("Sends every workout to your watch again")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            // Short states would otherwise leave the scroll view as narrow as their words,
            // with the sheet's grey either side.
            .readableColumn()
        }
        .appCanvas()
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: sends)
    }

    private func steps(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("\(index + 1)")
                        .font(.system(.headline, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20)
                    Text(step)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileBackground()
    }
}
