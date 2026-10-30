//
//  RunDiagnostics.swift
//  Intervally
//

import Foundation

/// A record of what a run went through, kept on the device for the user to share: Health
/// access, each workout session asked for and what HealthKit said, the app moving between
/// foreground and background, the cues, and how late the run's interval changes were
/// announced (`BoundaryTimingTally`). The unified log needs a Mac and a cable to read; this
/// needs neither, and shows why a run fell silent or never reached Health.
///
/// Thread-safe, as HealthKit calls back on its own queues. Nothing leaves the device unless
/// the user shares it from Settings > Apple Health > Diagnostics.
///
/// A note is kept in memory and written out two seconds later, off the main thread, with
/// whatever else was noted meanwhile. The whole file used to be rewritten on the main thread
/// at every note, and the watch notes the app coming forward: each wrist raise paid for a
/// write before the screen could update. The moments after which the app may not run again
/// for a while, a run's finish or End and the app leaving the screen, write at once
/// (`flush()`).
final class RunDiagnostics: @unchecked Sendable {
    static let shared = RunDiagnostics()

    struct Entry: Codable, Equatable, Sendable {
        let date: Date
        let text: String
        /// How many more times the same line was noted straight after this one, and when it
        /// last was: one entry for a run of them, so a flood can't push the rest out.
        var repeats = 0
        var lastDate: Date?
    }

    /// Enough for a few workouts, small enough to read on a phone.
    static let capacity = 400

    /// How long a note waits for the ones after it, to be written out with them.
    static let writeDelay: TimeInterval = 2

    /// Writes the encoded log to its file. Injectable so tests can count the writes.
    typealias Write = @Sendable (_ data: Data, _ url: URL) -> Void

    /// Runs `work` once `delay` seconds have passed. Injectable so tests can say when.
    typealias Schedule = @Sendable (_ delay: TimeInterval, _ work: @escaping @Sendable () -> Void) -> Void

    private let lock = NSLock()
    private var entries: [Entry]
    /// Something was noted since the last write.
    private var isDirty = false
    /// A write is already waiting to go, and will take whatever is noted before it does.
    private var isWriteScheduled = false
    /// One write at a time, each taking the entries as they are once it holds this, so an
    /// older copy of the log can never land on top of a newer one. Taken before `lock`, never
    /// inside it, and not by `note`, which never waits on the disk.
    private let writing = NSLock()
    private let url: URL?
    private let write: Write
    private let schedule: Schedule

    init(
        url: URL? = RunDiagnostics.defaultURL,
        write: @escaping Write = RunDiagnostics.writeFile,
        schedule: @escaping Schedule = RunDiagnostics.inBackground
    ) {
        self.url = url
        self.write = write
        self.schedule = schedule
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

    /// The log's file, rewritten whole and atomically, its folder made first if need be.
    static let writeFile: Write = { data, url in
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// On a background queue.
    static let inBackground: Schedule = { delay, work in
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: work)
    }

    func note(_ text: String, at date: Date = Date()) {
        let schedulesWrite: Bool = lock.withLock {
            if let last = entries.indices.last, entries[last].text == text {
                entries[last].repeats += 1
                entries[last].lastDate = date
            } else {
                entries.append(Entry(date: date, text: text))
                if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
            }
            isDirty = true
            guard !isWriteScheduled else { return false }
            isWriteScheduled = true
            return true
        }
        // Outside the lock, so a schedule that runs the write straight away can't deadlock.
        guard schedulesWrite else { return }
        schedule(Self.writeDelay) { [weak self] in self?.save(fromSchedule: true) }
    }

    /// Writes out everything noted so far, now and on this thread, rather than two seconds on.
    /// Nothing to write when nothing was noted since the last write.
    func flush() {
        save(fromSchedule: false)
    }

    var all: [Entry] { lock.withLock { entries } }

    func clear() {
        lock.withLock {
            entries.removeAll()
            isDirty = true
        }
        // Cleared from Settings, it stays cleared even if the app is ended a moment later.
        flush()
    }

    /// Everything, oldest first, one line each, for sharing.
    var text: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        return all.map { entry in
            let line = "\(formatter.string(from: entry.date))  \(entry.text)"
            guard entry.repeats > 0, let last = entry.lastDate else { return line }
            return line + "  (\(entry.repeats + 1) times, until \(formatter.string(from: last)))"
        }.joined(separator: "\n")
    }

    /// An error as HealthKit and AVFoundation report it: domain and code, which say far more
    /// than the localized text alone.
    static func describe(_ error: any Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    }

    /// - Parameter fromSchedule: Whether this is the write a note scheduled. Its slot is freed
    ///   as it takes the entries, so a note that comes after them schedules the next write.
    private func save(fromSchedule: Bool) {
        writing.withLock {
            let unsaved: [Entry]? = lock.withLock {
                if fromSchedule { isWriteScheduled = false }
                guard isDirty else { return nil }
                isDirty = false
                return entries
            }
            guard let unsaved, let url, let data = try? JSONEncoder().encode(unsaved) else { return }
            write(data, url)
        }
    }
}

extension RunDiagnostics.Entry {
    /// Entries saved before repeats were counted have neither field.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        text = try container.decode(String.self, forKey: .text)
        repeats = try container.decodeIfPresent(Int.self, forKey: .repeats) ?? 0
        lastDate = try container.decodeIfPresent(Date.self, forKey: .lastDate)
    }
}
