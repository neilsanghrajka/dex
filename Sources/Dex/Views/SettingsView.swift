import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TabView {
            Form {
                Section {
                    Toggle("Arrange all displays by default", isOn: $model.arrangeAllDisplays)
                    Text("When disabled, double Option opens the Arrange Board only for the active display. When enabled, each display gets its own three-tile board.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Onboarding") {
                    Toggle("Show shortcut legend on the board after onboarding", isOn: $model.showsBoardLegend)
                    Button("Replay onboarding") {
                        model.replayOnboarding()
                    }
                    Text("Replays the full welcome flow. Permissions you have already granted stay granted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            AppShortcutSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            NewWindowLaunchSettingsView()
                .tabItem {
                    Label("Windows", systemImage: "macwindow.badge.plus")
                }
        }
        .frame(width: 560, height: 460)
        .onAppear {
            // Settings is reachable even when the main window has been closed; capture the
            // scene's openWindow action so "Replay onboarding" can recreate that window.
            model.openMainWindowAction = { openWindow(id: "main") }
        }
    }
}
