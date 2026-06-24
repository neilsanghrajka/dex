import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

final class PermissionService {
    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    var isInputMonitoringTrusted: Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess()
        }
        return true
    }

    var isScreenRecordingTrusted: Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        openPrivacyPane(.accessibility)
    }

    func requestInputMonitoring() {
        if #available(macOS 10.15, *) {
            CGRequestListenEventAccess()
        }
        openPrivacyPane(.inputMonitoring)
    }

    func requestScreenRecording() {
        if #available(macOS 10.15, *) {
            CGRequestScreenCaptureAccess()
        }
        openPrivacyPane(.screenRecording)
    }

    private func openPrivacyPane(_ pane: PrivacyPane) {
        guard let url = URL(string: pane.urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

private enum PrivacyPane {
    case accessibility
    case inputMonitoring
    case screenRecording

    var urlString: String {
        switch self {
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .screenRecording:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
    }
}
