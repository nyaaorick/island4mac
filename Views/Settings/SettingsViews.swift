//
//  SettingsViews.swift
//  MacDynamicIsland
//
//  Shared Settings Components
//

import SwiftUI

// MARK: - Pane Layout
// Every pane is a SettingsForm of titled sections, like System Settings. Rows keep the form's own fonts;
// the only other text style is SettingsNote, for an explanation under a row or at the foot of a section

/// A settings pane: a grouped form, with the form's own margins
struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
    }
}

/// Explanation under a setting or at the foot of a section. The one secondary text size in Settings
struct SettingsNote: View {
    let text: String
    var color: Color = .secondary

    init(_ text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Rows

struct ToggleSettingsRow: View {
    let key: SettingsKey<Bool>
    let title: String
    let help: String

    @State private var isOn: Bool

    init(key: SettingsKey<Bool>, title: String, help: String) {
        self.key = key
        self.title = title
        self.help = help
        _isOn = State(initialValue: SettingsDefaults.shared.get(key))
    }

    var body: some View {
        Toggle(title, isOn: $isOn)
            .help(help)
            .onChange(of: isOn) { _, newValue in
                SettingsDefaults.shared.set(key, value: newValue)
            }
    }
}

/// A slider with its label on the left and its current value to its right
struct SliderSettingsRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    /// The current value as shown next to the slider
    let valueText: String
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                slider
                    .frame(width: 180)
                Text(valueText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private var slider: some View {
        if let step {
            Slider(value: $value, in: range, step: step, onEditingChanged: onEditingChanged)
        } else {
            Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
        }
    }
}

/// Something that is either set up or not (a permission, an agent's hooks): its status, what it means,
/// and the control that changes it
struct StatusSettingsRow<Accessory: View>: View {
    let title: String
    let isOK: Bool
    let note: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isOK ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isOK ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                SettingsNote(note)
            }
            Spacer()
            accessory
        }
    }
}
