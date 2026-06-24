import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            Form {
                Toggle("Arrange all displays by default", isOn: $model.arrangeAllDisplays)
                Text("When disabled, double Option opens the Arrange Board only for the active display. When enabled, each display gets its own three-tile board.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            Form {
                Section("Activation Board App Shortcuts") {
                    ForEach(BoardAppShortcut.allCases) { shortcut in
                        HStack {
                            Text(shortcut.spec.label)
                            Spacer()
                            TextField(
                                shortcut.defaultKeySequence,
                                text: Binding(
                                    get: { model.shortcut(for: shortcut) },
                                    set: { model.setShortcut(shortcut, sequence: $0) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.center)
                        }
                    }
                }
                Text("Use one letter or number. Press it while the Arrange Board is open. Reserved: Q for close/quit. Use / for the palette.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .tabItem {
                Label("Shortcuts", systemImage: "keyboard")
            }
        }
        .frame(width: 520, height: 320)
    }
}
