//
//  EditorTile.swift
//  IntervallyPhone
//

import SwiftUI

/// What one editor tile shows for a preset, worked out apart from the view.
struct EditorTileContent: Equatable {
    let field: PresetField
    /// A free user's warmup or cooldown: "PRO" and a lock where the value would be. The
    /// stored value is kept, and shows again the moment Pro unlocks.
    let isLocked: Bool
    /// "45s", "8", "Off"; nil while locked.
    let value: String?
    let accessibilityValue: String
    let accessibilityHint: String
    /// The up-and-down chevron that says a tap changes the value. Not on a locked tile,
    /// whose tap opens Intervally Pro rather than a picker.
    var showsPickerHint: Bool { !isLocked }

    init(field: PresetField, workout: IntervalWorkout, isPro: Bool) {
        let stored = workout[keyPath: field.keyPath]
        self.field = field
        self.isLocked = field.isPro && !isPro
        self.value = isLocked ? nil : field.tileText(stored)
        self.accessibilityValue = isLocked ? "Locked" : field.spoken(stored)
        self.accessibilityHint = isLocked ? "Opens Intervally Pro" : "Opens a picker"
    }
}

/// One number of the preset, in its phase's colour, with the phase's glyph. A tap opens its
/// picker, or the paywall for a locked bookend.
struct EditorTile: View {
    let content: EditorTileContent
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        let field = content.field

        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Label {
                        Text(field.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: field.symbolName)
                            .foregroundStyle(field.tint(in: palette))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                    Spacer(minLength: 0)

                    if content.showsPickerHint {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }

                Spacer(minLength: 0)

                if let value = content.value {
                    Text(value)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(field.tint(in: palette))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    ProBadge()
                        .font(.headline)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .tileBackground()
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        // The button is the one element: wrapping it in another left the locked tiles
        // exposed twice to VoiceOver.
        .accessibilityLabel(field.title)
        .accessibilityValue(content.accessibilityValue)
        .accessibilityHint(content.accessibilityHint)
    }
}

/// A medium-detent wheel over exactly the values the watch's crown offers for the field.
/// Every turn is saved, as a crown turn is on the watch; the store stamps only real changes.
struct ValuePickerSheet: View {
    let field: PresetField
    let onPick: (Int) -> Void

    @State private var selection: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    /// Starts on the table value nearest `value`. A stored value that isn't on the table is
    /// only shown at its neighbour, never rewritten, until the wheel is turned.
    init(field: PresetField, value: Int, onPick: @escaping (Int) -> Void) {
        self.field = field
        self.onPick = onPick
        _selection = State(initialValue: field.nearestValue(to: value))
    }

    var body: some View {
        NavigationStack {
            Picker(field.title, selection: $selection) {
                ForEach(field.values, id: \.self) { value in
                    Text(Self.rowText(field, value))
                        .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(field.tint(in: palette))
                        .accessibilityLabel(field.spoken(value))
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            // A wheel's rows keep their height whatever the text size.
            .dynamicTypeSize(...Self.largestRowSize)
            .padding(.horizontal)
            .navigationTitle(field.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(palette.canvas)
        .onChange(of: selection) { _, new in onPick(new) }
    }

    /// The largest text a wheel row takes. Rows don't grow, so at the accessibility sizes
    /// each value overlapped the next on an iPhone SE. The sheet's title and the editor's
    /// tiles still follow the user's size.
    static let largestRowSize = DynamicTypeSize.xxxLarge

    /// A wheel row: the tile's form, with rounds spelled out ("8 rounds") since a bare
    /// number in a wheel says nothing on its own.
    static func rowText(_ field: PresetField, _ value: Int) -> String {
        field == .rounds ? DurationFormat.rounds(value) : field.tileText(value)
    }
}

#Preview {
    let workout = WorkoutStore.starterWorkouts[0]
    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
        GridRow {
            EditorTile(content: EditorTileContent(field: .work, workout: workout, isPro: false)) {}
            EditorTile(content: EditorTileContent(field: .rest, workout: workout, isPro: false)) {}
        }
        GridRow {
            EditorTile(content: EditorTileContent(field: .warmup, workout: workout, isPro: false)) {}
            EditorTile(content: EditorTileContent(field: .cooldown, workout: workout, isPro: true)) {}
        }
    }
    .padding()
    .background(.black)
}
