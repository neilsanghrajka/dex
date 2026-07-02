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
                .frame(minWidth: 640, idealWidth: 700, maxWidth: .infinity)
                .frame(minHeight: 560, idealHeight: 700, maxHeight: .infinity)
                .onAppear {
                    appDelegate.configure(model: model)
                }
        }
        .windowResizability(.contentMinSize)

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
