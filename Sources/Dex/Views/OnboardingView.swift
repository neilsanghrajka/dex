import AppKit
import SwiftUI

/// First-run wizard shown in the main window (Acts 1 & 2 of onboarding). The in-board
/// guided tour (Act 3) lives in `ArrangeBoardView`.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            switch model.onboardingPhase {
            case .welcome:
                WelcomeStep()
            case .permissions:
                PermissionsStep()
            case .summon:
                SummonStep()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(36)
        .animation(.easeInOut(duration: 0.25), value: model.onboardingPhase)
        .overlay(alignment: .bottom) {
            if let hudText = model.hudText {
                Text(hudText)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.72), in: Capsule())
                    .padding(.bottom, 20)
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }
}

// MARK: - Act 1, screen 1: Welcome

private struct WelcomeStep: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 26) {
            Spacer()

            ThreeColumnGlyph()
                .frame(width: 240, height: 132)

            VStack(spacing: 10) {
                Text("Welcome to Dex")
                    .font(.largeTitle.weight(.semibold))
                Text("Arrange your windows into three columns, from your keyboard.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                model.beginOnboardingPermissions()
            } label: {
                Text("Get started")
                    .font(.headline)
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: 460)
    }
}

/// A simple three-column visual: a tall main center flanked by two passive columns.
private struct ThreeColumnGlyph: View {
    var body: some View {
        HStack(spacing: 12) {
            column(height: 92)
            column(height: 132)
            column(height: 92)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func column(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.accentColor.opacity(0.18))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
            }
            .frame(width: 64, height: height)
    }
}

// MARK: - Act 1, screen 2: Permissions

private struct PermissionsStep: View {
    @EnvironmentObject private var model: AppModel
    @State private var didSkipScreenRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Grant a couple of permissions")
                    .font(.title.weight(.semibold))
                Text("Dex needs these to move your windows and to hear the double-Option summon. Rows update on their own once you grant them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                OnboardingPermissionRow(
                    title: "Accessibility",
                    detail: "Required. Dex moves and arranges your windows.",
                    granted: model.permissions.isAccessibilityTrusted,
                    action: model.requestAccessibility
                )
                OnboardingPermissionRow(
                    title: "Input Monitoring",
                    detail: "Required. Powers the double-Option summon.",
                    granted: model.permissions.isInputMonitoringTrusted,
                    action: model.requestInputMonitoring
                )
                OnboardingPermissionRow(
                    title: "Screen Recording",
                    detail: "Optional. Live window previews.",
                    granted: model.permissions.isScreenRecordingTrusted,
                    isOptional: true,
                    isSkipped: didSkipScreenRecording,
                    action: model.requestScreenRecording,
                    onSkip: { didSkipScreenRecording = true }
                )
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .id(model.permissionRefreshID)

            Text("The two required rows must turn green to continue.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 480)
    }
}

private struct OnboardingPermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    var isOptional = false
    var isSkipped = false
    let action: () -> Void
    var onSkip: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : (isOptional ? "circle" : "exclamationmark.circle"))
                .foregroundStyle(granted ? .green : (isOptional ? .secondary : .orange))
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !granted, isOptional, !isSkipped, let onSkip {
                Button("Skip for now", action: onSkip)
                    .buttonStyle(.borderless)
                    .font(.caption)
            }

            Button(granted ? "Granted" : "Allow") {
                action()
            }
            .disabled(granted)
        }
    }
}

// MARK: - Act 2: The summon gate

private struct SummonStep: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            OptionKeyGlyph()
                .frame(width: 132, height: 96)

            VStack(spacing: 10) {
                Text("Press ⌥ Option twice")
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Tap the Option key twice, quickly, to summon the Arrange Board.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Not working? Open the board manually") {
                Task { await model.showArrangeBoard() }
            }
            .buttonStyle(.link)
            .font(.callout)

            Spacer()
        }
        .frame(maxWidth: 460)
    }
}

private struct OptionKeyGlyph: View {
    var body: some View {
        HStack(spacing: 14) {
            keycap
            keycap
        }
    }

    private var keycap: some View {
        VStack(spacing: 2) {
            Image(systemName: "option")
                .font(.system(size: 28, weight: .semibold))
            Text("option")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 58, height: 58)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.secondary.opacity(0.35), lineWidth: 1)
        }
    }
}
