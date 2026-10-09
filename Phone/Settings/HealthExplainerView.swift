//
//  HealthExplainerView.swift
//  IntervallyPhone
//

import HealthKit
import SwiftUI

/// What History reads from Apple Health, listed from the types it asks for so the two can't
/// drift apart.
struct HealthReadItem: Identifiable {
    let type: HKObjectType
    let systemImage: String
    let title: String
    let detail: String

    var id: String { type.identifier }

    static let all: [HealthReadItem] = [
        HealthReadItem(
            type: HKObjectType.workoutType(), systemImage: "figure.highintensity.intervaltraining",
            title: "Workouts", detail: "The interval sessions your Apple Watch saves, with each interval in them."
        ),
        HealthReadItem(
            type: HKQuantityType(.heartRate), systemImage: "heart",
            title: "Heart Rate", detail: "Your average and highest for each session, and your average for each interval."
        ),
        HealthReadItem(
            type: HKQuantityType(.activeEnergyBurned), systemImage: "flame",
            title: "Active Energy", detail: "What each session burned."
        ),
    ]
}

/// Settings > Apple Health: what History reads, that it stays on this iPhone, and where to
/// change it.
struct HealthExplainerView: View {
    @Environment(HistoryModel.self) private var history

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("History shows the workouts your Apple Watch saves to Apple Health. Intervally only reads Health on this iPhone, and never writes to it.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                block("What Intervally Reads") {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(HealthReadItem.all) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                Image(systemName: item.systemImage)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.headline)
                                    Text(item.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tileBackground()
                }

                block("Where It Stays") {
                    paragraph("On this iPhone. Intervally has no account and no server. Your watch saves each session to Health, and Health brings it to your iPhone on its own.")
                }

                block("Changing Access") {
                    paragraph(HistoryMessage.whereToCheck)
                }

                if history.state == .needsAccess {
                    Button {
                        Task { await history.connect() }
                    } label: {
                        Text(HistoryMessage.connectTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .prominentCapsule()
                    .disabled(history.isConnecting)
                }
            }
            .padding(20)
        }
        .blackCanvas()
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        // Whether to offer Connect is History's to know; this is where it finds out.
        .onAppear {
            Task { await history.appear() }
        }
    }

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title)
            content()
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tileBackground()
    }
}
