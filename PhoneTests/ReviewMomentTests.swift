//
//  ReviewMomentTests.swift
//  IntervallyPhoneTests
//

import Foundation
import SwiftUI
import Testing
@testable import IntervallyPhone

/// Where a rating prompt may land: on the library or History, with the app in front and no run
/// going or on screen, once a version. Checked again as the request lands, a second after its
/// moment, and buying Pro is one more moment, asked on the next return to the library.
@Suite("Review moments")
@MainActor
struct ReviewMomentTests {
    let defaults = makeTestDefaults()

    /// A ledger well past `ReviewPolicy`'s first days, on the library with the app in front:
    /// calm, so a test changes only what it is about. Requests land at once.
    private func ledger() -> ReviewLedger {
        let reviews = ReviewLedger(defaults: makeTestDefaults())
        reviews.recordOpen(now: Date().addingTimeInterval(-30 * 86_400))
        reviews.requestDelay = .zero
        reviews.select(.workouts)
        reviews.show(.library, in: .workouts)
        return reviews
    }

    /// `ReviewMoment.canPresent` with everything calm but what a check changes.
    private func canPresent(
        runActive: Bool = false, scenePhase: ScenePhase = .active, topScreen: ReviewMoment.Screen = .library,
        lastPromptVersion: String? = nil, currentVersion: String = "1.3"
    ) -> Bool {
        ReviewMoment.canPresent(
            runActive: runActive, scenePhase: scenePhase, topScreen: topScreen,
            lastPromptVersion: lastPromptVersion, currentVersion: currentVersion
        )
    }

    /// This iPhone's run on stand-ins, wired to `reviews` the way the app wires it.
    private func run(wiredTo reviews: ReviewLedger) -> (PhoneRun, WorkoutStore) {
        let store = WorkoutStore(defaults: defaults)
        let run = PhoneRun(
            store: store, pro: FakePro(), theme: ThemeStore(defaults: defaults), output: FakeCueOutput(),
            workout: FakeWorkoutSession(), notifications: FakeBackstop(), presenter: RecordingPresenter(),
            defaults: defaults
        )
        _ = PhoneServices(store: store, pro: ProStore(defaults: defaults), reviews: reviews, run: run)
        return (run, store)
    }

    @Test("Never while a run is going or on screen, here or from the watch")
    func blockedDuringRun() throws {
        #expect(canPresent())
        #expect(!canPresent(runActive: true))
        #expect(!canPresent(runActive: true, topScreen: .summary))

        let reviews = ledger()
        let (run, store) = run(wiredTo: reviews)
        #expect(reviews.canPresentNow)
        let tabata = try #require(store.workouts.first { $0.name == "Tabata" })
        run.start(tabata)
        #expect(!reviews.canPresentNow, "Start covers the app with the run")
        run.close()
        #expect(reviews.canPresentNow, "Ended or done, the screen has closed")

        // A workout on the watch takes the screen here too.
        run.mirror.apply(RunMirrorState(workout: tabata, status: .running, anchor: Date().addingTimeInterval(-20)))
        #expect(!reviews.canPresentNow)
    }

    @Test("Only on the library or History, with nothing over them, and the app in front")
    func blockedOffLibraryOrSummary() {
        #expect(canPresent(topScreen: .library))
        #expect(canPresent(topScreen: .summary))
        #expect(!canPresent(topScreen: .other))
        #expect(!canPresent(scenePhase: .inactive), "Control Center, a call, the app switcher")
        #expect(!canPresent(scenePhase: .background))

        // What the tabs report: the screen of the one in front counts.
        let reviews = ledger()
        #expect(reviews.topScreen == .library)
        reviews.show(.other, in: .workouts)
        #expect(reviews.topScreen == .other, "An editor pushed, or a sheet over the list")
        #expect(!reviews.canPresentNow)
        reviews.show(.summary, in: .history)
        reviews.select(.history)
        #expect(reviews.topScreen == .summary, "History's sessions, or one session's summary")
        #expect(reviews.canPresentNow)
        reviews.show(.other, in: .history)
        #expect(!reviews.canPresentNow, "Settings over History")

        // Before the tabs first show, there is only the welcome.
        #expect(ReviewLedger(defaults: makeTestDefaults()).topScreen == .other)
    }

    @Test("Once a version, whichever moment asks")
    func oncePerVersion() async {
        #expect(!canPresent(lastPromptVersion: "1.3", currentVersion: "1.3"))
        #expect(canPresent(lastPromptVersion: "1.2", currentVersion: "1.3"), "1.2's ask doesn't count against 1.3")
        #expect(canPresent(lastPromptVersion: nil, currentVersion: "1.3"))

        let reviews = ledger()
        let asked = Counter()
        await reviews.askLater(.finishedWorkout(count: 5)) { asked.increment() }.value
        #expect(asked.value == 1)
        #expect(reviews.snapshot.lastRequestVersion == ReviewLedger.appVersion)
        #expect(!reviews.canPresentNow)
        await reviews.askLater(.lookedBackAtSession(sessionCount: 9)) { asked.increment() }.value
        reviews.show(.other, in: .workouts)
        reviews.markPaidForPro { asked.increment() }
        await reviews.show(.library, in: .workouts)?.value
        #expect(asked.value == 1, "Neither a session nor a purchase asks again in this version")
    }

    @Test("A request checks again as it lands: one that can't is dropped, and spends nothing")
    func delayedRequestRechecksAtFire() async throws {
        let reviews = ledger()
        let asked = Counter()
        let moment = ReviewMoment.lookedBackAtSession(sessionCount: 5)

        // Calm when made, each time, then something comes up in the second before it lands.
        #expect(reviews.canPresentNow)
        var request = reviews.askLater(moment) { asked.increment() }
        reviews.show(.other, in: .workouts)
        await request.value
        #expect(asked.value == 0, "Settings opened")
        reviews.show(.library, in: .workouts)

        request = reviews.askLater(moment) { asked.increment() }
        reviews.scenePhase = .background
        await request.value
        #expect(asked.value == 0, "The phone locked")
        reviews.scenePhase = .active

        let (run, store) = run(wiredTo: reviews)
        request = reviews.askLater(moment) { asked.increment() }
        run.start(try #require(store.workouts.first))
        await request.value
        #expect(asked.value == 0, "A run started")
        run.close()
        #expect(reviews.snapshot.lastRequest == nil, "Nothing is spent on a request that never went in")

        // It is how things stand as it lands that counts: Settings closed in time lets it in.
        reviews.show(.other, in: .workouts)
        request = reviews.askLater(moment) { asked.increment() }
        reviews.show(.library, in: .workouts)
        await request.value
        #expect(asked.value == 1)
    }

    @Test("Buying Pro asks once, on the next return to the library still in front as it lands")
    func purchaseCountsAsMoment() async {
        // A purchase needs no workouts or open days of its own, only the first days past.
        let calendar = Calendar(identifier: .gregorian)
        let opened = Date(timeIntervalSince1970: 1_790_000_000)
        let snapshot = ReviewLedger.Snapshot(firstOpened: opened)
        #expect(ReviewPolicy.shouldAsk(.paidForPro, ledger: snapshot, version: "1.3", now: opened.addingTimeInterval(3 * 86_400), calendar: calendar))
        #expect(!ReviewPolicy.shouldAsk(.paidForPro, ledger: snapshot, version: "1.3", now: opened.addingTimeInterval(86_400), calendar: calendar))

        // Bought from the paywall + opened over the library.
        let reviews = ledger()
        let asked = Counter()
        reviews.show(.other, in: .workouts)
        reviews.markPaidForPro { asked.increment() }
        #expect(reviews.paidForPro)
        #expect(reviews.show(.other, in: .workouts) == nil, "Nothing asks while the paywall is up")

        // The paywall closes, but the new workout's editor opens before the request lands.
        var landing = reviews.show(.library, in: .workouts)
        reviews.show(.other, in: .workouts)
        await landing?.value
        #expect(asked.value == 0)
        #expect(reviews.paidForPro, "Still waiting for a real return")

        // History isn't the library.
        reviews.show(.summary, in: .history)
        #expect(reviews.select(.history) == nil)

        // Back from the editor to the library, and it stays in front: the request goes in.
        reviews.select(.workouts)
        landing = reviews.show(.library, in: .workouts)
        await landing?.value
        #expect(asked.value == 1)
        #expect(!reviews.paidForPro)
        #expect(reviews.snapshot.lastRequestVersion == ReviewLedger.appVersion)

        // Once: the next return has nothing to ask.
        reviews.show(.other, in: .workouts)
        #expect(reviews.show(.library, in: .workouts) == nil)
        #expect(asked.value == 1)
    }
}
