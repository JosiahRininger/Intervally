//
//  RunDiagnostics.swift
//  Intervally
//

import Foundation

/// A record of what a run went through, kept on the device for the user to share: Health
/// access, each workout session asked for and what HealthKit said, the app moving between
/// foreground and background, and the cues. The unified log needs a Mac and a cable to read;
/// this needs neither, and shows why a run fell silent or never reached Health.
///
/// Thread-safe, as HealthKit calls back on its own queues. Nothing leaves the device unless
/// the user shares it from Settings > Apple Health > Diagnostics.
final class RunDiagnostics: @unchecked Sendable {
    static let shared = RunDiagnostics()

    struct Entry: Codable, Equatable, Sendable {
        let date: Date
        let text: String
    }

    /// Enough for a few workouts, small enough to read on a phone.
    static let capacity = 400

    private let lock = NSLock()
    private var entries: [Entry]
    private let url: URL?

    init(url: URL? = RunDiagnostics.defaultURL) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        } else {
            entries = []
        }
    }

    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("run-diagnostics.json")
    }

    func note(_ text: String, at date: Date = Date()) {
        lock.withLock {
            entries.append(Entry(date: date, text: text))
            if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
            save()
        }
    }

    var all: [Entry] { lock.withLock { entries } }

    func clear() {
        lock.withLock {
            entries.removeAll()
            save()
        }
    }

    /// Everything, oldest first, one line each, for sharing.
    var text: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        return all.map { "\(formatter.string(from: $0.date))  \($0.text)" }.joined(separator: "\n")
    }

    /// An error as HealthKit and AVFoundation report it: domain and code, which say far more
    /// than the localized text alone.
    static func describe(_ error: any Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    }

    /// Called with the lock held.
    private func save() {
        guard let url, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
