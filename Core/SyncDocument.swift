//
//  SyncDocument.swift
//  Intervally
//

import Foundation

/// When a record was last written, and by which install. Ordered by `millis`, then
/// `device`, so stamps from two devices never tie.
struct SyncStamp: Codable, Comparable, Hashable, Sendable {
    var millis: Int64
    var device: String

    /// Older than any real write. The starters and an empty register carry it, so the first
    /// edit on either device beats them.
    static let origin = SyncStamp(millis: 0, device: "")

    static func < (a: SyncStamp, b: SyncStamp) -> Bool {
        (a.millis, a.device) < (b.millis, b.device)
    }
}

/// A hybrid logical clock, the cheap variant. It never runs backwards, and every stamp it
/// issues is later than anything this install has written or seen, so an edit made after
/// receiving the other device's presets beats them even when this device's wall clock is
/// behind.
struct SyncClock: Codable, Equatable, Sendable {
    /// This install, generated once.
    var device: String
    var last: Int64 = 0

    mutating func tick(now: Date = Date()) -> SyncStamp {
        let wall = Int64((now.timeIntervalSince1970 * 1000).rounded(.down))
        last = max(wall, last + 1)
        return SyncStamp(millis: last, device: device)
    }

    mutating func observe(_ document: SyncDocument) {
        last = max(last, document.highestMillis)
    }
}

/// One preset's replicated state. A deleted preset stays as a tombstone, or the other
/// device's copy would bring it straight back. The tombstone keeps the last contents, so
/// the empty-list repair has a real preset to restore.
///
/// Two last-writer-wins registers: the contents (workout and tombstone) under `stamp`, and
/// the place in the list under `orderStamp`. A reorder on one device and an edit on the
/// other then both survive: a move can't put back contents it never touched, and an edit
/// can't put back a place it never touched.
struct PresetRecord: Codable, Equatable, Sendable {
    var id: UUID
    var workout: IntervalWorkout
    var deleted: Bool
    /// Where it sits in the list on both devices: the starters at 0, 1 and 2, a new preset
    /// after every other, a moved one between its new neighbours.
    var order: Int64
    /// When the contents were last written.
    var stamp: SyncStamp
    /// When `order` was last written: by the add that created the preset, or by a move.
    var orderStamp: SyncStamp

    /// A preset placed when it was written, as an add places it.
    init(id: UUID, workout: IntervalWorkout, deleted: Bool, order: Int64, stamp: SyncStamp, orderStamp: SyncStamp? = nil) {
        self.id = id
        self.workout = workout
        self.deleted = deleted
        self.order = order
        self.stamp = stamp
        self.orderStamp = orderStamp ?? stamp
    }

    /// The later of its two stamps: the last time anything in it was written.
    var latestStamp: SyncStamp { max(stamp, orderStamp) }

    /// Each register keeps the later write. On an exact tie the receiver keeps its own, as
    /// `Register` does.
    func merged(with other: PresetRecord) -> PresetRecord {
        var out = self
        if other.stamp > stamp {
            out.workout = other.workout
            // A version that predates the activity choice writes every edit without one. Its
            // later edit still wins, but must not reset the activity chosen here to HIIT.
            if out.workout.activity == nil { out.workout.activity = workout.activity }
            out.deleted = other.deleted
            out.stamp = other.stamp
        }
        if other.orderStamp > orderStamp {
            out.order = other.order
            out.orderStamp = other.orderStamp
        }
        return out
    }
}

extension PresetRecord {
    /// Lenient like `IntervalWorkout`: only the id is required. The workout's own id is
    /// forced to the record's, so a record can never describe a preset it isn't filed under.
    /// A record without an order stamp was placed no later than its contents were written.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        var workout = (try? container.decode(IntervalWorkout.self, forKey: .workout)) ?? IntervalWorkout(id: id)
        workout.id = id
        self.init(
            id: id,
            workout: workout,
            deleted: (try? container.decode(Bool.self, forKey: .deleted)) ?? false,
            order: (try? container.decode(Int64.self, forKey: .order)) ?? 0,
            stamp: (try? container.decode(SyncStamp.self, forKey: .stamp)) ?? .origin,
            orderStamp: try? container.decode(SyncStamp.self, forKey: .orderStamp)
        )
    }
}

/// One replicated value. The later stamp wins.
struct Register<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    var value: Value
    var stamp: SyncStamp

    /// On an exact tie the receiver keeps its own. A tie with different contents only comes
    /// from an older app version that re-encoded the value without fields it doesn't know,
    /// and the newer copy must not lose them.
    func merged(with other: Register) -> Register {
        other.stamp > stamp ? other : self
    }
}

/// The presets and the selected preset, as the iPhone and the watch replicate them.
///
/// State-based: each side sends its whole document and the receiver merges, never
/// replaces. Every preset is a last-writer-wins record whose place in the list is a
/// register of its own, a deletion is a tombstone, and the selection is a last-writer-wins
/// register, all stamped by `SyncClock`. That makes `merged(with:)` commutative,
/// associative and idempotent, so the two devices converge however WatchConnectivity
/// orders, drops or repeats what they send.
struct SyncDocument: Equatable, Sendable {
    /// Written into every encoded document, so a later version can tell what an older one
    /// wrote. Not a stored property: two versions holding the same presets are equal, and a
    /// difference here alone must never make them reply to each other forever.
    static let currentSchema = 1

    var presets: [UUID: PresetRecord]
    var selected: Register<UUID?>

    /// The live presets, in the order both devices list them.
    var workouts: [IntervalWorkout] { liveRecords.map(\.workout) }

    var highestMillis: Int64 {
        presets.values.reduce(selected.stamp.millis) { max($0, $1.latestStamp.millis) }
    }

    private var liveRecords: [PresetRecord] {
        presets.values.filter { !$0.deleted }.sorted { ($0.order, $0.id.uuidString) < ($1.order, $1.id.uuidString) }
    }

    // MARK: - Merging

    func merged(with other: SyncDocument) -> SyncDocument {
        var out = self
        for (id, theirs) in other.presets {
            out.presets[id] = out.presets[id]?.merged(with: theirs) ?? theirs
        }
        out.selected = selected.merged(with: other.selected)
        return out
    }

    /// This device's document once `remote` has arrived: merged, then repaired if the merge
    /// emptied the list. The clock observes `remote` first, so a repair's stamp beats
    /// everything in it.
    func receiving(_ remote: SyncDocument, clock: inout SyncClock) -> SyncDocument {
        clock.observe(remote)
        var out = merged(with: remote)
        out.repairIfEmpty(clock: &clock)
        return out
    }

    /// The app needs at least one preset. If each device deleted the other's last one, the
    /// merge is empty: bring back the most recently deleted preset with a new stamp. Both
    /// devices pick the same record, the id breaking any tie, so the repair itself converges.
    @discardableResult
    mutating func repairIfEmpty(clock: inout SyncClock) -> Bool {
        guard liveRecords.isEmpty,
              var newest = presets.values.max(by: { ($0.stamp, $0.id.uuidString) < ($1.stamp, $1.id.uuidString) })
        else { return false }
        newest.deleted = false
        newest.stamp = clock.tick()
        presets[newest.id] = newest
        return true
    }

    // MARK: - Fresh install

    /// The starters' ids, fixed so two fresh installs agree on which preset is Classic. With
    /// a random id each, the first sync would list every starter twice. Never change them:
    /// an install that already holds the starters would gain a second set.
    static let starterIDs: [UUID] = [
        UUID(uuidString: "6A1E0C2B-5D4F-4E43-9C1A-000000000001")!,
        UUID(uuidString: "6A1E0C2B-5D4F-4E43-9C1A-000000000002")!,
        UUID(uuidString: "6A1E0C2B-5D4F-4E43-9C1A-000000000003")!,
    ]

    static let starterWorkouts: [IntervalWorkout] = [
        IntervalWorkout(id: starterIDs[0], name: "Classic", prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 8),
        IntervalWorkout(id: starterIDs[1], name: "Tabata", prepareSeconds: 10, workSeconds: 20, restSeconds: 10, rounds: 8),
        IntervalWorkout(id: starterIDs[2], name: "EMOM", prepareSeconds: 10, workSeconds: 45, restSeconds: 15, rounds: 10),
    ]

    /// A fresh install: the starters with Classic selected, stamped at the origin so any real
    /// edit on either device beats the seed.
    static let fresh: SyncDocument = {
        var presets: [UUID: PresetRecord] = [:]
        for (index, workout) in starterWorkouts.enumerated() {
            presets[workout.id] = PresetRecord(id: workout.id, workout: workout, deleted: false, order: Int64(index), stamp: .origin)
        }
        return SyncDocument(presets: presets, selected: Register(value: starterIDs[0], stamp: .origin))
    }()

    /// A preset list saved before sync existed, taken over as this install's own write. It is
    /// stamped now rather than at the origin, so neither a preset nor the selection can tie
    /// with the other device's seed and leave the two disagreeing for good.
    static func imported(_ workouts: [IntervalWorkout], selectedID: UUID?, clock: inout SyncClock) -> SyncDocument {
        let stamp = clock.tick()
        var presets: [UUID: PresetRecord] = [:]
        for (index, workout) in workouts.enumerated() where presets[workout.id] == nil {
            presets[workout.id] = PresetRecord(id: workout.id, workout: workout, deleted: false, order: Int64(index), stamp: stamp)
        }
        let selection = selectedID.flatMap { presets[$0] == nil ? nil : $0 } ?? workouts.first?.id
        return SyncDocument(presets: presets, selected: Register(value: selection, stamp: stamp))
    }

    // MARK: - Local edits

    /// Saves `workout`, clamped. An existing preset keeps its place, and the stamp of that
    /// place, so an edit can't undo a move the other device made; a new one goes after every
    /// other.
    mutating func upsert(_ workout: IntervalWorkout, clock: inout SyncClock) {
        let stamp = clock.tick()
        if var record = presets[workout.id] {
            record.workout = workout.clamped
            record.deleted = false
            record.stamp = stamp
            presets[workout.id] = record
            return
        }
        let highest = presets.values.map(\.order).max() ?? -1
        presets[workout.id] = PresetRecord(
            id: workout.id, workout: workout.clamped, deleted: false, order: max(stamp.millis, highest + 1), stamp: stamp
        )
    }

    /// Tombstones a live preset. Refused for the last one: there must always be one to run.
    @discardableResult
    mutating func delete(_ id: UUID, clock: inout SyncClock) -> Bool {
        guard var record = presets[id], !record.deleted, liveRecords.count > 1 else { return false }
        record.deleted = true
        record.stamp = clock.tick()
        presets[id] = record
        return true
    }

    mutating func select(_ id: UUID?, clock: inout SyncClock) {
        selected = Register(value: id, stamp: clock.tick())
    }

    /// The gap a move leaves between neighbours, and between presets when they are
    /// renumbered: room for sixteen halvings before a gap fills up.
    static let orderSpacing: Int64 = 1 << 16

    /// Moves live presets the way SwiftUI's `onMove` describes it: `source` and
    /// `destination` are offsets into `workouts` before the move. The moved presets are
    /// placed between their new neighbours; when the neighbours leave no room, as between
    /// the starters, every preset whose place changes is renumbered instead. Either way only
    /// places are written, under `orderStamp`: no preset's contents are, so a concurrent edit
    /// on the other device survives the move, whichever preset it touched. False when
    /// nothing moved.
    @discardableResult
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int, clock: inout SyncClock) -> Bool {
        let live = liveRecords
        let moving = source.filter { live.indices.contains($0) }
        guard !moving.isEmpty, (0...live.count).contains(destination) else { return false }

        var arranged = live.indices.filter { !source.contains($0) }.map { live[$0] }
        let insertAt = destination - moving.filter { $0 < destination }.count
        arranged.insert(contentsOf: moving.map { live[$0] }, at: insertAt)
        guard arranged.map(\.id) != live.map(\.id) else { return false }

        let stamp = clock.tick()
        let after = insertAt + moving.count
        let lower = insertAt > 0 ? arranged[insertAt - 1].order : nil
        let upper = after < arranged.count ? arranged[after].order : nil
        if let orders = Self.orders(count: moving.count, between: lower, and: upper) {
            for (offset, order) in orders.enumerated() {
                place(arranged[insertAt + offset].id, at: order, stamp: stamp)
            }
        } else {
            for (index, record) in arranged.enumerated() where record.order != Int64(index) * Self.orderSpacing {
                place(record.id, at: Int64(index) * Self.orderSpacing, stamp: stamp)
            }
        }
        return true
    }

    /// `count` increasing orders strictly between `lower` and `upper` (either may be open),
    /// or nil when they don't fit.
    private static func orders(count: Int, between lower: Int64?, and upper: Int64?) -> [Int64]? {
        let n = Int64(count)
        switch (lower, upper) {
        case let (lower?, upper?):
            guard upper - lower > n else { return nil }
            let step = (upper - lower) / (n + 1)
            return (1...n).map { lower + step * $0 }
        case let (lower?, nil):
            return (1...n).map { lower + orderSpacing * $0 }
        case let (nil, upper?):
            return (1...n).map { upper - orderSpacing * (n + 1 - $0) }
        case (nil, nil):
            return nil
        }
    }

    private mutating func place(_ id: UUID, at order: Int64, stamp: SyncStamp) {
        presets[id]?.order = order
        presets[id]?.orderStamp = stamp
    }
}

extension SyncDocument: Codable {
    private enum CodingKeys: String, CodingKey {
        case schema, presets, selected
    }

    /// Lenient, so documents from other versions still merge: unknown fields and a higher
    /// `schema` are ignored, an unreadable record costs only that record, and an unreadable
    /// selection reads as none. Only the preset list is required; without it this isn't a
    /// document at all.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decode([LossyRecord].self, forKey: .presets)
        var presets: [UUID: PresetRecord] = [:]
        for case let record? in entries.map(\.record) {
            presets[record.id] = presets[record.id]?.merged(with: record) ?? record
        }
        let selected = (try? container.decode(Register<UUID?>.self, forKey: .selected))
            ?? Register(value: nil, stamp: .origin)
        self.init(presets: presets, selected: selected)
    }

    /// Records sorted by id, so equal documents encode to equal bytes.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchema, forKey: .schema)
        try container.encode(presets.values.sorted { $0.id.uuidString < $1.id.uuidString }, forKey: .presets)
        try container.encode(selected, forKey: .selected)
    }

    private struct LossyRecord: Decodable {
        let record: PresetRecord?
        init(from decoder: Decoder) throws {
            record = try? PresetRecord(from: decoder)
        }
    }
}

// MARK: - Wire format

/// What goes in `updateApplicationContext(_:)`: property-list types only, with the document
/// as LZFSE-compressed JSON.
enum SyncWire {
    static let documentKey = "doc"
    static let schemaKey = "schema"
    /// Makes every context distinct, so a forced re-send after a reinstall is never
    /// coalesced away as unchanged.
    static let sentAtKey = "sentAt"
    /// The theme the user chose (`ThemeStore`), as a JSON `Register<String>`. A key of its own
    /// beside the document rather than a field in it: a version that predates themes reads
    /// only `doc`, so it never sees the theme, never re-encodes it away, and its document
    /// still compares equal to this version's.
    static let themeKey = "theme"
    /// A run the iPhone asked the watch to start (`StartRequest`), sent once, beside the
    /// document. A version that predates it ignores the key.
    static let startKey = "start"

    /// Start on Watch: which preset, asked for when. The ID tells one request from the next,
    /// so a context delivered twice starts nothing twice.
    struct StartRequest: Codable, Equatable, Sendable {
        let id: UUID
        let presetID: UUID
        let requestedAt: Date

        /// A request this old was never picked up: the watch was off the wrist, or out of
        /// reach. It must not start a workout the next time Intervally opens.
        static let lifetime: TimeInterval = 60

        func isFresh(at now: Date) -> Bool {
            let age = now.timeIntervalSince(requestedAt)
            return age < Self.lifetime && age > -30
        }
    }

    /// - Parameter theme: nil sends presets only, as a version that predates themes did.
    static func context(
        for document: SyncDocument, theme: Register<String>? = nil, sentAt: Date = Date(),
        start: StartRequest? = nil
    ) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = try encoder.encode(document)
        let compressed = try (json as NSData).compressed(using: .lzfse) as Data
        var context: [String: Any] = [documentKey: compressed, schemaKey: SyncDocument.currentSchema, sentAtKey: sentAt]
        if let theme {
            context[themeKey] = try encoder.encode(theme)
        }
        if let start {
            context[startKey] = try encoder.encode(start)
        }
        return context
    }

    /// The start request in `context`, or nil. Like `document(from:)`, for the delegate queue.
    static func startRequest(from context: [String: Any]) -> StartRequest? {
        guard let data = context[startKey] as? Data else { return nil }
        return try? JSONDecoder().decode(StartRequest.self, from: data)
    }

    /// The theme in `context`, or nil where there is none: from a version that predates
    /// themes, or one that won't decode. Like `document(from:)`, meant for the delegate queue.
    static func theme(from context: [String: Any]) -> Register<String>? {
        guard let data = context[themeKey] as? Data,
              let theme = try? JSONDecoder().decode(Register<String>.self, from: data),
              !theme.value.isEmpty
        else { return nil }
        return theme
    }

    /// The document in `context`, or nil for anything that isn't one. Meant to run on the
    /// WatchConnectivity delegate queue, before anything hops to the main actor:
    /// `[String: Any]` isn't Sendable, `SyncDocument` is.
    static func document(from context: [String: Any]) -> SyncDocument? {
        guard let compressed = context[documentKey] as? Data,
              let json = try? (compressed as NSData).decompressed(using: .lzfse) as Data
        else { return nil }
        return try? JSONDecoder().decode(SyncDocument.self, from: json)
    }

    /// When the sender sent `context`, by its clock. Nil for anything that doesn't say.
    static func sentAt(from context: [String: Any]) -> Date? {
        context[sentAtKey] as? Date
    }
}
