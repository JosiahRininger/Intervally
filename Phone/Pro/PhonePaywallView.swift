//
//  PhonePaywallView.swift
//  IntervallyPhone
//

import SwiftUI

/// Intervally Pro on iPhone: what it adds, its price, and Restore, in the shared
/// `PaywallContent`'s words for this device.
///
/// A sheet from the Workouts screen and the editor, where a purchase finishes what the user
/// reached for; pushed inside Settings, which is already a sheet. Never shown on launch, and
/// never a sheet on top of a sheet.
struct PhonePaywallView: View {
    let context: PaywallContext
    /// Shown as a sheet, so it carries its own Close button.
    var isSheet = false
    /// Runs once a purchase or a restore here unlocks Pro, so the screen that opened the
    /// paywall can finish what the user started.
    var onUnlock: (() -> Void)? = nil

    @Environment(ProStore.self) private var pro
    @Environment(WatchSync.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @State private var lastPurchase: ProStore.PurchaseOutcome?
    @State private var lastRestore: ProStore.RestoreOutcome?
    /// Set on the tap itself, before `purchase()` claims `isPurchasing`, so a double tap
    /// can't queue a second purchase behind the first.
    @State private var isBuying = false
    @State private var isRestoring = false
    @State private var unlocks = 0

    private var content: PaywallContent {
        PaywallContent.make(
            context: context,
            isPro: pro.isPro,
            ownership: pro.ownership,
            canMakePayments: pro.canMakePayments,
            offer: pro.offer,
            isPurchasing: isBuying || pro.isPurchasing,
            lastPurchase: lastPurchase,
            lastRestore: lastRestore,
            platform: .phone,
            hasWatch: sync.peer.hasWatch
        )
    }

    var body: some View {
        ScrollView {
            PhonePaywallPage(
                content: content,
                isRestoring: isRestoring,
                canRestore: !isRestoring && !isBuying,
                buy: buy,
                restore: restore,
                retry: retry
            )
        }
        .appCanvas()
        // The page carries its own large title.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .neutralGlass()
                }
            }
        }
        .sensoryFeedback(.success, trigger: unlocks)
        .task(id: pro.isPro) {
            guard !pro.isPro else { return }
            await pro.loadOffer()
        }
    }

    // MARK: - Actions

    private func buy() {
        // Only a price on screen can be bought; `.purchasing` also covers a purchase already
        // in flight, from this tap or the store.
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
        unlocks += 1
        onUnlock?()
    }
}

/// The paywall's layout for one `PaywallContent`, apart from the store, so every state can be
/// previewed and rendered in a test.
struct PhonePaywallPage: View {
    let content: PaywallContent
    var isRestoring = false
    var canRestore = true
    var buy: () -> Void = {}
    var restore: () -> Void = {}
    var retry: () -> Void = {}

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 24) {
            header
            actionArea
            terms
            features
            if content.offersRestore {
                restoreButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    /// A workout with a warmup and a cooldown, drawn as its ring: what Pro adds, in the
    /// ring's own colours.
    private var header: some View {
        VStack(spacing: 12) {
            SegmentedRing(plan: IntervalPlan(workout: Self.sample), strokeRatio: 0.1, gap: 2)
                .frame(width: 96, height: 96)
                .padding(.bottom, 4)

            Text(PaywallContent.title)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(content.contextLine)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    static let sample = IntervalWorkout(
        name: "Pro", prepareSeconds: 0, warmupSeconds: 120, workSeconds: 40,
        restSeconds: 20, rounds: 6, cooldownSeconds: 120
    )

    /// The one thing to tap: the price, Try Again where the price should be, or why there
    /// is nothing to buy.
    @ViewBuilder
    private var actionArea: some View {
        switch content.action {
        case .buy, .loading, .purchasing:
            buyCapsule
        case .unavailable, .loadFailed:
            VStack(spacing: 14) {
                retryCapsule
                status
            }
        case .owned, .blocked:
            status
        }
    }

    /// The price, or a spinner in the same capsule while it loads or the sheet is up, so the
    /// layout doesn't jump when the price arrives.
    private var buyCapsule: some View {
        let action = content.action
        return Button(action: buy) {
            Group {
                if let title = action.buttonTitle {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    ProgressView()
                        .tint(palette.onTint)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .prominentCapsule()
        // Not `.disabled`, which greys the capsule out from under its own spinner. `buy()`
        // refuses anything but a price either way.
        .allowsHitTesting(action.isPurchasable)
        .accessibilityRespondsToUserInteraction(action.isPurchasable)
        .accessibilityLabel(action.buttonAccessibilityLabel ?? "")
    }

    /// As wide as the price it stands in for, in neutral glass: it buys nothing.
    private var retryCapsule: some View {
        Button(action: retry) {
            Text(PaywallContent.retryTitle)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .neutralGlass()
    }

    private var status: some View {
        let action = content.action
        return VStack(spacing: 6) {
            if let icon = action.systemImage {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(action.isOwned ? palette.workInk : .secondary)
            }
            Text(action.headline ?? "")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if let detail = content.statusDetail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// The terms and the other device, under the price, then the answer to the last tap.
    @ViewBuilder
    private var terms: some View {
        let lines = [content.footnote, content.companionLine].compactMap { $0 }
        if !lines.isEmpty || content.note != nil {
            VStack(spacing: 6) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let note = content.note {
                    Text(note)
                        .font(.subheadline.weight(.medium))
                        .padding(.top, lines.isEmpty ? 0 : 6)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(content.features) { feature in
                HStack(spacing: 14) {
                    Image(systemName: feature.systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.workInk)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    Text(feature.title)
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileBackground()
    }

    private var restoreButton: some View {
        Button(action: restore) {
            Group {
                if isRestoring {
                    ProgressView()
                } else {
                    Text(PaywallContent.restoreTitle)
                }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .neutralGlass()
        .disabled(!canRestore)
        .accessibilityLabel(isRestoring ? "Restoring purchases" : PaywallContent.restoreTitle)
    }
}

#Preview("Price") {
    NavigationStack {
        ScrollView {
            PhonePaywallPage(content: .make(
                context: .presets, isPro: false, ownership: .none, canMakePayments: true,
                offer: .loaded(ProOffer(displayPrice: "$4.99", isFamilyShareable: true)),
                isPurchasing: false, lastPurchase: nil, lastRestore: nil, platform: .phone
            ))
        }
        .appCanvas()
    }
}

#Preview("Owned") {
    NavigationStack {
        ScrollView {
            PhonePaywallPage(content: .make(
                context: .settings, isPro: true, ownership: .purchased, canMakePayments: true,
                offer: .idle, isPurchasing: false, lastPurchase: nil, lastRestore: nil, platform: .phone
            ))
        }
        .appCanvas()
    }
}
