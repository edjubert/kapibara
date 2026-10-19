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

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(model.isUp ? .green : .secondary)
                .frame(width: 7, height: 7)
            Text(model.barTitle)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar agent: no Dock icon, no main window.
        NSApplication.shared.setActivationPolicy(.accessory)
        AppModel.shared.refresh()
    }
}

struct MenuContent: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("language") private var languageRaw: String = "system"
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
            } else {
                serverSection
                Divider()
                modelsSection
            }
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
        .onAppear { model.refresh() }
    }

    @State private var selectedModel: String = ""

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("server.headline")).font(.headline)
            HStack {
                Circle()
                    .fill(model.isUp ? .green : .secondary)
                    .frame(width: 8, height: 8)
                Text(model.isUp ? L10n.t("server.up") : L10n.t("server.down"))
                    .font(.callout)
                Spacer()
                if case .up(let served) = model.state {
                    Text("\(served.id) · \(served.slots ?? 0) \(L10n.t("server.slots"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if model.isUp {
                if model.ownsServer {
                    Button(L10n.t("server.stop")) { model.stopServer() }
                        .font(.caption)
                }
            } else {
                if !model.installedModels.isEmpty {
                    Picker(L10n.t("server.model"), selection: $selectedModel) {
                        ForEach(model.installedModels) { m in
                            Text(m.name).tag(m.name)
                        }
                    }
                    .font(.caption)
                    .labelsHidden()
                    .onAppear {
                        if selectedModel.isEmpty {
                            selectedModel = model.installedModels.first?.name ?? ""
                        }
                    }
                }
                Button(L10n.t("server.start")) {
                    model.startServer(model: selectedModel.isEmpty ? nil : selectedModel)
                }
                .font(.caption)
                .disabled(model.installedModels.isEmpty)
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

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("models.headline")).font(.headline)
            if model.installedModels.isEmpty {
                Text(L10n.t("models.empty"))
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
