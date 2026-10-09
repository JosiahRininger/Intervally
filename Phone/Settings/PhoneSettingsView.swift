//
//  PhoneSettingsView.swift
//  IntervallyPhone
//

import SwiftUI
import UIKit

/// A screen pushed inside Settings.
enum SettingsRoute: Hashable {
    case pro, watch, health, theme
    /// The paywall, opened by a free user's Pastel in Theme.
    case themePaywall
}

/// The iPhone's Settings sheet: Intervally Pro, the watch, Apple Health, the App Store's
/// purchase sheets, and the links App Review and users look for. Nothing here is a
/// placeholder.
///
/// The paywall is pushed here rather than presented: this is already a sheet.
struct PhoneSettingsView: View {
    @Environment(ProStore.self) private var pro
    @Environment(ThemeStore.self) private var theme
    @Environment(WatchSync.self) private var sync
    @Environment(HistoryModel.self) private var history
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var path: [SettingsRoute] = []
    @State private var notice: StoreNotice?
    /// The store action under way, so a second tap can't start another.
    @State private var busy: StoreAction?

    enum StoreAction: Equatable {
        case restore, redeem, refund

        /// The row's words, which the App Review notes quote.
        var title: String {
            switch self {
            case .restore: PaywallContent.restoreTitle
            case .redeem: "Redeem Code"
            case .refund: "Request a Refund"
            }
        }

        var systemImage: String {
            switch self {
            case .restore: "arrow.clockwise"
            case .redeem: "giftcard"
            case .refund: "arrow.uturn.backward.circle"
            }
        }
    }

    private static let support = URL(string: "https://josiahrininger.com/intervally/support")
    private static let privacyPolicy = URL(string: "https://josiahrininger.com/intervally/privacy")

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    /// Once, however Pro arrived: chooses Pastel and goes back to the picker.
    private func finishThemePaywall() {
        guard path.last == .themePaywall else { return }
        theme.paywallUnlocked()
        path.removeLast()
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: SettingsRoute.pro) {
                        proRow(ProStatusRow(isPro: pro.isPro, ownership: pro.ownership))
                    }
                    NavigationLink(value: SettingsRoute.theme) {
                        row(
                            systemImage: ThemeRow.systemImage, title: ThemeRow.title,
                            subtitle: theme.effective(isPro: pro.isPro).title
                        )
                    }
                    NavigationLink(value: SettingsRoute.watch) {
                        watchRow
                    }
                    NavigationLink(value: SettingsRoute.health) {
                        row(
                            systemImage: "heart.text.square", title: "Apple Health",
                            subtitle: HistoryMessage.settingsSubtitle(for: history.state)
                        )
                    }
                }

                Section {
                    storeButton(.restore)
                    storeButton(.redeem)
                    // A family member's shared copy can only be refunded by whoever bought it.
                    if pro.ownership == .purchased {
                        storeButton(.refund)
                    }
                } header: {
                    Text("Purchases")
                } footer: {
                    Text("Intervally Pro is one purchase for your iPhone and your Apple Watch.")
                }

                Section {
                    // Asked for: the App Store's own Write a Review page, any time.
                    if let writeReview = ReviewLinks.writeReview {
                        Link(destination: writeReview) {
                            Label("Rate Intervally", systemImage: "star")
                        }
                    }
                    // Something wrong reaches Josiah, not just a one-star review.
                    if let feedback = ReviewLinks.feedbackMail(appVersion: Self.version, systemVersion: UIDevice.current.systemVersion) {
                        Link(destination: feedback) {
                            Label("Send Feedback", systemImage: "envelope")
                        }
                    }
                    if let support = Self.support {
                        Link(destination: support) {
                            Label("Support", systemImage: "questionmark.circle")
                        }
                    }
                    if let privacyPolicy = Self.privacyPolicy {
                        Link(destination: privacyPolicy) {
                            Label("Privacy Policy", systemImage: "hand.raised")
                        }
                    }
                } footer: {
                    Text("Intervally \(Self.version)")
                }
            }
            .appCanvas()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Neutral, as on the paywall: closing Settings confirms nothing.
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                        .neutralGlass()
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .pro: PhonePaywallView(context: .settings)
                case .watch: WatchStatusView()
                case .health: HealthExplainerView()
                case .theme: ThemePickerView { path.append(.themePaywall) }
                case .themePaywall:
                    // A purchase here applies what was reached for, then goes back to the
                    // picker to show it chosen. Pro can also arrive while this is open without
                    // its buttons (an Ask to Buy approval, the other device's purchase, Family
                    // Sharing), and finishes the same way.
                    PhonePaywallView(context: .themes) { finishThemePaywall() }
                        .onChange(of: pro.isPro) { _, isPro in
                            if isPro { finishThemePaywall() }
                        }
                }
            }
            .alert(notice?.title ?? "", isPresented: isShowingNotice, presenting: notice) { _ in
                Button("OK", role: .cancel) {}
            } message: { notice in
                Text(notice.message)
            }
        }
        #if DEBUG
        .modifier(SettingsQAOpen(path: $path))
        #endif
    }

    private var isShowingNotice: Binding<Bool> {
        Binding { notice != nil } set: { if !$0 { notice = nil } }
    }

    // MARK: - Rows

    private func proRow(_ row: ProStatusRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.systemImage)
                .foregroundStyle(palette.workInk)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ProStatusRow.title)
                    .font(.body.weight(.semibold))
                Text(row.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var watchRow: some View {
        let status = WatchStatusContent(peer: sync.peer, lastSentAt: sync.lastSentAt, lastReceivedAt: sync.lastReceivedAt)
        return row(systemImage: status.systemImage, title: "Apple Watch", subtitle: status.title)
    }

    private func row(systemImage: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func storeButton(_ action: StoreAction) -> some View {
        Button {
            run(action)
        } label: {
            HStack {
                Label(action.title, systemImage: action.systemImage)
                Spacer()
                if busy == action {
                    ProgressView()
                }
            }
        }
        .disabled(busy != nil)
    }

    // MARK: - Actions

    private func run(_ action: StoreAction) {
        guard busy == nil else { return }
        busy = action
        Task {
            switch action {
            case .restore: notice = StoreNotice.restore(await pro.restore())
            case .redeem: notice = StoreNotice.redeem(await pro.redeemOfferCode())
            case .refund: notice = StoreNotice.refund(await pro.requestRefund())
            }
            busy = nil
        }
    }
}

#Preview {
    let store = WorkoutStore(defaults: UserDefaults(suiteName: "preview.settings") ?? .standard)
    PhoneSettingsView()
        .environment(ProStore(defaults: UserDefaults(suiteName: "preview.pro") ?? .standard))
        .environment(ThemeStore(defaults: UserDefaults(suiteName: "preview.theme") ?? .standard))
        .environment(WatchSync(store: store))
        .environment(HistoryModel(source: HealthHistory()))
}
