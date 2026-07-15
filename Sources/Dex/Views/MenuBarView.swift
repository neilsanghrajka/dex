import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Arrange Board") {
            Task { await model.showArrangeBoard() }
        }

        Button("Arrange Now") {
            Task { await model.arrangeNow() }
        }

        Divider()

        Toggle("Arrange All Displays", isOn: $model.arrangeAllDisplays)

        Picker("Board Presentation", selection: $model.boardPresentationMode) {
            ForEach(BoardPresentationMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }

        Button("Refresh Permissions") {
            model.refreshPermissions()
        }

        Divider()

        Button("Open Dex") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
