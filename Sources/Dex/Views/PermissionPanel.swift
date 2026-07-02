import SwiftUI

struct PermissionPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsDetails = false

    private var allGranted: Bool {
        model.permissions.isAccessibilityTrusted
            && model.permissions.isInputMonitoringTrusted
            && model.permissions.isScreenRecordingTrusted
    }

    var body: some View {
        VStack(spacing: 10) {
            if allGranted && !showsDetails {
                compactRow
            } else {
                fullRows
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeInOut(duration: 0.15), value: allGranted)
        .animation(.easeInOut(duration: 0.15), value: showsDetails)
    }

    private var compactRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)

            Text("All permissions granted")
                .font(.headline)

            Spacer()

            Button("Details") {
                showsDetails = true
            }
            .buttonStyle(.borderless)
        }
    }

    private var fullRows: some View {
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

            HStack(spacing: 16) {
                Button {
                    model.refreshPermissions()
                } label: {
                    Label("Recheck Permissions", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                if allGranted {
                    Button("Hide Details") {
                        showsDetails = false
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.top, 2)
        }
        .id(model.permissionRefreshID)
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
