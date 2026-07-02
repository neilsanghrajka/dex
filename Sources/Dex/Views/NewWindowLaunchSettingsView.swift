import SwiftUI

/// Grouped-form "Open New Windows" section. Embed inside a `Form`.
struct NewWindowLaunchSettingsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var isPickerPresented = false

    var body: some View {
        Section {
            if model.newWindowLaunchRules.isEmpty {
                Text("No apps selected.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.newWindowLaunchRules) { rule in
                    row(for: rule)
                }
            }

            HStack {
                Button {
                    isPickerPresented = true
                } label: {
                    Label("Add App…", systemImage: "plus")
                }
                Spacer()
                Button("Restore Defaults") {
                    model.resetNewWindowLaunchRulesToDefaults()
                }
                .buttonStyle(.link)
            }
            .sheet(isPresented: $isPickerPresented) {
                NewWindowLaunchRulePicker { application in
                    isPickerPresented = false
                    model.addNewWindowLaunchRule(for: application)
                } onCancel: {
                    isPickerPresented = false
                }
                .environmentObject(model)
            }
        } header: {
            Text("Open New Windows")
        } footer: {
            Text("Use this for apps like browsers and terminals where choosing the app should create a new work surface instead of jumping to an existing window on another display. Dex tries the app's New Window command first, then falls back to opening or activating the app.")
        }
    }

    @ViewBuilder
    private func row(for rule: NewWindowLaunchRule) -> some View {
        HStack(spacing: 12) {
            appIcon(for: rule)
                .frame(width: 22, height: 22)

            Text(rule.displayName)
                .lineLimit(1)

            Spacer()

            Button {
                model.removeNewWindowLaunchRule(id: rule.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove \(rule.displayName)")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func appIcon(for rule: NewWindowLaunchRule) -> some View {
        if let bundleID = rule.primaryBundleIdentifier,
           let icon = AppIconCache.icon(for: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.dashed")
                .foregroundStyle(.secondary)
        }
    }
}

private struct NewWindowLaunchRulePicker: View {
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
