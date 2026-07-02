import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.isOnboardingWizardActive {
                OnboardingView()
                    .environmentObject(model)
            } else {
                mainContent
            }
        }
        .onAppear {
            model.openMainWindowAction = { openWindow(id: "main") }
        }
    }

    private var mainContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                AppHeader()

                PermissionPanel()
                    .frame(maxWidth: 460)

                DexActionsPanel()
                    .environmentObject(model)

                if !model.savedModes.isEmpty {
                    ModeManagementPanel()
                        .environmentObject(model)
                }

                AppShortcutSettingsView()
                    .environmentObject(model)

                NewWindowLaunchSettingsView()
                    .environmentObject(model)

                PreferencesPanel()
                    .environmentObject(model)
            }
            .padding(28)
        }
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

private struct AppHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                if let logo = BrandAssets.logoImage() {
                    Image(nsImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                } else {
                    Image(systemName: "rectangle.split.3x1")
                        .font(.system(size: 32, weight: .semibold))
                        .frame(width: 58, height: 58)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Dex")
                        .font(.largeTitle.weight(.semibold))
                    Text("Arrange your current desktop into passive left, main center, and passive right.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                KeyCap("⌥")
                KeyCap("⌥")
                Text("Double-press Option anywhere to open the board.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 2)
        }
        .frame(maxWidth: 460, alignment: .leading)
        .padding(.bottom, 4)
    }
}

private struct KeyCap: View {
    let symbol: String

    init(_ symbol: String) {
        self.symbol = symbol
    }

    var body: some View {
        Text(symbol)
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .frame(width: 22, height: 20)
            .background(.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.25), lineWidth: 1)
            }
    }
}

private struct PreferencesPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Preferences", systemImage: "gearshape")
                .font(.headline.weight(.semibold))

            Toggle("Show shortcut legend on the board", isOn: $model.showsBoardLegend)
                .toggleStyle(.switch)

            Divider()
                .opacity(0.35)

            HStack(spacing: 10) {
                Button("Replay Onboarding") {
                    model.replayOnboarding()
                }
                Button("Replay Board Tour") {
                    Task { await model.replayTour() }
                }
            }

            Text("Onboarding runs the full welcome flow — granted permissions stay granted. The board tour jumps straight into the guided walkthrough.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 460, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ModeManagementPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Modes", systemImage: "square.grid.3x1.below.line.grid.1x2")
                    .font(.headline.weight(.semibold))
                Spacer()
                Text("\(model.savedModes.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.10), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.savedModes) { mode in
                    ModeManagementRow(mode: mode)
                        .environmentObject(model)
                    if mode.id != model.savedModes.last?.id {
                        Divider()
                            .opacity(0.35)
                            .padding(.leading, 106)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 460, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DexActionsPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Actions", systemImage: "slider.horizontal.3")
                .font(.headline.weight(.semibold))

            HStack(spacing: 12) {
                Button {
                    Task { await model.showArrangeBoard() }
                } label: {
                    Label("Arrange Board", systemImage: "rectangle.3.group")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await model.arrangeNow() }
                } label: {
                    Label("Arrange Now", systemImage: "sparkles")
                }

                Toggle("Arrange all displays", isOn: $model.arrangeAllDisplays)
                    .toggleStyle(.switch)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 460, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ModeManagementRow: View {
    @EnvironmentObject private var model: AppModel
    let mode: SavedMode
    @State private var draftName: String
    @State private var isEditing = false
    @FocusState private var isNameFocused: Bool

    init(mode: SavedMode) {
        self.mode = mode
        _draftName = State(initialValue: mode.name)
    }

    var body: some View {
        HStack(spacing: 10) {
            ContentModeIconCluster(windows: mode.windows)
                .frame(width: 94, height: 30, alignment: .leading)

            if isEditing {
                TextField("Mode name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .focused($isNameFocused)
                    .onSubmit(commitRename)
            } else {
                Text(mode.name)
                    .font(.headline)
                    .lineLimit(1)
            }

            Text(mode.shortcutLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.secondary.opacity(0.10), in: Capsule())

            if isEditing {
                Button(action: commitRename) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.borderless)
                .disabled(!canRename)
                .help("Save name")

                Button(action: cancelRename) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.borderless)
                .help("Cancel rename")
            } else {
                Button(action: beginRename) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Rename mode")
            }

            Button(role: .destructive) {
                model.deleteMode(id: mode.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Delete mode")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: mode.name) {
            draftName = mode.name
            isEditing = false
        }
    }

    private var canRename: Bool {
        let cleaned = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleaned.isEmpty && cleaned != mode.name
    }

    private func commitRename() {
        guard canRename else { return }
        model.renameMode(id: mode.id, to: draftName)
        isEditing = false
    }

    private func beginRename() {
        draftName = mode.name
        isEditing = true
        DispatchQueue.main.async {
            isNameFocused = true
        }
    }

    private func cancelRename() {
        draftName = mode.name
        isEditing = false
    }
}

private struct ContentModeIconCluster: View {
    let windows: [SavedModeWindow]

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(windows.prefix(4).enumerated()), id: \.element.id) { _, window in
                if let icon = AppIconCache.icon(for: window.bundleIdentifier) {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .padding(4)
                        .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.black.opacity(0.08), lineWidth: 1)
                        }
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}
