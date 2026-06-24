import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button("Arrange Board") {
            Task { await model.showArrangeBoard() }
        }

        Button("Arrange Now") {
            Task { await model.arrangeNow() }
        }

        Divider()

        Toggle("Arrange All Displays", isOn: $model.arrangeAllDisplays)

        Button("Refresh Permissions") {
            model.refreshPermissions()
        }

        Divider()

        Button("Open Dex") {
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
