import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func configure(model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model?.refreshPermissions()
    }
}
