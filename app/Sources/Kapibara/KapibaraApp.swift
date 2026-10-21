import SwiftUI
import AppKit
import ServiceManagement

@main
struct KapibaraApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(AppModel.shared)
        } label: {
            BarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar label lives in its own View: observation at the App/Scene
/// level does not reliably refresh MenuBarExtra labels, a dedicated
/// observed view does.
struct BarLabel: View {
    @ObservedObject private var model = AppModel.shared
    @AppStorage("menubarDisplay") private var menubarDisplay: String = "both"

    var body: some View {
        HStack(spacing: 4) {
            // Bake the state color into a non-template image so macOS
            // preserves it in the status item. The .id() forces the
            // image to be rebuilt when the state changes.
            if menubarDisplay != "text" {
                Image(nsImage: KapibaraIcon.menuBarImage(color: barColor))
                    .renderingMode(.original)
                    .id("icon-\(model.stateVersion)")
            }
            if menubarDisplay != "icon" {
                Text(model.barTitle)
                    .id("text-\(model.stateVersion)")
            }
        }
    }

    private var barColor: NSColor {
        switch model.state {
        case .up: return .systemGreen
        case .starting: return .systemYellow
        case .down: return .systemGray
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar agent: no Dock icon, no main window.
        NSApplication.shared.setActivationPolicy(.accessory)
        // AppModel starts its refresh on initialization. A second call
        // here would repeat the expensive doctor report at launch.
        _ = AppModel.shared
    }
}

struct MenuContent: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("language") private var languageRaw: String = "system"
    @AppStorage("menubarDisplay") private var menubarDisplay: String = "both"
    @State private var loginError: String?

    /// App version from the bundle plist, stamped by `make app`.
    /// "dev" when run via `swift run`.
    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            serverSection
            Divider()
            modelsSection
            Divider()
            downloadSection
            if !model.activity.isEmpty {
                Divider()
                analyticsSection
            }
            Divider()
            logsSection
            Divider()
            settingsSection
            Divider()
            HStack {
                Button(L10n.t("refresh.button")) { model.refresh() }
                    .keyboardShortcut("r")
                if let refreshed = model.lastRefresh {
                    Text(refreshed.formatted(date: .omitted, time: .standard))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(L10n.t("version.display", appVersion))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Divider()
                    .frame(height: 12)
                Button(L10n.t("quit.button")) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(minWidth: 300)
        .onAppear { model.refreshServer() }
    }

    @State private var selectedModel: String = ""
    @State private var selectedCatalogModel: String = ""
    @State private var selectedCatalogVariant: String = ""

    /// The toggle button is disabled while the server is starting, when
    /// it is up but not owned by the app, or when no model is installed
    /// to start with.
    private var serverButtonDisabled: Bool {
        switch model.state {
        case .starting:
            return true
        case .up:
            return !model.ownsServer
        case .down:
            return model.installedModels.isEmpty
        }
    }

    private var serverDotColor: Color {
        switch model.state {
        case .up: return .green
        case .starting: return .yellow
        case .down: return .secondary
        }
    }

    private var serverStatusText: String {
        switch model.state {
        case .up: return L10n.t("server.up")
        case .starting: return L10n.t("server.starting")
        case .down: return L10n.t("server.down")
        }
    }

    private var engineActivityText: String {
        switch model.engineActivity {
        case .idle: return ""
        case .prefill: return L10n.t("engine.prefill")
        case .generating: return L10n.t("engine.generating")
        }
    }

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("server.headline")).font(.headline)
            HStack {
                Circle()
                    .fill(serverDotColor)
                    .frame(width: 8, height: 8)
                Text(serverStatusText)
                    .font(.callout)
                if model.isUp, model.engineActivity != .idle {
                    Text(engineActivityText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if case .up(let served) = model.state {
                    Text("\(served.id) · \(served.slots ?? 0) \(L10n.t("server.slots"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if case .down = model.state, !model.installedModels.isEmpty {
                Picker(L10n.t("server.model"), selection: $selectedModel) {
                    ForEach(model.installedModels) { m in
                        Text(m.name).tag(m.name)
                    }
                }
                .font(.caption)
                .labelsHidden()
                .onAppear {
                    if selectedModel.isEmpty || !model.installedModelIds.contains(selectedModel) {
                        selectedModel = model.installedModels.first?.name ?? ""
                    }
                }
                .onChange(of: model.installedModels) { _ in
                    if selectedModel.isEmpty || !model.installedModelIds.contains(selectedModel) {
                        selectedModel = model.installedModels.first?.name ?? ""
                    }
                }
                contextSlider(for: selectedModel)
            }
            let isExternalServer = model.isUp && !model.ownsServer
            let isStarting = model.state == .starting
            Button {
                guard !isExternalServer else { return }
                if model.isUp {
                    model.stopServer()
                } else {
                    model.startServer(model: selectedModel.isEmpty ? nil : selectedModel)
                }
            } label: {
                HStack(spacing: 4) {
                    if isStarting {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                    Text(model.isUp ? L10n.t("server.stop") : L10n.t("server.start"))
                }
            }
            .font(.caption)
            .keyboardShortcut("s")
            .disabled(serverButtonDisabled && !isExternalServer)
            .opacity(isExternalServer ? 0.5 : 1)
            .help(isExternalServer ? L10n.t("server.external") : "")
            if isExternalServer {
                Text(L10n.t("server.external"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if case .down = model.state, model.installedModels.isEmpty {
                Text(L10n.t("server.no_models"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button(L10n.t("server.open_chat")) {
                if let url = URL(string: "http://127.0.0.1:\(model.port)/") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.caption)
            .disabled(!model.isUp)
        }
    }

    /// Context window slider for the selected model. Min 8K, max the
    /// model's trained context limit from `kapitsa doctor`. 0 means
    /// "Auto": kapitsa picks (memory-dependent default), the slider
    /// then shows the default position greyed out.
    private func contextSlider(for modelName: String) -> some View {
        let limit = model.contextLimit(for: modelName) ?? 131_072
        let defaultCtx = model.defaultContext(for: modelName) ?? 131_072
        let minCtx = 8_192
        let isAuto = model.contextTokens == 0
        // Clamp the stored value into the model's range so switching
        // models never leaves the slider out of bounds.
        let stored = min(max(model.contextTokens, minCtx), limit)
        let displayValue = isAuto ? defaultCtx : stored

        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(L10n.t("server.context"))
                    .font(.caption)
                Spacer()
                if isAuto {
                    Text(L10n.t("context.auto_value", formatContext(defaultCtx)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(formatContext(displayValue))
                        .font(.caption)
                }
            }
            Slider(
                value: Binding(
                    get: { Double(displayValue) },
                    set: { model.contextTokens = Int($0) }
                ),
                in: Double(minCtx)...Double(limit),
                step: 1_024
            )
            .disabled(isAuto)
            HStack(spacing: 4) {
                Button(L10n.t("context.auto")) { model.contextTokens = 0 }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                Button(L10n.t("context.default")) { model.contextTokens = defaultCtx }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                Button(L10n.t("context.max")) { model.contextTokens = limit }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                Spacer()
                Text(L10n.t("context.limit_label", formatContext(limit)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: selectedModel) { _ in
            // Clamp the stored context when the model changes.
            let newLimit = model.contextLimit(for: selectedModel) ?? 131_072
            if model.contextTokens > newLimit {
                model.contextTokens = newLimit
            }
        }
    }

    /// Compact context size: 1M, 256K, 8K.
    private func formatContext(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.0fM", Double(tokens) / 1_000_000)
        }
        return String(format: "%.0fK", Double(tokens) / 1_000)
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("models.headline")).font(.headline)
            if model.installedModels.isEmpty {
                Text(L10n.t(model.modelsLoading ? "models.loading" : "models.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.installedModels) { m in
                    HStack {
                        Text(m.name)
                            .font(.caption)
                        Spacer()
                        Text(m.sizeLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Circle()
                            .fill(m.complete ? .green : .orange)
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
    }

    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("download.headline")).font(.headline)
            if model.catalogModels.isEmpty {
                Text(L10n.t(model.catalogLoading ? "download.catalog_loading" : "download.catalog_empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker(L10n.t("download.pick"), selection: $selectedCatalogModel) {
                    ForEach(model.catalogModels, id: \.self) { name in
                        let variants = model.variants(for: name)
                        if variants.contains(where: { $0.fits }) {
                            Text(name).tag(name)
                        } else {
                            Text("\(name) · \(L10n.t("download.does_not_fit"))")
                                .foregroundStyle(.orange)
                                .tag(name)
                        }
                    }
                }
                .font(.caption)
                .labelsHidden()

                let variants = model.variants(for: selectedCatalogModel)
                if !variants.isEmpty {
                    Picker(L10n.t("download.variant"), selection: $selectedCatalogVariant) {
                        ForEach(variants, id: \.id) { variant in
                            Text(variant.variant)
                                .tag(variant.variant)
                                .disabled(!variant.fits)
                        }
                    }
                    .font(.caption)
                    .labelsHidden()

                    if let variant = variants.first(where: { $0.variant == selectedCatalogVariant }) {
                        HStack {
                            if !variant.fits {
                                Text(L10n.t("download.does_not_fit"))
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            if model.installedModelIds.contains(variant.id) {
                                Text(L10n.t("download.done"))
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            } else if model.downloadingModel == variant.id {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Button(L10n.t("download.button")) {
                                    model.startDownload(variant.id)
                                }
                                .font(.caption2)
                                .disabled(!variant.fits || model.downloadingModel != nil)
                            }
                        }
                    }
                }
            }
            if let downloading = model.downloadingModel {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.t("download.downloading") + " " + downloading)
                        .font(.caption)
                    Spacer()
                    Button(L10n.t("download.cancel")) { model.cancelDownload() }
                        .font(.caption2)
                }
            }
            if let error = model.downloadError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            if selectedCatalogModel.isEmpty || !model.catalogModels.contains(selectedCatalogModel) {
                selectedCatalogModel = model.catalogModels.first ?? ""
            }
            let variants = model.variants(for: selectedCatalogModel)
            if selectedCatalogVariant.isEmpty
                || !variants.contains(where: { $0.variant == selectedCatalogVariant }) {
                selectedCatalogVariant = variants.first?.variant ?? ""
            }
        }
        .onChange(of: model.catalog) { _ in
            if selectedCatalogModel.isEmpty || !model.catalogModels.contains(selectedCatalogModel) {
                selectedCatalogModel = model.catalogModels.first ?? ""
            }
            let variants = model.variants(for: selectedCatalogModel)
            if selectedCatalogVariant.isEmpty
                || !variants.contains(where: { $0.variant == selectedCatalogVariant }) {
                selectedCatalogVariant = variants.first?.variant ?? ""
            }
        }
        .onChange(of: selectedCatalogModel) { _ in
            let variants = model.variants(for: selectedCatalogModel)
            selectedCatalogVariant = variants.first?.variant ?? ""
        }
    }

    private var analyticsSection: some View {
        let summary = model.activitySummary
        return VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("analytics.headline")).font(.headline)
            HStack(spacing: 12) {
                statColumn(L10n.t("analytics.total_requests", summary.requestCount))
                statColumn(L10n.t("analytics.total_prompt_tokens", formatTokens(summary.totalPromptTokens)))
                statColumn(L10n.t("analytics.total_output_tokens", formatTokens(summary.totalOutputTokens)))
            }
            HStack(spacing: 12) {
                statColumn(L10n.t("analytics.avg_tps", summary.avgTokPerSec))
                statColumn(L10n.t("analytics.avg_prefill", summary.avgPrefillMs))
            }
            Divider()
            ForEach(model.recentActivity) { entry in
                HStack(spacing: 6) {
                    Text("\(entry.promptTokens) → \(entry.outputTokens)")
                        .font(.caption2)
                    Text(String(format: "%.1f tok/s", entry.tokPerSec))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.finishReason)
                        .font(.caption2)
                        .foregroundStyle(finishColor(entry.finishReason))
                }
            }
            HStack {
                Spacer()
                HStack(spacing: 2) {
                    Button(L10n.t("analytics.open_log")) { model.openActivityLog() }
                    Menu {
                        logEditorMenuItem(
                            L10n.t("analytics.open_log.default"),
                            id: AppModel.systemDefaultLogEditorID
                        )
                        if !model.logEditors.isEmpty {
                            Divider()
                        }
                        ForEach(model.logEditors) { editor in
                            logEditorMenuItem(editor.name, id: editor.bundleIdentifier)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .help(L10n.t("analytics.open_log.choose"))
                }
                .font(.caption2)
            }
        }
        // Force rebuild on every poll: SwiftUI skips @Published arrays
        // whose content is unchanged.
        .id(model.activityVersion)
    }

    private func statColumn(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func logEditorMenuItem(_ name: String, id: String) -> some View {
        Button {
            model.openActivityLog(using: id)
        } label: {
            if model.selectedLogEditorID == id {
                Label(name, systemImage: "checkmark")
            } else {
                Text(name)
            }
        }
    }

    private func finishColor(_ reason: String) -> Color {
        switch reason {
        case "stop": return .green
        case "tool_calls": return .blue
        case "length": return .orange
        case "cancelled": return .red
        default: return .secondary
        }
    }

    /// Compact token count: 1.6M, 42K, 800.
    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.t("logs.headline")).font(.headline)
                Spacer()
                Button(L10n.t("refresh.button")) { model.refreshLogs() }
                    .font(.caption2)
            }
            if model.logLines.isEmpty {
                Text(L10n.t("logs.empty"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(model.logLines, id: \.self) { line in
                            Text(line)
                                .font(.caption2)
                                .foregroundStyle(logLineColor(line))
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
    }

    private func logLineColor(_ line: String) -> Color {
        if line.contains("[ERROR]") { return .red }
        if line.contains("[WARN]") { return .orange }
        return .secondary
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("settings.headline")).font(.headline)
            Toggle(L10n.t("login.toggle"), isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                    }
                }
            ))
            .font(.caption)
            Picker(L10n.t("settings.menubar"), selection: $menubarDisplay) {
                Text(L10n.t("menubar.icon")).tag("icon")
                Text(L10n.t("menubar.text")).tag("text")
                Text(L10n.t("menubar.both")).tag("both")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .font(.caption)
            Picker(L10n.t("settings.language"), selection: $languageRaw) {
                Text(L10n.t("language.system")).tag("system")
                Text(L10n.t("language.french")).tag("fr")
                Text(L10n.t("language.english")).tag("en")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .font(.caption)
            if let loginError {
                Text(loginError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }
}
