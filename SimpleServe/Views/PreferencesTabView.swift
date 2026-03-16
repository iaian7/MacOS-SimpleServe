import SwiftUI
import ServiceManagement

struct PreferencesTabView: View {
    @EnvironmentObject var appSettings: AppSettings
    @State private var loginItemError: String? = nil
    @State private var isUpdatingLoginItem = false

    var body: some View {
        Form {
            Section("Open Sites In") {
                Picker("Browser", selection: Binding(
                    get: { appSettings.preferredBrowser.rawValue },
                    set: { appSettings.preferredBrowser = PreferredBrowser(rawValue: $0) ?? .default }
                )) {
                    ForEach(PreferredBrowser.allCases, id: \.rawValue) { browser in
                        Text(browser.displayName).tag(browser.rawValue)
                    }
                }
            }

            Section("Appearance") {
                Picker("Menu Bar Icon", selection: $appSettings.menuBarIcon) {
                    ForEach(MenuBarIcon.allCases, id: \.rawValue) { icon in
                        Label(icon.displayName, systemImage: icon.rawValue).tag(icon.rawValue)
                    }
                }
            }

            Section("Startup") {
                Toggle("Start at login", isOn: $appSettings.startAtLogin)
                    .onChange(of: appSettings.startAtLogin) { _, newValue in
                        updateLoginItem(enabled: newValue)
                    }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Login Item Error", isPresented: .constant(loginItemError != nil), actions: {
            Button("OK") { loginItemError = nil }
        }, message: {
            Text(loginItemError ?? "")
        })
    }

    private func updateLoginItem(enabled: Bool) {
        guard !isUpdatingLoginItem else { return }
        isUpdatingLoginItem = true
        defer { isUpdatingLoginItem = false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert the toggle and surface the error to the user.
            appSettings.startAtLogin = !enabled
            loginItemError = error.localizedDescription
        }
    }
}
