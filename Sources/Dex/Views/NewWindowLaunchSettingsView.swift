import SwiftUI

struct NewWindowLaunchSettingsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var isPickerPresented = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    if model.newWindowLaunchRules.isEmpty {
                        Text("No apps selected.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(model.newWindowLaunchRules) { rule in
                                row(for: rule)
                                if rule.id != model.newWindowLaunchRules.last?.id {
                                    Divider()
                                        .opacity(0.35)
                                        .padding(.leading, 34)
                                }
                            }
                        }
                        .padding(.top, 6)
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

                    Text("Dex tries to create a fresh app window when the app supports it, then falls back to normal launch or activation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } label: {
                HStack(spacing: 10) {
                    Label("Open New Windows", systemImage: "macwindow.badge.plus")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Text("\(model.newWindowLaunchRules.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.10), in: Capsule())
                }
            }
        }
        .frame(maxWidth: 460, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sheet(isPresented: $isPickerPresented) {
            NewWindowLaunchRulePicker { application in
                isPickerPresented = false
                model.addNewWindowLaunchRule(for: application)
            } onCancel: {
                isPickerPresented = false
            }
            .environmentObject(model)
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
        .padding(.vertical, 7)
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
