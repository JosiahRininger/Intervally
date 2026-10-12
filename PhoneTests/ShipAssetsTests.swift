//
//  ShipAssetsTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing

/// The images that go to App Store Connect, read from the source tree (which the simulator
/// shares with the Mac). App Store Connect refuses a screenshot of the wrong size or with an
/// alpha channel only at upload, and an iPhone icon that differs from the watch's is a
/// Guideline 2.3.8 rejection, so each is checked here instead.
@Suite("Ship assets")
struct ShipAssetsTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    static let screenshots = root.appendingPathComponent("AppStore/Screenshots")

    struct Size: Equatable {
        let width: Int
        let height: Int
    }

    /// Each screenshot folder and the one size App Store Connect takes for it. One iPhone
    /// set: App Store Connect uses the medium display's shots for every iPhone size. One
    /// iPad set, the 13-inch, which App Store Connect requires of an app that runs on iPad.
    static let sets: [String: Size] = [
        "iPhone-6.3": Size(width: 1206, height: 2622),
        "iPad-13": Size(width: 2064, height: 2752),
        "Watch": Size(width: 416, height: 496),
    ]

    @Test("The iPhone's icon is the watch's art, byte for byte, 1024 square with no alpha")
    func icon() throws {
        let phone = try Data(contentsOf: Self.root.appendingPathComponent("Phone/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
        let watch = try Data(contentsOf: Self.root.appendingPathComponent("Sources/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
        #expect(phone == watch)
        let header = try #require(PNGHeader(phone))
        #expect(header.width == 1024 && header.height == 1024)
        #expect(!header.hasAlpha)
    }

    @Test("Every screenshot is its set's exact size, with no alpha")
    func screenshotSizes() throws {
        for (folder, size) in Self.sets {
            let files = try Self.pngs(in: folder)
            #expect((1...10).contains(files.count), "\(folder) holds \(files.count) screenshots")
            for file in files {
                let header = try #require(PNGHeader(Data(contentsOf: file)), "\(file.lastPathComponent) isn't a PNG")
                #expect(header.width == size.width && header.height == size.height, "\(folder)/\(file.lastPathComponent)")
                #expect(!header.hasAlpha, "\(folder)/\(file.lastPathComponent) has alpha")
            }
        }
    }

    @Test("The iPhone set leads with a run on iPhone, and names Pro wherever it shows it")
    func iPhoneSet() throws {
        let shots = try Self.pngs(in: "iPhone-6.3").map(\.lastPathComponent)
        #expect(shots == [
            "1-run.png", "2-lock.png", "3-workouts.png", "4-editor.png",
            "5-history.png", "6-session.png", "7-pro-editor.png", "8-pastel.png",
        ])
        let compose = try String(contentsOf: Self.screenshots.appendingPathComponent("compose.py"), encoding: .utf8)
        for pro in ["7-pro-editor", "8-pastel"] {
            #expect(compose.contains("('\(pro)', 'INTERVALLY PRO'"), "\(pro) is captioned Intervally Pro (2.3.2)")
        }
    }

    @Test("The iPad set is the iPhone's, shot for shot, captioned for a device without a watch")
    func iPadSet() throws {
        let iPhone = try Self.pngs(in: "iPhone-6.3").map(\.lastPathComponent)
        let iPad = try Self.pngs(in: "iPad-13").map(\.lastPathComponent)
        #expect(iPad == iPhone)
        let compose = try String(contentsOf: Self.screenshots.appendingPathComponent("compose.py"), encoding: .utf8)
        #expect(compose.contains("'1-run': ('TRAIN ON IPAD'"))
        #expect(!compose.contains("anywhere"), "No 'Start it anywhere' on a device with no watch")
    }

    @Test("The In-App Purchase review screenshot is a 6.9-inch capture with no alpha")
    func purchaseReviewShot() throws {
        let data = try Data(contentsOf: Self.screenshots.appendingPathComponent("iap-review.png"))
        let header = try #require(PNGHeader(data))
        #expect(header.width == 1320 && header.height == 2868)
        #expect(!header.hasAlpha)
    }

    @Test("The listing names every screenshot on disk, and none that isn't")
    func listingMatchesDisk() throws {
        let listing = try String(contentsOf: Self.root.appendingPathComponent("AppStore/Metadata.md"), encoding: .utf8)
        let named = Set(listing.matches(of: /`(?:[\w\/.-]*\/)?([\w-]+\.png)`/).map { String($0.1) })
        var onDisk = Set(try Self.sets.keys.flatMap { try Self.pngs(in: $0) }.map(\.lastPathComponent))
        onDisk.insert("iap-review.png")
        #expect(named == onDisk)
    }

    @Test("The PNG reader finds the size and the alpha channel")
    func reader() {
        // An 8-bit RGBA PNG's signature and header chunk, 3 x 2.
        var rgba = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13])
        rgba.append(contentsOf: Array("IHDR".utf8))
        rgba.append(contentsOf: [0, 0, 0, 3, 0, 0, 0, 2, 8, 6, 0, 0, 0])
        rgba.append(contentsOf: [0, 0, 0, 0])   // the chunk's CRC, which the reader doesn't check
        #expect(PNGHeader(rgba) == PNGHeader(width: 3, height: 2, hasAlpha: true))
        var rgb = rgba
        rgb[25] = 2
        #expect(PNGHeader(rgb)?.hasAlpha == false)
        #expect(PNGHeader(Data("not a png".utf8)) == nil)
    }

    private static func pngs(in folder: String) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: screenshots.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

/// A PNG's size and whether it can hold transparency, from its header and chunk list.
struct PNGHeader: Equatable {
    let width: Int
    let height: Int
    /// A colour type with alpha (grey + alpha, or RGBA), or a tRNS chunk.
    let hasAlpha: Bool

    init(width: Int, height: Int, hasAlpha: Bool) {
        self.width = width
        self.height = height
        self.hasAlpha = hasAlpha
    }

    init?(_ data: Data) {
        let bytes = [UInt8](data)
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard bytes.count >= 33, Array(bytes[0..<8]) == signature, Array(bytes[12..<16]) == Array("IHDR".utf8) else {
            return nil
        }
        func integer(at offset: Int) -> Int {
            bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
        }
        width = integer(at: 16)
        height = integer(at: 20)
        let colourType = bytes[25]
        // Walk the chunks for tRNS, which gives a palette or RGB image transparency.
        var offset = 8
        var transparency = false
        while offset + 8 <= bytes.count {
            let length = integer(at: offset)
            let type = String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self)
            if type == "tRNS" { transparency = true }
            if type == "IDAT" || type == "IEND" { break }
            offset += 12 + length
        }
        hasAlpha = colourType == 4 || colourType == 6 || transparency
    }
}
