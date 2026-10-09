//
//  HistoryView.swift
//  IntervallyPhone
//

import SwiftUI

/// What History says when it has no sessions to list, worked out apart from the view.
struct HistoryMessage: Equatable {
    let systemImage: String
    let title: String
    let detail: String

    /// Where to look in Health. The same words in the empty state and the explainer.
    static let whereToCheck = "In the Health app, tap your picture, then Apps under Privacy, then Intervally."

    /// Nil for the states that show something else: the sessions, or the first read.
    init?(_ state: HistoryModel.State) {
        switch state {
        case .needsAccess:
            systemImage = "heart.text.square"
            title = "See every session, interval by interval"
            detail = "Connect Apple Health to see the workouts your Apple Watch saves: each interval, "
                + "your heart rate and the energy you burned. Intervally only reads, and what it reads "
                + "stays on this iPhone."
        case .empty:
            // Never "you denied access": HealthKit doesn't say, and most often the watch just
            // hasn't finished a workout yet, or Health hasn't brought it over.
            systemImage = "applewatch"
            title = "No sessions yet"
            detail = "Workouts you finish in Intervally on your Apple Watch show up here once Health "
                + "brings them to this iPhone. If one is missing, check that Intervally can read "
                + "workouts. \(Self.whereToCheck)"
        case .unavailable:
            systemImage = "heart.slash"
            title = "Apple Health isn't available"
            detail = "History reads from Apple Health, which this device doesn't have. "
                + "Your workouts and Intervally Pro work as usual."
        case .failed:
            systemImage = "exclamationmark.triangle"
            title = "Couldn't read Apple Health"
            detail = "Health didn't answer, as happens while this iPhone is locked. Try again in a moment."
        case .loading, .loaded:
            return nil
        }
    }

    /// Settings' Apple Health row.
    static func settingsSubtitle(for state: HistoryModel.State) -> String {
        switch state {
        case .unavailable: "Not available on this device"
        case .needsAccess: "Not connected"
        case .loading, .empty, .loaded, .failed: "Reads your watch's workouts"
        }
    }
}

/// History: the sessions the watch saved to Health, by week, newest first.
///
/// Read again whenever it appears, the app comes forward or the list is pulled: Health brings
/// a watch workout over in its own time.
struct HistoryView: View {
    @Environment(HistoryModel.self) private var history
    @State private var path: [SessionSummary] = []
    @State private var showsSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .blackCanvas()
                .navigationTitle("History")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showsSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                .navigationDestination(for: SessionSummary.self) { session in
                    SessionDetailView(session: session)
                }
        }
        .sheet(isPresented: $showsSettings) {
            PhoneSettingsView()
        }
        .onAppear {
            Task { await history.appear() }
        }
        #if DEBUG
        .modifier(HistoryQAOpen(path: $path))
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if history.state == .loaded {
            sessions
        } else if let message = HistoryMessage(history.state) {
            ScrollView {
                messageView(message)
            }
            .refreshable { await history.refresh() }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Sessions

    private var sessions: some View {
        List {
            ThisWeekCard(totals: WeekTotals(history.sessions))
                .cardRow()
            ForEach(history.weeks) { week in
                // The This Week card above already heads this week's sessions.
                if !week.isCurrent() {
                    SectionLabel(week.title())
                        .padding(.top, 14)
                        .cardRow()
                }
                ForEach(week.sessions) { session in
                    Button {
                        path.append(session)
                    } label: {
                        HistoryRow(session: session)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows every interval")
                    .cardRow()
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await history.refresh() }
    }

    // MARK: - Messages

    private func messageView(_ message: HistoryMessage) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: message.systemImage)
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(height: 72)
                    .accessibilityHidden(true)
                Text(message.title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .fixedSize(horizontal: false, vertical: true)

            switch history.state {
            case .needsAccess:
                Button {
                    Task { await history.connect() }
                } label: {
                    Group {
                        if history.isConnecting {
                            ProgressView()
                                .tint(Theme.onTint)
                        } else {
                            Text("Connect Apple Health")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .prominentCapsule()
                .disabled(history.isConnecting)
            case .failed:
                Button {
                    Task { await history.refresh() }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 40)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }
}

/// This week at a glance: how many sessions, and the minutes they came to.
struct ThisWeekCard: View {
    let totals: WeekTotals

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("This Week")
            // Side by side, the accessibility sizes broke "sessions" and the minutes mid-word.
            switch CardArrangement(typeSize: typeSize) {
            case .row:
                HStack(alignment: .firstTextBaseline, spacing: 28) {
                    figures
                    Spacer(minLength: 0)
                }
            case .stacked:
                VStack(alignment: .leading, spacing: 6) {
                    figures
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileBackground()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(totals.sessions) \(totals.sessions == 1 ? "session" : "sessions"), \(totals.minutes) minutes")
    }

    @ViewBuilder
    private var figures: some View {
        figure(totals.sessions, unit: totals.sessions == 1 ? "session" : "sessions")
        figure(totals.minutes, unit: "min")
    }

    private func figure(_ value: Int, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(value)")
                .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
            Text(unit)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

#Preview {
    HistoryView()
        .environment(HistoryModel(source: HealthHistory()))
}
