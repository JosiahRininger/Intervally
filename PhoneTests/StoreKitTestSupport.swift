//
//  StoreKitTestSupport.swift
//  IntervallyPhoneTests
//

import Foundation

/// Holds an async call open until the test releases it, so a test can act while a read is
/// still in flight. The iPhone twin of the watch suite's.
@MainActor
final class Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}
