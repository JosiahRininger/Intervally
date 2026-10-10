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
            title: "Workouts", detail: "The interval sessions Intervally saves, with each interval in them."
        ),
        HealthReadItem(
            type: HKQuantityType(.heartRate), systemImage: "heart",
            title: "Heart Rate", detail: "Your average and highest for each session, and your average for each interval, when your Apple Watch or a heart rate monitor measured it."
        ),
        HealthReadItem(
            type: HKQuantityType(.activeEnergyBurned), systemImage: "flame",
            title: "Active Energy", detail: "What each session burned."
        ),
    ]
}

/// Settings > Apple Health: what Intervally saves and reads, that it stays in Health, and
/// where to change it.
struct HealthExplainerView: View {
    @Environment(HistoryModel.self) private var history

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Intervally saves each session you finish to Apple Health as a workout, on this iPhone or on your Apple Watch, and History reads them back.")
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

                block("What Intervally Saves") {
                    paragraph("Each workout you finish on this iPhone, interval by interval, so it counts toward your activity rings. A workout you end early isn't saved. Your Apple Watch saves the ones it runs.")
                }

                block("Where It Stays") {
                    paragraph("In Health, on your own devices. Intervally has no account and no server. Health brings the sessions your watch saves to your iPhone on its own.")
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
            .readableColumn()
        }
        .appCanvas()
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
