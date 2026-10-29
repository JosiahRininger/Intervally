//
//  SyncTestSupport.swift
//  IntervallyTests, IntervallyPhoneTests
//

import Foundation
import Testing
import WatchConnectivity
#if os(watchOS)
@testable import Intervally
#else
@testable import IntervallyPhone
#endif

// Compiled into both test bundles: sync runs on both devices, and each has branches the
// other doesn't.

extension PeerSnapshot {
    /// Activated, paired, and the other device has Intervally.
    static let ready = PeerSnapshot(
        isSupported: true,
        activationState: .activated,
        isPaired: true,
        isCounterpartInstalled: true,
        hasContentPending: false
    )
}

/// Stands in for `WCSession`: holds the two contexts as WatchConnectivity would and records
/// every send.
@MainActor
final class FakeTransport: SyncTransport {
    var snapshot: PeerSnapshot = .ready
    var applicationContext: [String: Any] = [:]
    var receivedApplicationContext: [String: Any] = [:]
    /// Thrown by the next sends, while set.
    var sendError: (any Error)?

    private(set) var sent: [[String: Any]] = []
    private(set) var activations = 0
    private(set) var onStateChange: (@MainActor @Sendable () -> Void)?

    var sentDocuments: [SyncDocument] { sent.compactMap(SyncWire.document(from:)) }

    func activate(delegate: any WCSessionDelegate, onStateChange: @escaping @MainActor @Sendable () -> Void) {
        activations += 1
        self.onStateChange = onStateChange
    }

    func updateApplicationContext(_ context: [String: Any]) throws {
        if let sendError { throw sendError }
        applicationContext = context
        sent.append(context)
    }
}

/// Stands in for `Task.sleep`: every sleep waits until the test wakes it, so a debounce is
/// as long as the test says.
@MainActor
final class ManualSleeper {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requested: [Duration] = []

    nonisolated var sleep: @Sendable (Duration) async throws -> Void {
        { [self] duration in await self.wait(duration) }
    }

    private func wait(_ duration: Duration) async {
        requested.append(duration)
        await withCheckedContinuation { waiters.append($0) }
    }

    func wakeAll() {
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// The other device: a copy of a document, edited with a clock of its own.
struct PeerDevice {
    var document: SyncDocument
    var clock = SyncClock(device: "peer-device")

    init(_ document: SyncDocument = .fresh) {
        self.document = document
        clock.observe(document)
    }

    mutating func rename(_ index: Int, to name: String) {
        var workout = document.workouts[index]
        workout.name = name
        document.upsert(workout, clock: &clock)
    }

    mutating func select(_ index: Int) {
        document.select(document.workouts[index].id, clock: &clock)
    }

    var context: [String: Any] {
        // A fixed instant: the tests compare documents, never send times.
        (try? SyncWire.context(for: document, sentAt: Date(timeIntervalSince1970: 1_000))) ?? [:]
    }
}

struct SendFailure: Error {}

extension SyncDocument {
    /// The document as the other device decodes it from an application context.
    func overTheWire() throws -> SyncDocument {
        try #require(SyncWire.document(from: SyncWire.context(for: self)))
    }
}

// MARK: - Every field a preset has

extension IntervalWorkout {
    /// A preset with every field set, the optional ones included: what no merge, older
    /// version or trip over the wire may lose. A field added later belongs here too, or
    /// `IntervalWorkoutTests` fails.
    static let everyFieldSet: IntervalWorkout = {
        var workout = IntervalWorkout(
            id: UUID(uuidString: "3C9A2E51-7D0B-4F6E-8A14-B2C5D7E9F031")!,
            name: "Hill Sprints", prepareSeconds: 20, warmupSeconds: 300, workSeconds: 45,
            restSeconds: 75, rounds: 6, cooldownSeconds: 240, activity: .outdoorRun
        )
        workout.setLabel(PhaseLabel(name: "Climb", symbol: .run), for: .work)
        workout.setLabel(PhaseLabel(name: "Jog", symbol: .easy), for: .rest)
        return workout
    }()

    /// Its Optional stored properties by name, found by reflection rather than listed, so a
    /// field added later is checked without anyone remembering to add it.
    var optionalFieldNames: [String] {
        Mirror(reflecting: self).children.compactMap { child in
            child.value is any ReflectedOptional ? child.label : nil
        }
    }

    /// Those of them that are nil.
    var absentFieldNames: [String] {
        Mirror(reflecting: self).children.compactMap { child in
            (child.value as? any ReflectedOptional)?.isNone == true ? child.label : nil
        }
    }
}

/// Lets reflection tell an Optional property from the rest, and whether it holds a value.
protocol ReflectedOptional {
    var isNone: Bool { get }
}

extension Optional: ReflectedOptional {
    var isNone: Bool { self == nil }
}

/// A preset's optional fields one by one: the ones a version that predates them leaves out.
/// The sync fuzz varies every one, and fails for an Optional property missing here.
enum OptionalWorkoutField: CaseIterable, Sendable {
    case activity, phaseLabels

    /// The property's name, which is also its key on the wire.
    var name: String { "\(self)" }

    func isSet(in workout: IntervalWorkout) -> Bool {
        switch self {
        case .activity: workout.activity != nil
        case .phaseLabels: workout.phaseLabels != nil
        }
    }

    func copy(from source: IntervalWorkout, to target: inout IntervalWorkout) {
        switch self {
        case .activity: target.activity = source.activity
        case .phaseLabels: target.phaseLabels = source.phaseLabels
        }
    }

    func clear(in workout: inout IntervalWorkout) {
        switch self {
        case .activity: workout.activity = nil
        case .phaseLabels: workout.phaseLabels = nil
        }
    }

    /// A value from a few, so that two copies often agree. Emptied labels are among them:
    /// once touched they are never nil again.
    func randomize<G: RandomNumberGenerator>(_ workout: inout IntervalWorkout, using rng: inout G) {
        switch self {
        case .activity:
            workout.activity = [WorkoutActivity.hiit, .outdoorRun, .rowing].randomElement(using: &rng)
        case .phaseLabels:
            let climb = PhaseLabel(name: "Climb", symbol: .run), walk = PhaseLabel(name: "Walk", symbol: .walk)
            workout.phaseLabels = [[:], ["work": climb], ["work": climb, "rest": walk]].randomElement(using: &rng)
        }
    }
}

// MARK: - Versions already out there

/// A version of Intervally already on someone's iPhone or watch. It decodes only the fields
/// it knows, so it holds, and sends back, presets without the rest; and it merges as it
/// shipped.
enum OlderVersion: CaseIterable, Sendable {
    /// 1.1, from before the activity choice and phase names.
    case v11
    /// 1.2, live on the App Store while 1.3 is built.
    case v12

    /// The optional fields it decodes. Every field it lacks altogether is optional, and a
    /// later version adds only optional ones.
    var knownOptionalFields: Set<OptionalWorkoutField> {
        switch self {
        case .v11: []
        case .v12: [.activity, .phaseLabels]
        }
    }

    func knows(_ field: OptionalWorkoutField) -> Bool {
        knownOptionalFields.contains(field)
    }

    /// `workout` as this version decodes it. Its decoder skips keys it doesn't know, and a
    /// field it lacks is optional and encoded under its own name only when set
    /// (`IntervalWorkoutTests`), so clearing those fields is exactly what it reads.
    func reading(_ workout: IntervalWorkout) -> IntervalWorkout {
        var held = workout
        for field in OptionalWorkoutField.allCases where !knows(field) {
            field.clear(in: &held)
        }
        return held
    }

    /// `document` as this version decodes it, which is also all it can send back.
    func reading(_ document: SyncDocument) -> SyncDocument {
        var held = document
        held.presets = document.presets.mapValues { record in
            var record = record
            record.workout = reading(record.workout)
            return record
        }
        return held
    }

    /// Only the fields of `workout` this version doesn't know, on an otherwise blank preset:
    /// two presets agree on those fields exactly when these are equal.
    func unknownFields(of workout: IntervalWorkout) -> IntervalWorkout {
        var unknown = IntervalWorkout(id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
        for field in OptionalWorkoutField.allCases where !knows(field) {
            field.copy(from: workout, to: &unknown)
        }
        return unknown
    }

    /// `PresetRecord.merged(with:)` as 1.2 shipped it: the activity and phase names came from
    /// the other copy only when that copy was newer or tied, never when this one was newer.
    /// On what 1.1 reads, where they are always nil, it is 1.1's plain last writer wins.
    func merged(_ mine: PresetRecord, with theirs: PresetRecord) -> PresetRecord {
        var out = mine
        if theirs.stamp > mine.stamp {
            out.workout = theirs.workout
            if out.workout.activity == nil { out.workout.activity = mine.workout.activity }
            if out.workout.phaseLabels == nil { out.workout.phaseLabels = mine.workout.phaseLabels }
            out.deleted = theirs.deleted
            out.stamp = theirs.stamp
        } else if theirs.stamp == mine.stamp {
            if out.workout.activity == nil { out.workout.activity = theirs.workout.activity }
            if out.workout.phaseLabels == nil { out.workout.phaseLabels = theirs.workout.phaseLabels }
        }
        if theirs.orderStamp > mine.orderStamp {
            out.order = theirs.order
            out.orderStamp = theirs.orderStamp
        }
        return out
    }

    /// `SyncDocument.receiving(_:clock:)` as this version does it, on `remote` as it reads it.
    func receiving(_ remote: SyncDocument, into local: SyncDocument, clock: inout SyncClock) -> SyncDocument {
        let remote = reading(remote)
        clock.observe(remote)
        var out = local
        for (id, theirs) in remote.presets {
            out.presets[id] = out.presets[id].map { merged($0, with: theirs) } ?? theirs
        }
        out.selected = local.selected.merged(with: remote.selected)
        out.repairIfEmpty(clock: &clock)
        return out
    }
}
