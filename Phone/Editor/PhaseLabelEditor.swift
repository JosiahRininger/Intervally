//
//  PhaseLabelEditor.swift
//  IntervallyPhone
//

import SwiftUI

/// Renames one phase of a preset and gives it a figure: "Run" with a runner for Work. Pushed
/// inside the phase's picker sheet. A figure is saved when it is tapped; the name when it is
/// done (Done, leaving the field, or leaving the screen), so a rename is one edit to sync, as
/// the preset's own name is. The phase's own name and figure put it back.
struct PhaseLabelEditor: View {
    let kind: IntervalPhase.Kind
    let onChange: (PhaseLabel?) -> Void

    @State private var name: String
    @State private var symbol: PhaseSymbol
    /// What was last saved, so leaving the field or the screen without a change saves nothing.
    @State private var saved: PhaseLabel
    @FocusState private var nameFocused: Bool
    @Environment(\.palette) private var palette

    init(kind: IntervalPhase.Kind, label: PhaseLabel, onChange: @escaping (PhaseLabel?) -> Void) {
        self.kind = kind
        self.onChange = onChange
        // An empty field shows the phase's own name as its placeholder.
        _name = State(initialValue: label.name == kind.title ? "" : label.name)
        _symbol = State(initialValue: label.symbol)
        _saved = State(initialValue: label)
    }

    private var isCustom: Bool {
        PhaseLabel.cleaned(name) != nil || symbol != kind.defaultSymbol
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Name")
                    TextField(kind.title, text: $name)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .tileBackground()
                        .onChange(of: name) { _, new in
                            if new.count > PhaseLabel.maxNameLength {
                                name = String(new.prefix(PhaseLabel.maxNameLength))
                            }
                        }
                        .onSubmit(save)
                        .onChange(of: nameFocused) { _, focused in
                            if !focused { save() }
                        }
                    Text("What the run screen, the Lock Screen and the voice coach call it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Icon")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(PhaseLabelPicker.symbols(for: kind)) { option in
                            symbolButton(option)
                        }
                    }
                }

                if isCustom {
                    Button {
                        name = ""
                        symbol = kind.defaultSymbol
                        save()
                    } label: {
                        Label("Use “\(kind.title)”", systemImage: "arrow.uturn.backward")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .neutralGlass()
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .onDisappear(perform: save)
        .navigationTitle("Name & Icon")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func symbolButton(_ option: PhaseSymbol) -> some View {
        let selected = option == symbol
        return Button {
            symbol = option
            save()
        } label: {
            Image(systemName: option.systemName)
                .font(.title2)
                .foregroundStyle(selected ? palette.onTint : palette.ink(for: kind))
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(
                    selected ? palette.fill(for: kind) : palette.card,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.spokenName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func save() {
        let label = PhaseLabel(name: PhaseLabel.cleaned(name) ?? kind.title, symbol: symbol)
        guard label != saved else { return }
        saved = label
        onChange(label)
    }
}

/// The figures offered for a phase, apart from the view: its own first, then the rest.
enum PhaseLabelPicker {
    /// The built-in phases' figures other than this one's are left out: a sunrise on Work
    /// would only read as a warmup.
    static func symbols(for kind: IntervalPhase.Kind) -> [PhaseSymbol] {
        let builtIns: Set<PhaseSymbol> = [.bolt, .wind, .hourglass, .sunrise, .sunset]
        return [kind.defaultSymbol] + PhaseSymbol.allCases.filter { !builtIns.contains($0) }
    }
}

#Preview {
    NavigationStack {
        PhaseLabelEditor(kind: .work, label: PhaseLabel(name: "Run", symbol: .run)) { _ in }
    }
}
