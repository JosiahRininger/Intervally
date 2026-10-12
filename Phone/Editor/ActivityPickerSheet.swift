//
//  ActivityPickerSheet.swift
//  IntervallyPhone
//

import SwiftUI

/// What Health records a preset as, picked from Apple's own kinds of workout in groups, with
/// a search for the one you have in mind. A tap picks it and closes the sheet.
struct ActivityPickerSheet: View {
    let current: WorkoutActivity
    let onPick: (WorkoutActivity) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(ActivityPicker.groups(matching: search)) { group in
                    Section(group.title) {
                        ForEach(group.activities) { activity in
                            row(activity)
                        }
                    }
                }
            }
            .overlay {
                if ActivityPicker.groups(matching: search).isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .appCanvas()
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Apple Health and Fitness file the workout under it. On Apple Watch it also sets how calories are estimated.")
                    .font(.footnote)
                    // .primary: on the bar's material, with rows passing under it, .secondary
                    // fell short of 4.5:1 (accessibility audit).
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }

    private func row(_ activity: WorkoutActivity) -> some View {
        Button {
            onPick(activity)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: activity.symbolName)
                    .font(.title3)
                    .foregroundStyle(palette.workInk)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                Text(activity.title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if activity == current {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.workInk)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(activity == current ? .isSelected : [])
    }
}

/// The picker's content, apart from the view.
enum ActivityPicker {
    struct Group: Identifiable, Equatable {
        let id: WorkoutActivity.Group
        let activities: [WorkoutActivity]
        var title: String { id.rawValue }
    }

    /// Each group with its activities that match `search`; a group with none is left out.
    static func groups(matching search: String) -> [Group] {
        WorkoutActivity.Group.allCases.compactMap { group in
            let matching = group.activities.filter { $0.matches(search) }
            return matching.isEmpty ? nil : Group(id: group, activities: matching)
        }
    }
}

#Preview {
    ActivityPickerSheet(current: .hiit) { _ in }
}
