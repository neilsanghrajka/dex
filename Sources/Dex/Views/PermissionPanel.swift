import SwiftUI

struct PermissionPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            PermissionRow(
                title: "Accessibility",
                detail: "Move, resize, and focus app windows.",
                granted: model.permissions.isAccessibilityTrusted,
                action: model.requestAccessibility
            )
            PermissionRow(
                title: "Input Monitoring",
                detail: "Detect double Option, Option-scroll, Option-arrow cycling, and Control-drag. If Dex is not listed, press + and choose /Applications/Dex.app.",
                granted: model.permissions.isInputMonitoringTrusted,
                action: model.requestInputMonitoring
            )
            PermissionRow(
                title: "Screen Recording",
                detail: "Show real window thumbnails. Return to Dex after granting; relaunch if macOS asks.",
                granted: model.permissions.isScreenRecordingTrusted,
                action: model.requestScreenRecording
            )

            Button {
                model.refreshPermissions()
            } label: {
                Label("Recheck Permissions", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
        .id(model.permissionRefreshID)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(granted ? "Granted" : "Allow") {
                action()
            }
            .disabled(granted)
        }
    }
}
