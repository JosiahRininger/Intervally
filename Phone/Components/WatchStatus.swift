//
//  WatchStatus.swift
//  IntervallyPhone
//

import SwiftUI

/// What the watch status shows for where the watch stands, worked out here so the card only
/// lays it out. No state is a dead end: presets are saved on the iPhone whatever happens.
struct WatchStatusContent: Equatable {
    let systemImage: String
    let title: String
    let detail: String
    /// When the two devices last exchanged presets. Only once the watch is set up.
    let lastSynced: Date?

    init(peer: PeerState, lastSentAt: Date?, lastReceivedAt: Date?) {
        switch peer {
        case .unsupported:
            systemImage = "applewatch.slash"
            title = "Apple Watch isn't available"
            detail = "You can still build workouts here."
        case .activating:
            systemImage = "applewatch"
            title = "Looking for your Apple Watch"
            detail = "Your workouts are saved here either way."
        case .notPaired:
            systemImage = "applewatch.slash"
            title = "No Apple Watch paired"
            detail = "Your workouts will be waiting."
        case .appNotInstalled:
            systemImage = "applewatch"
            title = "Intervally isn't on your watch yet"
            detail = "In the Watch app, open My Watch, then Available Apps, and tap Install next to Intervally."
        case .ready:
            systemImage = "applewatch.radiowaves.left.and.right"
            title = "You're set"
            // Until the watch has sent anything, its presets are still only on the watch.
            detail = lastReceivedAt == nil
                ? "Open Intervally on your watch to bring your presets over."
                : "Workouts you change here show up on your watch."
        }
        lastSynced = peer == .ready ? [lastSentAt, lastReceivedAt].compactMap { $0 }.max() : nil
    }

    /// "Synced just now", "Last synced 5 minutes ago"; nil before the first exchange.
    func syncedLine(now: Date = Date()) -> String? {
        guard let lastSynced else { return nil }
        if now.timeIntervalSince(lastSynced) < 60 { return "Synced just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last synced \(formatter.localizedString(for: lastSynced, relativeTo: now))"
    }
}

/// Where the watch stands, and when the presets last went across.
struct WatchStatusCard: View {
    let content: WatchStatusContent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: content.systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(content.title)
                    .font(.headline)
                Text(content.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Redrawn each minute, so "just now" doesn't stay on screen for an hour.
                TimelineView(.everyMinute) { timeline in
                    if let line = content.syncedLine(now: timeline.date) {
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 12) {
        WatchStatusCard(content: WatchStatusContent(peer: .ready, lastSentAt: .now.addingTimeInterval(-300), lastReceivedAt: .now))
        WatchStatusCard(content: WatchStatusContent(peer: .appNotInstalled, lastSentAt: nil, lastReceivedAt: nil))
        WatchStatusCard(content: WatchStatusContent(peer: .unsupported, lastSentAt: nil, lastReceivedAt: nil))
    }
    .padding()
    .background(.black)
}
