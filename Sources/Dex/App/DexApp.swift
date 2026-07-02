import AppKit
import SwiftUI

@main
struct DexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Dex", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(width: 560, height: model.savedModes.isEmpty ? 640 : 760)
                .onAppear {
                    appDelegate.configure(model: model)
                }
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(model)
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            if let image = BrandAssets.menuBarTemplateImage() {
                Image(nsImage: image)
            } else {
                Image(systemName: "rectangle.split.3x1")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
