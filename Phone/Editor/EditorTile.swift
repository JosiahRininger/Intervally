//
//  EditorTile.swift
//  IntervallyPhone
//

import SwiftUI

/// What one editor tile shows for a preset, worked out apart from the view.
struct EditorTileContent: Equatable {
    let field: PresetField
    /// What the preset calls the phase, and its figure: the field's own unless renamed.
    let title: String
    let symbolName: String
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
        let label = field.kind.map(workout.label(for:))
        self.title = label?.name ?? field.title
        self.symbolName = label?.symbol.systemName ?? field.symbolName
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
                        Text(content.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: content.symbolName)
                            .foregroundStyle(field.tint(in: palette))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                    Spacer(minLength: 0)

                    if content.showsPickerHint {
                        // .secondary, not .tertiary: the only sign the tile opens a picker, and
                        // .tertiary fell short of 3:1 on the tile (accessibility audit).
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
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
        .accessibilityLabel(content.title)
        .accessibilityValue(content.accessibilityValue)
        .accessibilityHint(content.accessibilityHint)
    }
}

/// What a duration's two wheels can be set to: whole minutes up to the field's top, and
/// seconds by fives. Every length is reachable to the five seconds, where a single wheel of
/// the watch's crown table coarsened to 15 and 30 seconds past two minutes.
enum DurationWheels {
    static let secondSteps = Array(stride(from: 0, through: 55, by: 5))

    static func minutes(for field: PresetField) -> [Int] {
        Array(0...(field.range.upperBound / 60))
    }

    /// A stored value as the wheels show it: its minutes, and its seconds down to the five
    /// below. A value off the five-second grid, from an older build, is only shown there.
    static func split(_ value: Int) -> (minutes: Int, seconds: Int) {
        (value / 60, (value % 60) / 5 * 5)
    }

    /// What the wheels say, kept to the field's range: 0:00 on Work is its shortest, and
    /// past the top minute the seconds can't add more.
    static func value(minutes: Int, seconds: Int, field: PresetField) -> Int {
        field.range.clamping(minutes * 60 + seconds)
    }
}

/// A medium-detent sheet that sets one field. Rounds turn one wheel of counts; a duration
/// turns two, minutes and seconds. Every turn is saved, as a crown turn is on the watch; the
/// store stamps only real changes.
struct ValuePickerSheet: View {
    let field: PresetField
    let onPick: (Int) -> Void
    /// The phase's label, for a phase field: its name titles the sheet, and Name & Icon edits
    /// it. Nil for rounds.
    var label: PhaseLabel? = nil
    var onLabel: (PhaseLabel?) -> Void = { _ in }

    @State private var count: Int
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var detent = PresentationDetent.medium
    @State private var editingLabel = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    /// A stored value that isn't on the wheels is only shown at its neighbour, never
    /// rewritten, until a wheel is turned.
    init(
        field: PresetField, value: Int, label: PhaseLabel? = nil,
        onLabel: @escaping (PhaseLabel?) -> Void = { _ in }, onPick: @escaping (Int) -> Void
    ) {
        self.field = field
        self.onPick = onPick
        self.label = label
        self.onLabel = onLabel
        _count = State(initialValue: field.nearestValue(to: value))
        let split = DurationWheels.split(value)
        _minutes = State(initialValue: split.minutes)
        _seconds = State(initialValue: split.seconds)
    }

    var body: some View {
        NavigationStack {
            Group {
                if field == .rounds {
                    Picker(field.title, selection: $count) {
                        ForEach(field.values, id: \.self) { value in
                            row(Self.rowText(field, value), spoken: field.spoken(value)).tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                } else {
                    HStack(spacing: 0) {
                        Picker("Minutes", selection: $minutes) {
                            ForEach(DurationWheels.minutes(for: field), id: \.self) { value in
                                row("\(value) min", spoken: "\(value) minutes").tag(value)
                            }
                        }
                        .pickerStyle(.wheel)
                        .labelsHidden()
                        Picker("Seconds", selection: $seconds) {
                            ForEach(DurationWheels.secondSteps, id: \.self) { value in
                                row(String(format: "%02d sec", value), spoken: "\(value) seconds").tag(value)
                            }
                        }
                        .pickerStyle(.wheel)
                        .labelsHidden()
                    }
                }
            }
            // A wheel's rows keep their height whatever the text size.
            .dynamicTypeSize(...Self.largestRowSize)
            .padding(.horizontal)
            .navigationTitle(label?.name ?? field.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let label, let kind = field.kind {
                    // The title itself, with a pencil: the phase's name is what changes.
                    ToolbarItem(placement: .principal) {
                        Button {
                            editingLabel = true
                            detent = .large
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: label.symbol.systemName)
                                    .foregroundStyle(field.tint(in: palette))
                                Text(label.name)
                                    .foregroundStyle(.primary)
                                Image(systemName: "pencil")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.headline)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(palette.card, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(label.name), rename")
                        .accessibilityHint("Changes what \(kind.title) is called and its icon")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() }
                }
            }
            .navigationDestination(isPresented: $editingLabel) {
                if let label, let kind = field.kind {
                    PhaseLabelEditor(kind: kind, label: label, onChange: onLabel)
                        .appCanvas()
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationBackground(palette.canvas)
        .onChange(of: count) { _, new in onPick(new) }
        .onChange(of: minutes) { _, _ in pickDuration() }
        .onChange(of: seconds) { _, _ in pickDuration() }
    }

    private func row(_ text: String, spoken: String) -> some View {
        Text(text)
            .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
            .foregroundStyle(field.tint(in: palette))
            .accessibilityLabel(spoken)
    }

    /// Saves what the wheels say, and settles them on it where the range moved it: the top
    /// minute takes no seconds, and Work's shortest is five seconds.
    private func pickDuration() {
        let value = DurationWheels.value(minutes: minutes, seconds: seconds, field: field)
        onPick(value)
        let shown = DurationWheels.split(value)
        if shown.minutes != minutes { minutes = shown.minutes }
        if shown.seconds != seconds { seconds = shown.seconds }
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
