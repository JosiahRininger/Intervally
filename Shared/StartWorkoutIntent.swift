//
//  StartWorkoutIntent.swift
//  Intervally
//

import AppIntents
import Foundation

/// "Start an interval workout" from Siri, the Shortcuts app, or a Control Center button.
struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Interval Workout"
    static let description = IntentDescription(
        "Starts your selected interval workout on Intervally.",
        categoryName: "Workout"
    )

    /// watchOS runs this by launching the app; the run itself begins once the UI is up.
    static let openAppWhenRun = true

    @Parameter(title: "Preset")
    var preset: WorkoutPresetEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingStart.request(workoutID: preset?.id)
        return .result()
    }
}

/// Lets a Shortcut name a specific preset.
struct WorkoutPresetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Preset"
    static let defaultQuery = WorkoutPresetQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct WorkoutPresetQuery: EntityQuery {
    @MainActor
    private func allPresets() -> [WorkoutPresetEntity] {
        WorkoutStore().workouts.map { WorkoutPresetEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [WorkoutPresetEntity] {
        allPresets().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [WorkoutPresetEntity] {
        allPresets()
    }
}

struct IntervallyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "Start an interval workout with \(.applicationName)",
                "Start my \(.applicationName) workout",
                "Begin intervals with \(.applicationName)",
            ],
            shortTitle: "Start Workout",
            systemImageName: "timer"
        )
    }
}
