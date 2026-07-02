import SwiftUI

/// Grouped-form "Permissions" section for the main window. Collapses to a single
/// status row once everything is granted; expands to per-permission rows with
/// Allow buttons otherwise.
struct PermissionsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsDetails = false

    private var allGranted: Bool {
        model.permissions.isAccessibilityTrusted
            && model.permissions.isInputMonitoringTrusted
            && model.permissions.isScreenRecordingTrusted
    }

    var body: some View {
        Section {
            if allGranted && !showsDetails {
                HStack(spacing: 12) {
                    PermissionIconTile(systemImage: "checkmark", color: .green)
                    Text("All permissions granted")
                    Spacer()
                    Button("Details") {
                        showsDetails = true
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                Group {
                    PermissionRow(
                        title: "Accessibility",
                        detail: "Move, resize, and focus app windows.",
                        systemImage: "accessibility",
                        color: .blue,
                        granted: model.permissions.isAccessibilityTrusted,
                        action: model.requestAccessibility
                    )
                    PermissionRow(
                        title: "Input Monitoring",
                        detail: "Detect double Option, Option-scroll, Option-arrow cycling, and Control-drag. If Dex is not listed, press + and choose /Applications/Dex.app.",
                        systemImage: "keyboard",
                        color: .purple,
                        granted: model.permissions.isInputMonitoringTrusted,
                        action: model.requestInputMonitoring
                    )
                    PermissionRow(
                        title: "Screen Recording",
                        detail: "Show real window thumbnails. Return to Dex after granting; relaunch if macOS asks.",
                        systemImage: "rectangle.dashed.badge.record",
                        color: .orange,
                        granted: model.permissions.isScreenRecordingTrusted,
                        action: model.requestScreenRecording
                    )
                }
                .id(model.permissionRefreshID)
            }
        } header: {
            HStack {
                Text("Permissions")
                Spacer()
                if !allGranted || showsDetails {
                    Button("Recheck") {
                        model.refreshPermissions()
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)

                    if allGranted {
                        Button("Hide Details") {
                            showsDetails = false
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: allGranted)
        .animation(.easeInOut(duration: 0.15), value: showsDetails)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let color: Color
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PermissionIconTile(systemImage: systemImage, color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                    .accessibilityLabel("\(title) granted")
            } else {
                Button("Allow…") {
                    action()
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct PermissionIconTile: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.gradient)
            )
    }
}
