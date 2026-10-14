//
//  RunDiagnosticsView.swift
//  IntervallyPhone
//

import SwiftUI

/// What recent workouts went through (`RunDiagnostics`), newest first, to share when a run
/// fell silent outside the app or never reached Health. Kept on the device; shared only from
/// here, by the user.
struct RunDiagnosticsView: View {
    @State private var entries = RunDiagnostics.shared.all.reversed() as [RunDiagnostics.Entry]
    @State private var confirmingClear = false

    var body: some View {
        List {
            Section {
                if entries.isEmpty {
                    Text("Nothing yet. Start a workout, and what it goes through shows here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute().second())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(entry.text)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } footer: {
                Text("Stays on this iPhone. Share it to show what kept a workout running, or why it stopped.")
            }
        }
        .navigationTitle("Workout Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: RunDiagnostics.shared.text.isEmpty ? "No entries yet." : RunDiagnostics.shared.text) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share")
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Clear", role: .destructive) { confirmingClear = true }
                    .disabled(entries.isEmpty)
            }
        }
        .confirmationDialog("Clear the diagnostics?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                RunDiagnostics.shared.clear()
                entries = []
            }
        }
        .refreshable { entries = RunDiagnostics.shared.all.reversed() }
    }
}
