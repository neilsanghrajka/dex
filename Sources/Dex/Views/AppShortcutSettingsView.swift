import AppKit
import SwiftUI

/// Grouped-form "Launch Keys" section: a table of app-launch bindings with a
/// press-to-record key badge, remove buttons, and an "Add App…" picker.
/// Reads/writes the live binding list on `AppModel`. Embed inside a `Form`.
struct AppShortcutSettingsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var recordingID: UUID?
    @State private var feedback: [UUID: BindingFeedback] = [:]
    @State private var isPickerPresented = false

    var body: some View {
        Section {
            ForEach(model.appShortcutBindings) { binding in
                row(for: binding)
            }

            HStack {
                Button {
                    isPickerPresented = true
                } label: {
                    Label("Add App…", systemImage: "plus")
                }
                Spacer()
                Button("Restore Defaults") {
                    recordingID = nil
                    feedback = [:]
                    model.resetAppShortcutBindingsToDefaults()
                }
                .buttonStyle(.link)
            }
            .sheet(isPresented: $isPickerPresented) {
                AppShortcutPicker { application in
                    isPickerPresented = false
                    model.addAppShortcutBinding(for: application)
                } onCancel: {
                    isPickerPresented = false
                }
                .environmentObject(model)
            }
        } header: {
            Text("Launch Keys")
        } footer: {
            Text("Press a key while the board is open to launch that app in the focused column. Click a key badge and press a new letter or number to rebind. Reserved keys stay fixed: Q closes or quits, and / opens search.")
        }
    }

    @ViewBuilder
    private func row(for binding: AppShortcutBinding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                appIcon(for: binding)
                    .frame(width: 22, height: 22)

                Text(binding.displayName)
                    .lineLimit(1)

                Spacer()

                keyBadge(for: binding)

                Button {
                    if recordingID == binding.id { recordingID = nil }
                    feedback[binding.id] = nil
                    model.removeAppShortcutBinding(id: binding.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove \(binding.displayName)")
            }

            if let feedback = feedback[binding.id] {
                feedbackView(feedback, for: binding)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func appIcon(for binding: AppShortcutBinding) -> some View {
        if let bundleID = binding.primaryBundleIdentifier,
           let icon = AppIconCache.icon(for: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.dashed")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func keyBadge(for binding: AppShortcutBinding) -> some View {
        let isRecording = recordingID == binding.id
        Button {
            if isRecording {
                recordingID = nil
            } else {
                feedback[binding.id] = nil
                recordingID = binding.id
            }
        } label: {
            Text(badgeTitle(for: binding, isRecording: isRecording))
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .frame(minWidth: 74)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isRecording ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isRecording ? Color.accentColor : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .overlay {
            if isRecording {
                KeyRecorderCapture(
                    onKey: { handleRecordedKey($0, for: binding.id) },
                    onCancel: { recordingID = nil }
                )
                .frame(width: 1, height: 1)
                .opacity(0.001)
            }
        }
    }

    @ViewBuilder
    private func feedbackView(_ feedback: BindingFeedback, for binding: AppShortcutBinding) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(feedback.message)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let pendingKey = feedback.replaceableKey {
                Button("Replace") {
                    model.replaceAppShortcutKey(pendingKey, for: binding.id)
                    self.feedback[binding.id] = nil
                    recordingID = nil
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    private func badgeTitle(for binding: AppShortcutBinding, isRecording: Bool) -> String {
        if isRecording { return "Press key" }
        return binding.key.isEmpty ? "Set key" : binding.keyLabel
    }

    private func handleRecordedKey(_ character: String, for id: UUID) {
        let result = model.setAppShortcutKey(character, for: id)
        switch result {
        case .valid:
            feedback[id] = nil
            recordingID = nil
        case .notAKey:
            // Ignore modifier-only or non-alphanumeric presses; keep recording.
            break
        case .reserved(let label):
            feedback[id] = BindingFeedback(message: "\(label) is reserved and can't be used.")
            recordingID = nil
        case .conflict(_, let appName, let key):
            feedback[id] = BindingFeedback(
                message: "\(key.uppercased()) is used by \(appName).",
                replaceableKey: key
            )
            recordingID = nil
        }
    }
}

private struct BindingFeedback: Equatable {
    let message: String
    var replaceableKey: String?
}

/// A picker sheet listing running + installed apps to add as a new binding.
private struct AppShortcutPicker: View {
    @EnvironmentObject private var model: AppModel

    let onSelect: (InstalledApplication) -> Void
    let onCancel: () -> Void

    @State private var applications: [InstalledApplication] = []
    @State private var query = ""
    @State private var isLoading = true

    private var filtered: [InstalledApplication] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return applications }
        return applications.filter { app in
            app.name.localizedCaseInsensitiveContains(trimmed) ||
                (app.bundleIdentifier?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add App")
                    .font(.headline)
                Spacer()
                Button("Done", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            TextField("Search apps", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { app in
                    Button {
                        onSelect(app)
                    } label: {
                        HStack(spacing: 10) {
                            if let bundleID = app.bundleIdentifier,
                               let icon = AppIconCache.icon(for: bundleID) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "app.dashed")
                                    .frame(width: 20, height: 20)
                            }
                            Text(app.name)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 420, height: 460)
        .task {
            applications = await model.availableApplicationsForBinding()
            isLoading = false
        }
    }
}

/// Captures a single keypress for the press-to-record key badge. Modifier-combos and
/// Escape are handled here (Escape cancels); everything else is forwarded as its
/// `charactersIgnoringModifiers` string for validation.
private struct KeyRecorderCapture: NSViewRepresentable {
    let onKey: (String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyRecorderView {
        let view = KeyRecorderView()
        view.onKey = onKey
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: KeyRecorderView, context: Context) {
        nsView.onKey = onKey
        nsView.onCancel = onCancel
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class KeyRecorderView: NSView {
    var onKey: ((String) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Never let Option/Command/Control combos become app keys.
        if flags.contains(.option) || flags.contains(.command) || flags.contains(.control) {
            return
        }
        onKey?(event.charactersIgnoringModifiers ?? "")
    }
}
