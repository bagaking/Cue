import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var page: Page = .general

    private enum Page: String, CaseIterable, Identifiable {
        case general = "General"
        case capture = "Capture"
        case workspaces = "Workspaces"
        case privacy = "Privacy"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .capture: "text.cursor"
            case .workspaces: "tray.2"
            case .privacy: "hand.raised"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(.tint)
                    Text("Cue Settings").font(.system(size: 13.5, weight: .bold))
                }
                .padding(.horizontal, 11)
                .padding(.bottom, 9)

                ForEach(Page.allCases) { destination in
                    Button {
                        page = destination
                    } label: {
                        Label(destination.rawValue, systemImage: destination.symbol)
                            .font(.system(size: 12.5, weight: page == destination ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(page == destination ? Color.accentColor.opacity(0.16) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("Local-first · 0.1")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 11)
            }
            .padding(10)
            .frame(width: 164)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            Group {
                switch page {
                case .general: GeneralSettings(model: model)
                case .capture: CaptureSettingsView(model: model)
                case .workspaces: WorkspaceSettings(model: model)
                case .privacy: PrivacySettings(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 640, idealWidth: 700, minHeight: 440, idealHeight: 480)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @State private var launchAtLogin = LaunchAtLoginController.isEnabled

    var body: some View {
        SettingsPage(title: "General", subtitle: "Keep Cue quiet until you ask for it.") {
            Toggle("Launch Cue at login", isOn: Binding(
                get: { launchAtLogin },
                set: { value in
                    do {
                        try LaunchAtLoginController.setEnabled(value)
                        launchAtLogin = value
                    } catch {
                        model.publishReceipt(Receipt(message: "Launch at login was not changed", symbol: "exclamationmark.triangle.fill", isError: true))
                    }
                }
            ))
            Toggle("Keep the sidecar above other windows", isOn: binding(\.keepPanelOnTop))
            Toggle("Use a more opaque surface", isOn: binding(\.reduceTranslucency))
            Toggle("Complete items when copied", isOn: binding(\.completeOnCopy))
            Text("Copy is explicit but completion stays separate by default. When enabled, every copy marks its items complete immediately.")
                .settingsHint()

            Divider().padding(.vertical, 4)
            Text("Global shortcuts").font(.headline)
            ShortcutPicker(title: "Capture selection", value: Binding(
                get: { model.settings.captureChord },
                set: { value in model.updateSettings { $0.captureChord = value } }
            ))
            ShortcutPicker(title: "Show or hide Cue", value: Binding(
                get: { model.settings.panelChord },
                set: { value in model.updateSettings { $0.panelChord = value } }
            ))
            ShortcutPicker(title: "Open composer", value: Binding(
                get: { model.settings.composerChord },
                set: { value in model.updateSettings { $0.composerChord = value } }
            ))
            Text("Double Shift remains the direct selection-capture gesture. Preset chords are registered without Input Monitoring; conflicts are reported immediately.")
                .settingsHint()

            Divider().padding(.vertical, 4)

            LabeledContent("Active queue") { Text("\(model.queuedCount) queued · \(model.completedCount) completed") }
            LabeledContent("Archive") { Text("\(model.archiveCount) items") }
            LabeledContent("App mode") { Text("Menu bar · no Dock icon") }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { value in model.updateSettings { $0[keyPath: keyPath] = value } })
    }
}

private struct ShortcutPicker: View {
    var title: String
    @Binding var value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Menu {
                ForEach(GlobalShortcutPreset.allCases) { preset in
                    Button {
                        value = preset.rawValue
                    } label: {
                        if preset.rawValue == value {
                            Label(preset.label, systemImage: "checkmark")
                        } else {
                            Text(preset.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(GlobalShortcutPreset(rawValue: value)?.label ?? "Off")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 94)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.055)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

private struct CaptureSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var denylistText = ""

    var body: some View {
        SettingsPage(title: "Capture", subtitle: "Read only the selection you explicitly request.") {
            HStack(spacing: 12) {
                Image(systemName: model.isAccessibilityTrusted ? "checkmark.shield.fill" : "hand.raised.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(model.isAccessibilityTrusted ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isAccessibilityTrusted ? "Selection access is ready" : "Selection access is off")
                        .font(.headline)
                    Text("Typed prompts, search, copy, completion and Archive work either way.")
                        .settingsHint()
                }
                Spacer()
                if model.isAccessibilityTrusted {
                    Button("Refresh") { model.refreshAccessibilityStatus() }
                } else {
                    Button("Enable…") { model.requestAccessibilityPermission() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(11)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))

            Toggle("Save source app name", isOn: Binding(
                get: { model.settings.captureSourceApp },
                set: { value in model.updateSettings { $0.captureSourceApp = value } }
            ))
            Toggle("Save source window title", isOn: Binding(
                get: { model.settings.captureWindowTitle },
                set: { value in model.updateSettings { $0.captureWindowTitle = value } }
            ))
            Text("Window titles are off by default because chat, page and document titles can contain sensitive project names.")
                .settingsHint()

            HStack {
                Text("Duplicate window")
                Slider(value: Binding(
                    get: { model.settings.duplicateWindowSeconds },
                    set: { value in model.updateSettings { $0.duplicateWindowSeconds = value } }
                ), in: 0.5...5, step: 0.5)
                Text("\(model.settings.duplicateWindowSeconds, specifier: "%.1f")s")
                    .monospacedDigit().frame(width: 38, alignment: .trailing)
            }

            Divider().padding(.vertical, 4)
            Text("Never capture from these bundle identifiers").font(.headline)
            TextEditor(text: $denylistText)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 80)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor).opacity(0.84)))
            HStack {
                Text("One identifier per line. Secure text fields are always blocked separately.").settingsHint()
                Spacer()
                Button("Save denylist") {
                    let values = denylistText.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    model.updateSettings { $0.denylistedBundleIdentifiers = values }
                }
            }
        }
        .onAppear { denylistText = model.settings.denylistedBundleIdentifiers.joined(separator: "\n") }
    }
}

private struct WorkspaceSettings: View {
    @ObservedObject var model: AppModel
    @State private var bundleIdentifier = ""
    @State private var titlePattern = ""
    @State private var mappedWorkspaceID: UUID?

    var body: some View {
        SettingsPage(title: "Workspaces", subtitle: "One human-readable Markdown file per project context.") {
            ForEach(model.settings.workspaces) { workspace in
                HStack(spacing: 10) {
                    Image(systemName: workspace.id == model.settings.activeWorkspaceID ? "tray.full.fill" : "tray")
                        .foregroundStyle(workspace.id == model.settings.activeWorkspaceID ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workspace.title).font(.system(size: 13, weight: .semibold))
                        Text(workspace.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Use") { model.switchWorkspace(to: workspace.id) }
                        .disabled(workspace.id == model.settings.activeWorkspaceID)
                    Menu {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: workspace.path)]) }
                        Button("Remove from Cue") { model.removeWorkspaceReference(workspace.id) }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))
            }

            HStack {
                Button("Create…") { createWorkspace() }
                Button("Open…") { openWorkspace() }
                Spacer()
                Button("Reveal active file") { model.revealWorkspace() }
            }

            Divider().padding(.vertical, 4)
            Text("Confirmed context mappings").font(.headline)
            Text("A mapping can switch workspaces only when both its app and optional title phrase match. Cue never infers mappings by itself.")
                .settingsHint()

            HStack {
                TextField("Bundle identifier, e.g. com.tinyspeck.slackmacgap", text: $bundleIdentifier)
                TextField("Window title contains (optional)", text: $titlePattern)
            }
            Picker("Workspace", selection: Binding(
                get: { mappedWorkspaceID ?? model.settings.activeWorkspaceID },
                set: { mappedWorkspaceID = $0 }
            )) {
                ForEach(model.settings.workspaces) { workspace in Text(workspace.title).tag(Optional(workspace.id)) }
            }
            HStack {
                Spacer()
                Button("Add mapping") { addMapping() }
                    .disabled(bundleIdentifier.trimmingCharacters(in: .whitespaces).isEmpty || (mappedWorkspaceID ?? model.settings.activeWorkspaceID) == nil)
            }

            ForEach(model.settings.contextMappings) { mapping in
                HStack {
                    Toggle("", isOn: Binding(
                        get: { mapping.enabled },
                        set: { enabled in model.updateSettings { settings in
                            if let index = settings.contextMappings.firstIndex(where: { $0.id == mapping.id }) { settings.contextMappings[index].enabled = enabled }
                        } }
                    )).labelsHidden()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mapping.appBundleIdentifier).font(.system(size: 12, weight: .medium, design: .monospaced))
                        Text(mapping.titlePattern.isEmpty ? "Any confirmed title" : "Title contains “\(mapping.titlePattern)”").settingsHint()
                    }
                    Spacer()
                    Text(model.settings.workspaces.first(where: { $0.id == mapping.workspaceID })?.title ?? "Missing workspace")
                        .font(.caption).foregroundStyle(.secondary)
                    Button { model.updateSettings { $0.contextMappings.removeAll { $0.id == mapping.id } } } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func addMapping() {
        guard let workspaceID = mappedWorkspaceID ?? model.settings.activeWorkspaceID else { return }
        let mapping = ContextMapping(
            appBundleIdentifier: bundleIdentifier.trimmingCharacters(in: .whitespaces),
            titlePattern: titlePattern.trimmingCharacters(in: .whitespaces),
            workspaceID: workspaceID
        )
        model.updateSettings { $0.contextMappings.append(mapping) }
        bundleIdentifier = ""
        titlePattern = ""
    }

    private func createWorkspace() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "Cue Workspace.md"
        if panel.runModal() == .OK, let url = panel.url { model.createWorkspace(title: url.deletingPathExtension().lastPathComponent, at: url) }
    }

    private func openWorkspace() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url { model.addExistingWorkspace(url: url) }
    }
}

private struct PrivacySettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPage(title: "Privacy", subtitle: "The boundary is visible and boring on purpose.") {
            PrivacyRow(symbol: "externaldrive.fill", title: "Content storage", detail: "Local Markdown workspace files chosen by you")
            PrivacyRow(symbol: "network.slash", title: "Note content network", detail: "No network code path; content is never uploaded")
            PrivacyRow(symbol: "chart.bar.xaxis", title: "Analytics and telemetry", detail: "None implemented")
            PrivacyRow(symbol: "rectangle.and.text.magnifyingglass", title: "Selection capture", detail: "Only after double Shift or the explicit Capture command")
            PrivacyRow(symbol: "doc.on.clipboard", title: "Clipboard history", detail: "Never monitored; selected-text failure does not fall back to clipboard")
            PrivacyRow(symbol: "paperplane", title: "Automatic sending", detail: "Not implemented; you paste deliberately")

            Divider().padding(.vertical, 4)
            Text("Accessibility permission").font(.headline)
            Text("Cue uses Accessibility for the global Shift gesture and the foreground app's explicit selected-text attribute. Secure fields, denylisted apps and empty selections persist zero content.")
                .settingsHint()
            Button("Open Accessibility Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }

            Divider().padding(.vertical, 4)
            LabeledContent("Settings file") { Text("~/Library/Application Support/Cue/settings.json").font(.system(size: 10, design: .monospaced)) }
            if let path = model.activeWorkspace?.path {
                LabeledContent("Active workspace") { Text(path).font(.system(size: 10, design: .monospaced)).lineLimit(1) }
            }
        }
    }
}

private struct SettingsPage<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                Text(title).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.bottom, 2)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PrivacyRow: View {
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).settingsHint()
            }
        }
        .padding(.vertical, 1)
    }
}

private extension View {
    func settingsHint() -> some View {
        font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
