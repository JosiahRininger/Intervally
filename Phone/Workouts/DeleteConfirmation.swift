//
//  DeleteConfirmation.swift
//  IntervallyPhone
//

import SwiftUI

extension View {
    /// The question before a preset is deleted, the same from the library's swipe and menu as
    /// from the editor. Setting `pending` asks it; `delete` runs only on Delete, and Cancel
    /// leaves the preset as it was.
    ///
    /// Attached once, to the list or the screen. On a `Section`, or on each row, there would
    /// be one for every row on the same binding, racing each other to show it.
    func confirmsDelete(of pending: Binding<IntervalWorkout?>, delete: @escaping (IntervalWorkout) -> Void) -> some View {
        modifier(DeleteConfirmation(pending: pending, delete: delete))
    }
}

/// An alert: iOS 26's confirmation dialog shows no Cancel.
private struct DeleteConfirmation: ViewModifier {
    @Binding var pending: IntervalWorkout?
    let delete: (IntervalWorkout) -> Void

    @Environment(WatchSync.self) private var sync

    func body(content: Content) -> some View {
        content.alert(
            pending.map { PresetDeletion.title(for: $0.name) } ?? "",
            isPresented: Binding { pending != nil } set: { if !$0 { pending = nil } },
            presenting: pending
        ) { workout in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { delete(workout) }
        } message: { _ in
            Text(WorkoutsContent.deleteMessage(on: .current, peer: sync.peer))
        }
    }
}
