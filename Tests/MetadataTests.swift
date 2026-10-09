//
//  MetadataTests.swift
//  IntervallyTests
//

import Testing
import Foundation
@testable import Intervally

/// `AppStore/Metadata.md` is pasted into App Store Connect by hand, so nothing else checks
/// it. These hold it to Apple's field limits and its own stated counts, and to the product
/// and screens the app really has: a listing that oversells (Guideline 2.3.2), or review
/// notes that send the reviewer to a screen that moved (2.1(b)), is a rejection.
@Suite("App Store metadata")
struct MetadataTests {

    // MARK: - Reading the listing

    @Test("The parser reads blocks, table values, limits and stated counts")
    func parser() {
        let sample = """
        ## Keywords (10)

        ```
        ab
        c
        ```
        (4) — the newline counts

        | Field | Value |
        |---|---|
        | Name (30) | `Hello` (5) |
        | Bundle ID | `x.y` — never changes |
        | Price | Free |

        ## Notes
        ```
        loose
        ```
        """
        let fields = Listing.fields(in: sample)
        #expect(fields == [
            ListingField(label: "## Keywords (10)", text: "ab\nc", limit: 10, statedCount: 4, isBlock: true),
            ListingField(label: "Name (30)", text: "Hello", limit: 30, statedCount: 5, isBlock: false),
            ListingField(label: "Bundle ID", text: "x.y", limit: nil, statedCount: nil, isBlock: false),
            ListingField(label: "## Notes", text: "loose", limit: nil, statedCount: nil, isBlock: true),
        ])
    }

    // MARK: - Apple's limits

    /// Every field App Store Connect counts, with the limit the listing writes beside it.
    static let countedFields = [
        "Name (30)",
        "Subtitle (30)",
        "## Promotional text (170)",
        "## Description (4000)",
        "## Keywords (100)",
        "## What's New in 1.0 (4000)",
        "### Notes for the reviewer (4000)",
        "Display Name (30)",
        "Description (45)",
        "### Review notes (4000)",
    ]

    @Test("Each counted field fits Apple's limit", arguments: MetadataTests.countedFields)
    func fitsItsLimit(label: String) throws {
        let field = try Self.field(label)
        let limit = try #require(field.limit)
        #expect(field.text.count <= limit, "\(label) is \(field.text.count) characters")
        #expect(!field.text.isEmpty)
    }

    @Test("Every block meant for pasting states its limit")
    func everyBlockHasALimit() throws {
        let unlimited = try Self.fields().filter { $0.isBlock && $0.limit == nil }.map(\.label)
        #expect(unlimited.isEmpty, "blocks with no limit in their heading: \(unlimited)")
    }

    @Test("Every count the listing states is the real one")
    func statedCountsAreReal() throws {
        let stated = try Self.fields().filter { $0.statedCount != nil }
        #expect(stated.count >= 6)
        for field in stated {
            #expect(field.text.count == field.statedCount, "\(field.label) says \(field.statedCount ?? 0)")
        }
    }

    // MARK: - What it says

    @Test("The description says what Pro adds, and never oversells the free app (2.3.2)")
    func descriptionNamesThePurchase() throws {
        let description = try Self.field("## Description (4000)").text
        #expect(description.contains(
            "Intervally Pro, a one-time purchase, adds unlimited presets, warmup and cooldown phases, stronger taps, and \(AppTheme.pastel.title), a theme in soft colors."
        ))
        #expect(!description.contains("as many presets"))
    }

    @Test("Pro is sold as a tap pattern, never as haptics (4.10)")
    func neverSellsHaptics() throws {
        #expect(try !Self.listing().lowercased().contains("unlock haptic"))
        let notes = try Self.field("### Review notes (4000)").text
        #expect(notes.contains("repeats the tap at every interval change"))
        #expect(notes.contains("Every change still taps once for free users."))
    }

    @Test("The reviewer notes point at the screens the app really has")
    func notesMatchTheApp() throws {
        // These notes are wrapped to the file's width, so a phrase can span two lines.
        let version = try Self.field("### Notes for the reviewer (4000)").text
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(version.contains(ProProduct.id))
        #expect(version.contains("New Preset"))
        #expect(version.contains("the \(ProProduct.freePresetLimit) starter presets fill the free limit"))
        #expect(version.contains(try #require(PaywallContent.Action.unavailable.headline)))
        #expect(version.contains(PaywallContent.retryTitle))

        let purchase = try Self.field("### Review notes (4000)").text
        #expect(purchase.contains(ProProduct.id))
        #expect(purchase.contains("up to \(ProProduct.freePresetLimit) presets"))
        #expect(purchase.contains("The \(ProProduct.freePresetLimit) starters fill the free limit"))
        #expect(purchase.contains("then \(ProStatusRow.title) (the first row)"))
        #expect(purchase.contains("\(PaywallContent.restoreTitle) is at the bottom of the \(PaywallContent.title) screen"))
        #expect(purchase.contains("shows \(ProStatusRow(isPro: true, ownership: .purchased).subtitle)"))
        let titles = TapStrength.allCases.map(\.title)
        #expect(titles.count == 3)
        #expect(purchase.contains("\(titles[0]), \(titles[1]) and \(titles[2])"))
    }

    @Test("The notes find Settings by its place, and name both of its faces")
    func notesNameBothSettingsFaces() throws {
        // A reviewer who declined notifications at their first Start sees a bell, not a gear.
        #expect(SetupView.settingsSymbol(alertsOff: false) == "gearshape.fill")
        #expect(SetupView.settingsSymbol(alertsOff: true) == "bell.slash.fill")
        let purchase = try Self.field("### Review notes (4000)").text
        #expect(purchase.contains("Tap the Settings button (top right: a gear, or an orange bell if notifications are off)"))
        #expect(purchase.contains("Open Settings the same way, then choose Tap Strength."))
        #expect(!purchase.contains("Tap the gear"))
    }

    @Test("Both sets of notes say how to see Pastel, in the app's own words, and that it is Pro")
    func notesNameTheTheme() throws {
        let theme = ThemeRow.title, pastel = AppTheme.pastel.title, classic = AppTheme.classic.title
        let version = try Self.field("### Notes for the reviewer (4000)").text
        #expect(version.contains("Settings > \(theme) switches between \(classic) and \(pastel)"))
        #expect(version.contains("\(pastel) is part of Intervally Pro"))
        let purchase = try Self.field("### Review notes (4000)").text
        #expect(purchase.contains("then choose \(theme), then \(pastel), marked PRO."))
        #expect(purchase.contains("- \(pastel), a theme in soft colors"))
        #expect(PaywallContent.features.map(\.title).contains("\(pastel) theme"))
    }

    // MARK: - An iPhone app with an Apple Watch app

    @Test("The record is the iPhone app's, under a SKU that names no one platform")
    func recordIsTheIPhoneApps() throws {
        // Both are set once, when the record is created, and can never change.
        let companion = try #require(Bundle.main.object(forInfoDictionaryKey: "WKCompanionAppBundleIdentifier") as? String)
        #expect(try Self.field("Bundle ID").text == companion)
        #expect(try Self.field("SKU").text == "intervally")
    }

    /// The watch-only listing told App Review there was no iPhone app to carry the purchase.
    @Test("Nothing pasted into App Store Connect calls Intervally watch-only", arguments: [
        "## Description (4000)", "### Notes for the reviewer (4000)", "### Review notes (4000)",
    ])
    func neverWatchOnly(label: String) throws {
        let text = try Self.field(label).text.lowercased()
        for phrase in ["standalone", "no iphone app", "watch-only", "watch only"] {
            #expect(!text.contains(phrase), "\(label) says \(phrase)")
        }
    }

    @Test("The description says where the data stays, and that workouts run on the watch")
    func descriptionSaysWhereDataStays() throws {
        let description = try Self.field("## Description (4000)").text
        #expect(description.contains("stay on your iPhone and Apple Watch and in Apple Health"))
        #expect(description.contains("Workouts run on Apple Watch."))
    }

    @Test("The purchase goes in with the iOS version, and its notes start on the iPhone")
    func purchaseRidesWithTheIOSVersion() throws {
        #expect(try Self.listing().contains("add Intervally Pro to the same submission as iOS version 1.0"))
        let purchase = try Self.field("### Review notes (4000)").text
        let iPhone = try #require(purchase.range(of: "ON IPHONE (the main way to buy; no Apple Watch needed)"))
        let watch = try #require(purchase.range(of: "ON APPLE WATCH"))
        #expect(iPhone.lowerBound < watch.lowerBound)
        // The watch's paywall points to the iPhone where the App Store can't sell Pro on it.
        #expect(purchase.contains("its Intervally Pro screen says Pro can also be unlocked in Intervally on iPhone"))
    }

    // MARK: - The In-App Purchase record

    @Test("The StoreKit configuration mirrors the App Store Connect record")
    func storeKitMirrorsTheRecord() throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "Intervally", withExtension: "storekit"))
        let configuration = try JSONDecoder().decode(StoreKitConfiguration.self, from: Data(contentsOf: url))
        let product = try #require(configuration.products.first)
        #expect(configuration.products.count == 1)
        #expect(product.productID == ProProduct.id)
        #expect(product.type == "NonConsumable")
        #expect(product.familyShareable)
        let localization = try #require(product.localizations.first)
        #expect(product.localizations.count == 1)

        #expect(try Self.field("Product ID").text == product.productID)
        #expect(try Self.field("Reference Name").text == product.referenceName)
        #expect(try Self.field("Display Name (30)").text == localization.displayName)
        #expect(try Self.field("Description (45)").text == localization.description)
        #expect(try Self.listing().contains("USD \(product.displayPrice)"))
    }

    // MARK: - Helpers

    private static func listing() throws -> String {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "Metadata", withExtension: "md"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func fields() throws -> [ListingField] {
        Listing.fields(in: try listing())
    }

    /// The one field under `label`. Two would make every check on it ambiguous.
    private static func field(_ label: String) throws -> ListingField {
        let matches = try fields().filter { $0.label == label }
        #expect(matches.count == 1, "\(matches.count) fields labelled \(label)")
        return try #require(matches.first)
    }
}

/// The parts of a `.storekit` file the App Store Connect record also holds.
private struct StoreKitConfiguration: Decodable {
    struct Product: Decodable {
        struct Localization: Decodable {
            let displayName: String
            let description: String
        }
        let productID: String
        let referenceName: String
        let type: String
        let familyShareable: Bool
        let displayPrice: String
        let localizations: [Localization]
    }
    let products: [Product]
}
