//
//  ThemeSyncTests.swift
//  IntervallyTests, IntervallyPhoneTests
//

import Foundation
import Testing
#if os(watchOS)
@testable import Intervally
#else
@testable import IntervallyPhone
#endif

/// The theme the user chose: one last-writer-wins register per device, gated on Pro where it
/// shows, and carried beside the presets so the iPhone and the watch wear the same one.
@Suite("Theme store")
@MainActor
struct ThemeStoreTests {
    let defaults = makeTestDefaults()

    @Test("Raw values travel between devices and are stored, so they never change")
    func rawValues() {
        #expect(AppTheme.allCases.map(\.rawValue) == ["classic", "pastel"])
        #expect(AppTheme.allCases.map(\.title) == ["Classic", "Pastel"])
        #expect(AppTheme.allCases.filter(\.isPro) == [.pastel])
    }

    @Test("Without Pro the app shows Classic, whatever is stored; with Pro, what is stored")
    func effectiveIsGated() {
        for stored in AppTheme.allCases {
            #expect(AppTheme.effective(stored: stored, isPro: false) == .classic)
            #expect(AppTheme.effective(stored: stored, isPro: true) == stored)
        }
        #expect(AppTheme.pastel.isLocked(isPro: false))
        #expect(AppTheme.pastel.isLocked(isPro: true) == false)
        #expect(AppTheme.classic.isLocked(isPro: false) == false)
    }

    @Test("A fresh install is Classic, never chosen, and anything chosen beats it")
    func fresh() {
        let store = ThemeStore(defaults: defaults)
        #expect(store.stored == .classic)
        #expect(store.register == ThemeStore.unchosen)
        #expect(store.register.stamp == .origin)
    }

    @Test("A choice is saved, survives a relaunch, and is offered to the other device once")
    func choosePersists() {
        let store = ThemeStore(defaults: defaults)
        let sent = Counter()
        store.onLocalChange = { sent.increment() }
        store.choose(.pastel, now: Date(timeIntervalSince1970: 1_000))
        store.choose(.pastel, now: Date(timeIntervalSince1970: 2_000))
        #expect(sent.value == 1, "Choosing what is already stored stamps nothing")
        #expect(store.stored == .pastel)
        #expect(store.register.stamp.millis == 1_000_000)

        let relaunched = ThemeStore(defaults: defaults)
        #expect(relaunched.register == store.register)
    }

    @Test("A refund shows Classic but keeps the choice, so a restore brings Pastel back")
    func refundKeepsTheChoice() {
        let store = ThemeStore(defaults: defaults)
        store.choose(.pastel)
        #expect(store.effective(isPro: true) == .pastel)
        #expect(store.effective(isPro: false) == .classic)
        #expect(store.stored == .pastel)
        #expect(store.effective(isPro: true) == .pastel)
    }

    @Test("A choice is stamped after every choice seen, even from a device whose clock runs ahead")
    func choiceBeatsWhatWasSeen() {
        let store = ThemeStore(defaults: defaults)
        let ahead = Register(value: "pastel", stamp: SyncStamp(millis: 9_000_000_000_000, device: "watch"))
        store.merge(ahead)
        store.choose(.classic, now: Date(timeIntervalSince1970: 1_000))
        #expect(store.register.stamp > ahead.stamp)
        #expect(store.stored == .classic)
    }

    @Test("The later choice wins; an older one is ignored; an exact tie keeps this device's")
    func lastWriterWins() {
        let store = ThemeStore(defaults: defaults)
        store.choose(.pastel, now: Date(timeIntervalSince1970: 1_000))
        let mine = store.register
        let remoteChanges = Counter()
        store.onRemoteChange = { remoteChanges.increment() }

        #expect(store.merge(Register(value: "classic", stamp: SyncStamp(millis: 500_000, device: "z"))) == false)
        #expect(store.merge(Register(value: "classic", stamp: mine.stamp)) == false)
        #expect(store.register == mine)
        #expect(remoteChanges.value == 0)

        let later = Register(value: "classic", stamp: SyncStamp(millis: 2_000_000, device: "a"))
        #expect(store.merge(later))
        #expect(store.stored == .classic)
        #expect(remoteChanges.value == 1)
        #expect(ThemeStore(defaults: defaults).register == later, "A merged choice is saved")
    }

    @Test("A theme from a later version is kept and passed on, and shows as Classic here")
    func unknownValue() {
        let store = ThemeStore(defaults: defaults)
        let future = Register(value: "midnight", stamp: SyncStamp(millis: 5, device: "watch"))
        store.merge(future)
        #expect(store.register == future)
        #expect(store.stored == .classic)
        #expect(store.effective(isPro: true) == .classic)
    }

    @Test("An unreadable stored choice reads as never chosen")
    func unreadable() {
        defaults.set(Data("not json".utf8), forKey: ThemeStore.Key.register)
        #expect(ThemeStore(defaults: defaults).register == ThemeStore.unchosen)
        let empty = try? JSONEncoder().encode(Register(value: "", stamp: SyncStamp(millis: 9, device: "x")))
        defaults.set(empty, forKey: ThemeStore.Key.register)
        #expect(ThemeStore(defaults: defaults).register == ThemeStore.unchosen)
    }

    @Test("Each install has its own tie-breaker, kept across launches")
    func deviceIdentity() throws {
        _ = ThemeStore(defaults: defaults)
        let device = try #require(defaults.string(forKey: ThemeStore.Key.device))
        let store = ThemeStore(defaults: defaults)
        store.choose(.pastel)
        #expect(store.register.stamp.device == device)
        #expect(ThemeStore(defaults: makeTestDefaults()).register.stamp.device == "", "Unchosen carries the origin")
    }

    @Test("The complication reads the theme without a store, gated on the cached Pro flag")
    func complicationReader() {
        #expect(ThemeStore.Key.cachedIsPro == ProStore.Key.cachedIsPro)
        #expect(ThemeStore.effective(in: defaults) == .classic)
        ThemeStore(defaults: defaults).choose(.pastel)
        #expect(ThemeStore.effective(in: defaults) == .classic, "No Pro cached")
        defaults.set(true, forKey: ProStore.Key.cachedIsPro)
        #expect(ThemeStore.effective(in: defaults) == .pastel)
    }

    #if DEBUG
    @Test("-qaTheme pins what shows for the launch, saves nothing, and a real choice ends it")
    func qaPin() {
        let store = ThemeStore(defaults: defaults)
        store.pinForQA(.pastel)
        #expect(store.effective(isPro: false) == .pastel)
        #expect(store.register == ThemeStore.unchosen)
        #expect(ThemeStore(defaults: defaults).effective(isPro: true) == .classic)

        store.choose(.classic)
        #expect(store.qaPin == nil)
        #expect(store.effective(isPro: true) == .classic)
    }
    #endif

    @Test("-qaTheme takes classic or pastel, nothing else", arguments: [
        ("classic", AppTheme.classic as AppTheme?), ("pastel", .pastel), (" PASTEL ", .pastel),
        ("pink", nil), ("", nil), ("dark", nil),
    ])
    func qaFlag(spec: String, theme: AppTheme?) {
        #expect(AppTheme.qaOverride(spec) == theme)
    }
}

/// The theme over WatchConnectivity: a key of its own beside the presets' document.
@Suite("Theme sync")
@MainActor
struct ThemeSyncTests {
    let defaults = makeTestDefaults()
    let transport = FakeTransport()

    private func makeSync(
        store: WorkoutStore? = nil,
        theme: ThemeStore? = nil,
        transport: FakeTransport? = nil
    ) -> (WatchSync, ThemeStore) {
        let theme = theme ?? ThemeStore(defaults: defaults)
        let sync = WatchSync(
            store: store ?? WorkoutStore(defaults: defaults), theme: theme,
            transport: transport ?? self.transport, sleep: WatchSyncTests.neverSends,
            now: { Date(timeIntervalSince1970: 5_000) }
        )
        return (sync, theme)
    }

    private func chosen(_ theme: AppTheme, at millis: Int64, by device: String = "peer") -> Register<String> {
        Register(value: theme.rawValue, stamp: SyncStamp(millis: millis, device: device))
    }

    // MARK: Wire

    @Test("The theme rides beside the document, and the document still reads as before")
    func wire() throws {
        let theme = chosen(.pastel, at: 42)
        let context = try SyncWire.context(for: .fresh, theme: theme, sentAt: Date(timeIntervalSince1970: 1))
        #expect(SyncWire.theme(from: context) == theme)
        // What a version that predates themes reads: the document alone, unchanged.
        #expect(SyncWire.document(from: context) == .fresh)
        #expect(Set(context.keys) == [SyncWire.documentKey, SyncWire.schemaKey, SyncWire.sentAtKey, SyncWire.themeKey])
    }

    @Test("Presets alone, as an older version sends them, carry no theme")
    func missingKey() throws {
        let context = try SyncWire.context(for: .fresh, sentAt: Date(timeIntervalSince1970: 1))
        #expect(context[SyncWire.themeKey] == nil)
        #expect(SyncWire.theme(from: context) == nil)
    }

    @Test("A theme that won't decode is no theme")
    func garbage() {
        let contexts: [[String: Any]] = [
            [SyncWire.themeKey: "pastel"],
            [SyncWire.themeKey: Data("{".utf8)],
            [SyncWire.themeKey: Data(#"{"value":"","stamp":{"millis":1,"device":"x"}}"#.utf8)],
            [SyncWire.themeKey: Data(#"{"value":"pastel"}"#.utf8)],
        ]
        for context in contexts {
            #expect(SyncWire.theme(from: context) == nil)
        }
    }

    // MARK: Sending

    @Test("A choice is sent, though the presets haven't changed, and only once")
    func choiceIsSent() {
        let (sync, theme) = makeSync()
        sync.push()
        #expect(transport.sent.count == 1)
        theme.choose(.pastel)
        sync.push()
        sync.push()
        #expect(transport.sent.count == 2)
        #expect(SyncWire.theme(from: transport.sent[1]) == theme.register)
    }

    @Test("A choice goes out through the debounce, like a preset edit")
    func choiceIsDebounced() async {
        let sleeper = ManualSleeper()
        let theme = ThemeStore(defaults: defaults)
        let sync = WatchSync(store: WorkoutStore(defaults: defaults), theme: theme, transport: transport, sleep: sleeper.sleep)
        theme.choose(.pastel)
        #expect(transport.sent.isEmpty)
        #expect(await waitUntil { sleeper.requested.count == 1 })
        sleeper.wakeAll()
        #expect(await waitUntil { transport.sent.count == 1 })
        #expect(SyncWire.theme(from: transport.sent[0]) == theme.register)
        withExtendedLifetime(sync) {}
    }

    @Test("A theme never chosen is no reason to send")
    func unchosenSendsNothing() throws {
        let store = WorkoutStore(defaults: defaults)
        let (sync, _) = makeSync(store: store)
        // The other device sent these presets, from a version without themes.
        transport.receivedApplicationContext = try SyncWire.context(for: store.document, sentAt: Date(timeIntervalSince1970: 9))
        sync.push()
        #expect(transport.sent.isEmpty)
    }

    @Test("Nothing is sent to a device whose own last context holds this theme")
    func skipsWhatTheOtherDeviceSent() throws {
        let store = WorkoutStore(defaults: defaults)
        let (sync, theme) = makeSync(store: store)
        let theirs = chosen(.pastel, at: 77)
        theme.merge(theirs)
        transport.receivedApplicationContext = try SyncWire.context(for: store.document, theme: theirs, sentAt: Date(timeIntervalSince1970: 9))
        sync.push()
        #expect(transport.sent.isEmpty)
    }

    // MARK: Receiving

    @Test("A later choice from the other device is taken, and answered with nothing")
    func takesLaterChoice() {
        let store = WorkoutStore(defaults: defaults)
        let (sync, theme) = makeSync(store: store)
        sync.receive(store.document, theme: chosen(.pastel, at: 10))
        #expect(theme.stored == .pastel)
        #expect(transport.sent.isEmpty)
    }

    @Test("An older choice is answered with this device's later one")
    func answersOlderChoice() throws {
        let store = WorkoutStore(defaults: defaults)
        let (sync, theme) = makeSync(store: store)
        theme.choose(.pastel, now: Date(timeIntervalSince1970: 1_000))
        sync.receive(store.document, theme: chosen(.classic, at: 10))
        #expect(theme.stored == .pastel)
        let reply = try #require(transport.sent.last)
        #expect(transport.sent.count == 1)
        #expect(SyncWire.theme(from: reply) == theme.register)
    }

    @Test("A fresh install's unchosen theme is answered with the choice, so it catches up")
    func answersFreshInstall() {
        let store = WorkoutStore(defaults: defaults)
        let (sync, theme) = makeSync(store: store)
        theme.choose(.pastel)
        sync.push()
        sync.receive(store.document, theme: ThemeStore.unchosen)
        #expect(transport.sent.count == 2, "Forced, though this device sent it before")
    }

    @Test("A device that sends no theme, an older version, is never answered for it")
    func olderVersionIsLeftAlone() {
        let store = WorkoutStore(defaults: defaults)
        let (sync, theme) = makeSync(store: store)
        theme.choose(.pastel)
        let before = theme.register
        sync.receive(store.document)
        #expect(theme.register == before)
        #expect(transport.sent.isEmpty)
    }

    @Test("Without a readable document nothing is taken, the theme included")
    func noDocumentNoTheme() {
        let (sync, theme) = makeSync()
        sync.receive(nil, theme: chosen(.pastel, at: 10))
        #expect(theme.stored == .classic)
    }

    @Test("Activation takes a theme that arrived while the app was closed")
    func activationTakesPendingTheme() throws {
        let store = WorkoutStore(defaults: defaults)
        let (sync, theme) = makeSync(store: store)
        transport.receivedApplicationContext = try SyncWire.context(
            for: store.document, theme: chosen(.pastel, at: 10), sentAt: Date(timeIntervalSince1970: 9)
        )
        sync.sessionDidActivate()
        #expect(theme.stored == .pastel)
        #expect(transport.sent.isEmpty, "The other device already holds both")
    }

    // MARK: Two devices

    /// Delivers the latest context each side sent, as WatchConnectivity would, until neither
    /// has anything new. Returns how many exchanges it took.
    private func settle(_ phone: (WatchSync, FakeTransport), _ watch: (WatchSync, FakeTransport)) -> Int {
        var phoneSent = 0, watchSent = 0, exchanges = 0
        while exchanges < 10 {
            var delivered = false
            if phone.1.sent.count > phoneSent, let last = phone.1.sent.last {
                phoneSent = phone.1.sent.count
                watch.0.receive(SyncWire.document(from: last), theme: SyncWire.theme(from: last))
                delivered = true
            }
            if watch.1.sent.count > watchSent, let last = watch.1.sent.last {
                watchSent = watch.1.sent.count
                phone.0.receive(SyncWire.document(from: last), theme: SyncWire.theme(from: last))
                delivered = true
            }
            if !delivered { break }
            exchanges += 1
        }
        return exchanges
    }

    @Test("Chosen on both devices at once, both settle on the later choice within two exchanges")
    func converges() {
        let phoneTransport = FakeTransport(), watchTransport = FakeTransport()
        let phoneTheme = ThemeStore(defaults: makeTestDefaults())
        let watchTheme = ThemeStore(defaults: makeTestDefaults())
        let phone = WatchSync(store: WorkoutStore(defaults: makeTestDefaults()), theme: phoneTheme, transport: phoneTransport, sleep: WatchSyncTests.neverSends)
        let watch = WatchSync(store: WorkoutStore(defaults: makeTestDefaults()), theme: watchTheme, transport: watchTransport, sleep: WatchSyncTests.neverSends)

        phoneTheme.choose(.pastel, now: Date(timeIntervalSince1970: 2_000))
        // The watch's clock runs behind: its choice, made earlier, still loses.
        watchTheme.choose(.classic, now: Date(timeIntervalSince1970: 1_000))
        watchTheme.choose(.pastel, now: Date(timeIntervalSince1970: 1_001))
        watchTheme.choose(.classic, now: Date(timeIntervalSince1970: 1_002))
        phone.push()
        watch.push()

        let exchanges = settle((phone, phoneTransport), (watch, watchTransport))
        #expect(phoneTheme.register == watchTheme.register)
        #expect(phoneTheme.stored == .pastel)
        #expect(exchanges <= 2)
    }

    @Test("A choice made after seeing the other device's wins, whichever clock is behind")
    func laterChoiceWinsOnASlowClock() {
        let phoneTransport = FakeTransport(), watchTransport = FakeTransport()
        let phoneTheme = ThemeStore(defaults: makeTestDefaults())
        let watchTheme = ThemeStore(defaults: makeTestDefaults())
        let phone = WatchSync(store: WorkoutStore(defaults: makeTestDefaults()), theme: phoneTheme, transport: phoneTransport, sleep: WatchSyncTests.neverSends)
        let watch = WatchSync(store: WorkoutStore(defaults: makeTestDefaults()), theme: watchTheme, transport: watchTransport, sleep: WatchSyncTests.neverSends)

        phoneTheme.choose(.pastel, now: Date(timeIntervalSince1970: 50_000))
        phone.push()
        _ = settle((phone, phoneTransport), (watch, watchTransport))
        #expect(watchTheme.stored == .pastel)

        // An hour behind, the watch goes back to Classic: it is still the later choice.
        watchTheme.choose(.classic, now: Date(timeIntervalSince1970: 46_400))
        watch.push()
        _ = settle((phone, phoneTransport), (watch, watchTransport))
        #expect(phoneTheme.stored == .classic)
        #expect(phoneTheme.register == watchTheme.register)
    }

    @Test("Seeded histories of choices on both devices always converge", arguments: 0..<20)
    func seededHistories(seed: Int) {
        var random = SeededRandom(seed: UInt64(seed + 1))
        let phoneTransport = FakeTransport(), watchTransport = FakeTransport()
        let themes = [ThemeStore(defaults: makeTestDefaults()), ThemeStore(defaults: makeTestDefaults())]
        let syncs = [
            WatchSync(store: WorkoutStore(defaults: makeTestDefaults()), theme: themes[0], transport: phoneTransport, sleep: WatchSyncTests.neverSends),
            WatchSync(store: WorkoutStore(defaults: makeTestDefaults()), theme: themes[1], transport: watchTransport, sleep: WatchSyncTests.neverSends),
        ]
        for _ in 0..<12 {
            let side = Int(random.next() % 2)
            let clock = Double(random.next() % 10_000)
            themes[side].choose(random.next() % 2 == 0 ? .classic : .pastel, now: Date(timeIntervalSince1970: clock))
            syncs[side].push()
            // Sometimes the other side hears about it before the next choice; sometimes not.
            if random.next() % 3 == 0 {
                _ = settle((syncs[0], phoneTransport), (syncs[1], watchTransport))
            }
        }
        syncs[0].push()
        syncs[1].push()
        _ = settle((syncs[0], phoneTransport), (syncs[1], watchTransport))
        #expect(themes[0].register == themes[1].register)
    }
}

/// A small deterministic generator, so a failing history can be replayed.
private struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
}

/// Theme's picker, on either device: a free user's Pastel opens the paywall, and a purchase
/// there applies it.
@Suite("Theme picker")
@MainActor
struct ThemePickerTests {
    let defaults = makeTestDefaults()

    @Test("A free user's Pastel opens the paywall and chooses nothing; Classic is chosen")
    func freeTaps() {
        let store = ThemeStore(defaults: defaults)
        #expect(store.tap(.pastel, isPro: false) == .paywall)
        #expect(store.register == ThemeStore.unchosen)
        #expect(store.tap(.classic, isPro: false) == .chosen)
    }

    @Test("A purchase from the Theme door applies Pastel")
    func purchaseApplies() {
        let store = ThemeStore(defaults: defaults)
        _ = store.tap(.pastel, isPro: false)
        store.paywallUnlocked()
        #expect(store.stored == .pastel)
        #expect(store.effective(isPro: true) == .pastel)
    }

    @Test("With Pro, either is chosen at once")
    func proTaps() {
        let store = ThemeStore(defaults: defaults)
        #expect(store.tap(.pastel, isPro: true) == .chosen)
        #expect(store.stored == .pastel)
        #expect(store.tap(.classic, isPro: true) == .chosen)
        #expect(store.stored == .classic)
    }

    @Test("The row names the theme that shows, and Pro where it is locked")
    func rows() {
        let free = ThemeRow(shown: .classic, isPro: false, platform: .watch)
        #expect(free.value == "Classic")
        #expect(free.footer == "Pastel is part of Intervally Pro.")
        #expect(ThemeRow(shown: .pastel, isPro: true, platform: .watch).footer == "Intervally on your iPhone follows.")
        #expect(ThemeRow(shown: .pastel, isPro: true, platform: .phone).footer == "Your Apple Watch follows, keeping its black screen.")
        #expect(ThemeRow(shown: .pastel, isPro: true, platform: .phone, hasWatch: false).footer == nil)
        #expect(ThemeRow(shown: .classic, isPro: false, platform: .phone).footer == "Pastel is part of Intervally Pro.")
        #expect(ThemeRow.title == "Theme")
    }

    @Test("Each option says what it is, in each device's words")
    func details() {
        #expect(AppTheme.allCases.map { $0.detail(on: .watch) } == ["Blue for work", "Pink for work"])
        #expect(AppTheme.allCases.map { $0.detail(on: .phone) } == ["Dark, with blue for work", "Light, with pink for work"])
    }

    @Test("The swatch shows every phase, so every colour of a theme shows")
    func swatch() {
        let kinds = Set(IntervalPlan(workout: AppTheme.swatch).phases.map(\.kind.rawValue))
        #expect(kinds == ["prepare", "warmup", "work", "rest", "cooldown"])
    }

    @Test("The Theme door's words fit beside the other doors', on both devices")
    func doorCopy() {
        #expect(PaywallContent.contextLine(for: .themes) == "Make Intervally yours with Pastel.")
        #expect(PaywallContent.contextLine(for: .themes, platform: .phone) == PaywallContent.contextLine(for: .themes))
        #expect(PaywallContent.contextLine(for: .themes).count <= PaywallContent.contextLine(for: .bookends).count)
        #expect(PaywallContent.features.contains { $0.title == "Pastel theme" && $0.systemImage == "paintpalette.fill" })
    }
}
