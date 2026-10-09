//
//  PaywallView.swift
//  Intervally
//

import SwiftUI
import WatchKit

/// Intervally Pro: what it adds, its price, and Restore.
///
/// Always pushed inside the stack its entry point already uses — never a sheet on top of a
/// sheet — so the system back button is the one-tap way out. The price sits above the fold
/// on a 40mm watch; the feature list and Restore follow under the crown. Never shown on
/// launch, before Start, during a run or on the summary.
struct PaywallView: View {
    let context: PaywallContext
    /// Runs once a purchase or a restore unlocks Pro, so the screen that opened the paywall
    /// can finish what the user started.
    var onUnlock: (() -> Void)? = nil

    @Environment(ProStore.self) private var pro
    /// For Feel Strongest alone, which plays on the run's own player. Called from a tap and
    /// never read in `body`, so a run going on behind this screen never redraws it.
    @Environment(RunCoordinator.self) private var coordinator

    @State private var lastPurchase: ProStore.PurchaseOutcome?
    @State private var lastRestore: ProStore.RestoreOutcome?
    /// Set on the tap itself, before `purchase()` runs and claims `isPurchasing`, so a
    /// double tap can't queue a second purchase behind the first.
    @State private var isBuying = false
    @State private var isRestoring = false

    private var content: PaywallContent {
        PaywallContent.make(
            context: context,
            isPro: pro.isPro,
            ownership: pro.ownership,
            canMakePayments: pro.canMakePayments,
            offer: pro.offer,
            isPurchasing: isBuying || pro.isPurchasing,
            lastPurchase: lastPurchase,
            lastRestore: lastRestore
        )
    }

    var body: some View {
        ScrollView {
            PaywallPage(
                content: content,
                isRestoring: isRestoring,
                canRestore: !isRestoring && !isBuying,
                buy: buy,
                restore: restore,
                retry: retry,
                feelStrongest: { coordinator.previewTaps(.strongest) }
            )
        }
        // No title: "Intervally Pro" clipped beside the back button on a 40mm watch, so the
        // page carries its own.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: pro.isPro) {
            guard !pro.isPro else { return }
            await pro.loadOffer()
        }
    }

    // MARK: - Actions

    private func buy() {
        // Only a price on screen can be bought. The capsule is still a live button while it
        // spins, and VoiceOver can activate it; `.purchasing` also covers a purchase that
        // is already in flight, from this tap or the store.
        guard content.action.isPurchasable, !isRestoring else { return }
        isBuying = true
        lastPurchase = nil
        lastRestore = nil
        Task {
            let outcome = await pro.purchase()
            isBuying = false
            lastPurchase = outcome
            if outcome == .purchased { unlocked() }
        }
    }

    private func restore() {
        guard !isRestoring else { return }
        isRestoring = true
        lastPurchase = nil
        lastRestore = nil
        Task {
            let outcome = await pro.restore()
            isRestoring = false
            lastRestore = outcome
            if outcome == .restored { unlocked() }
        }
    }

    /// Try Again clears the last answer too: after a refused purchase the offer is still
    /// loaded, and the capsule should simply come back.
    private func retry() {
        lastPurchase = nil
        lastRestore = nil
        Task { await pro.loadOffer() }
    }

    private func unlocked() {
        Haptics.play(.success)
        onUnlock?()
    }
}

/// The paywall's layout for one `PaywallContent`, apart from the store and the actions, so
/// every state can be previewed. Everything under `PaywallHeader` is for someone already
/// deciding, and can wait for the crown.
struct PaywallPage: View {
    let content: PaywallContent
    var isRestoring = false
    var canRestore = true
    var buy: () -> Void = {}
    var restore: () -> Void = {}
    var retry: () -> Void = {}
    var feelStrongest: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaywallHeader(content: content, buy: buy, retry: retry)

            // Only when this watch couldn't sell Pro: the way that still works. Below the
            // header, so it never pushes Try Again under the fold.
            if let companion = content.companionLine {
                Text(companion)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = content.note {
                Text(note)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let footnote = content.footnote {
                // Footnote, not caption2: on watchOS caption2 is the larger of the two.
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            ForEach(PaywallContent.features) { feature in
                featureRow(feature)
            }

            if content.offersPreview {
                textButton(PaywallContent.previewTitle, action: feelStrongest)
            }
            if content.offersRestore {
                restoreButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scenePadding(.horizontal)
    }

    // MARK: Below the header

    private func featureRow(_ feature: PaywallContent.Feature) -> some View {
        HStack(spacing: 8) {
            Image(systemName: feature.systemImage)
                .foregroundStyle(Theme.work)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(feature.title)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote.weight(.semibold))
    }

    private var restoreButton: some View {
        Button(action: restore) {
            Group {
                if isRestoring {
                    ProgressView()
                } else {
                    Text(PaywallContent.restoreTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.work)
        .disabled(!canRestore)
        .accessibilityLabel(isRestoring ? "Restoring purchases" : PaywallContent.restoreTitle)
    }

    /// A borderless line of tinted text with a full-width, 44pt target. One line: wrapped,
    /// a borderless label centres itself and "Restore Purchases" read as two stray words.
    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.work)
    }
}

/// What a 40mm watch shows before the crown turns: the title, the context line and the
/// capsule slot. Its own view so a test can hold the price to the fold.
struct PaywallHeader: View {
    let content: PaywallContent
    var buy: () -> Void = {}
    var retry: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PaywallContent.title)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)

            Text(content.contextLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            actionArea(content.action)
        }
    }

    /// The capsule slot holds the one thing to tap: the price, or Try Again where the price
    /// should be, so a successful retry puts the price exactly there. Both stay above the
    /// fold on a 40mm watch; the reason for a retry follows the button.
    @ViewBuilder
    private func actionArea(_ action: PaywallContent.Action) -> some View {
        switch action {
        case .buy, .loading, .purchasing:
            buyCapsule(action)
        case .unavailable, .loadFailed:
            VStack(alignment: .leading, spacing: 8) {
                retryCapsule
                status(action)
            }
        case .owned, .blocked:
            status(action)
        }
    }

    /// The price, or a spinner in the same capsule while it loads or the sheet is up, so
    /// the layout doesn't jump when the price arrives.
    private func buyCapsule(_ action: PaywallContent.Action) -> some View {
        let title = action.buttonTitle
        return Button(action: buy) {
            Group {
                if let title {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    ProgressView()
                        .tint(Theme.onTint)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(Theme.work)
        .foregroundStyle(Theme.onTint)
        // Not `.disabled`: that greys the capsule out from under its own spinner. Hit
        // testing stops touches only, so VoiceOver is told separately that a spinner does
        // nothing, and `buy()` refuses it either way.
        .allowsHitTesting(action.isPurchasable)
        .accessibilityRespondsToUserInteraction(action.isPurchasable)
        .accessibilityLabel(action.buttonAccessibilityLabel ?? "")
    }

    /// Full width like the price it stands in for, in neutral glass: it buys nothing.
    private var retryCapsule: some View {
        Button(action: retry) {
            Text(PaywallContent.retryTitle)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
    }

    private func status(_ action: PaywallContent.Action) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let icon = action.systemImage {
                    Image(systemName: icon)
                        .foregroundStyle(action.isOwned ? Theme.work : .secondary)
                }
                Text(action.headline ?? "")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = action.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A Pro feature's screen, or the paywall in its place. It swaps in place the moment Pro
/// unlocks, so a purchase made from here lands on the feature with nothing left to resume.
struct ProGate<Content: View>: View {
    let context: PaywallContext
    @ViewBuilder let content: () -> Content

    @Environment(ProStore.self) private var pro

    var body: some View {
        if pro.isPro {
            content()
        } else {
            PaywallView(context: context)
        }
    }
}

/// Marks a control that opens the paywall rather than doing its job, for a free user.
/// Hidden from VoiceOver: the control's hint says the same thing in words.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.onTint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Theme.work))
            .fixedSize()
            .accessibilityHidden(true)
    }
}

#Preview("Live") {
    let pro = ProStore()
    NavigationStack { PaywallView(context: .tapStrength) }
        .environment(pro)
        .environment(RunCoordinator(
            store: WorkoutStore(defaults: UserDefaults(suiteName: "preview")!),
            pro: pro,
            haptics: HapticPlayer(strength: { .standard })
        ))
}

/// The free state with a price, without StoreKit: the App Review screenshot.
#Preview("Price") {
    NavigationStack {
        ScrollView {
            PaywallPage(content: .make(
                context: .settings, isPro: false, ownership: .none, canMakePayments: true,
                offer: .loaded(ProOffer(displayPrice: "$4.99", isFamilyShareable: true)),
                isPurchasing: false, lastPurchase: nil, lastRestore: nil
            ))
        }
    }
}

#Preview("Unreachable") {
    NavigationStack {
        ScrollView {
            PaywallPage(content: .make(
                context: .tapStrength, isPro: false, ownership: .none, canMakePayments: true,
                offer: .failed, isPurchasing: false, lastPurchase: nil, lastRestore: nil
            ))
        }
    }
}
