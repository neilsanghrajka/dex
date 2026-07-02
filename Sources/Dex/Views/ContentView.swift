import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var selectedSection: DexHomeSection? = .general

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
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(DexHomeSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            detailContent
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

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection ?? .general {
        case .general:
            GeneralPane()
                .environmentObject(model)
        case .shortcuts:
            ShortcutsPane()
                .environmentObject(model)
        case .preferences:
            PreferencesPane()
                .environmentObject(model)
        }
    }
}

private enum DexHomeSection: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case preferences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .preferences: "Preferences"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "rectangle.3.group"
        case .shortcuts: "keyboard"
        case .preferences: "gearshape"
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            heroSection

            PermissionsSection()

            boardSection

            if !model.savedModes.isEmpty {
                modesSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }

    private var heroSection: some View {
        Section {
            VStack(spacing: 8) {
                if let logo = BrandAssets.logoImage() {
                    Image(nsImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    Image(systemName: "rectangle.split.3x1")
                        .font(.system(size: 36, weight: .semibold))
                        .frame(width: 64, height: 64)
                }

                Text("Dex")
                    .font(.title.weight(.semibold))

                Text("Arrange your current desktop into passive left, main center, and passive right.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    KeyCap("⌥")
                    KeyCap("⌥")
                    Text("Double-press Option anywhere to open the board.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .listRowBackground(Color.clear)
    }

    private var boardSection: some View {
        Section {
            LabeledContent("Arrange the current desktop") {
                HStack(spacing: 8) {
                    Button("Arrange Now") {
                        Task { await model.arrangeNow() }
                    }
                    Button("Open Board") {
                        Task { await model.showArrangeBoard() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Toggle("Arrange all displays", isOn: $model.arrangeAllDisplays)
                .toggleStyle(.switch)
        } header: {
            Text("Board")
        } footer: {
            Text("When off, double Option opens the board for the active display only. When on, each display gets its own three-column board.")
        }
    }

    private var modesSection: some View {
        Section {
            ForEach(model.savedModes) { mode in
                ModeManagementRow(mode: mode)
                    .environmentObject(model)
            }
        } header: {
            Text("Modes")
        } footer: {
            Text("Saved modes reopen a remembered set of apps and place them back into the three board columns. Press Option and the mode's number to launch it from anywhere.")
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            AppShortcutSettingsView()
                .environmentObject(model)

            NewWindowLaunchSettingsView()
                .environmentObject(model)
        }
        .formStyle(.grouped)
        .navigationTitle("Shortcuts")
    }
}

// MARK: - Preferences

private struct PreferencesPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Show shortcut legend on the board", isOn: $model.showsBoardLegend)
                    .toggleStyle(.switch)
            } header: {
                Text("Guidance")
            } footer: {
                Text("Shows a one-line key legend along the bottom of the board for your first few sessions.")
            }

            Section {
                LabeledContent("Welcome flow") {
                    Button("Replay Onboarding") {
                        model.replayOnboarding()
                    }
                }
                LabeledContent("Guided board walkthrough") {
                    Button("Replay Board Tour") {
                        Task { await model.replayTour() }
                    }
                }
            } header: {
                Text("Onboarding")
            } footer: {
                Text("Onboarding runs the full welcome flow — granted permissions stay granted. The board tour jumps straight into the guided walkthrough.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Preferences")
    }
}

// MARK: - Shared pieces

struct KeyCap: View {
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
                    .font(.body.weight(.medium))
                    .focused($isNameFocused)
                    .onSubmit(commitRename)
            } else {
                Text(mode.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
            }

            Text(mode.shortcutLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.secondary.opacity(0.10), in: Capsule())

            Spacer()

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
        .padding(.vertical, 2)
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
