import SwiftUI

struct ShelfSettingsView: View {
    var body: some View {
        SettingsForm {
            Section(header: Text("Smart shelf")) {
                ToggleSettingsRow(
                    key: SettingsDefaults.boringShelf,
                    title: "Enable temporary shelf",
                    help: "Allow dragging files onto the island to hold them temporarily"
                )

                ToggleSettingsRow(
                    key: SettingsDefaults.expandedDragDetection,
                    title: "Enlarge drop area",
                    help: "Make dropping files easier by enlarging the sensing area"
                )
            }
        }
    }
}
