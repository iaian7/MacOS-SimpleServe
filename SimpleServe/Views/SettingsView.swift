import SwiftUI

enum SettingsTab: Hashable {
    case components
    case commands
    case preferences
}

final class SettingsNavigation: ObservableObject {
    @Published var selectedTab: SettingsTab = .components
}

struct SettingsView: View {
    @EnvironmentObject var siteManager: SiteManager
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var settingsNavigation: SettingsNavigation

    var body: some View {
        TabView(selection: $settingsNavigation.selectedTab) {
            ComponentsTabView()
                .environmentObject(siteManager)
                .tag(SettingsTab.components)
                .tabItem { Label("Components", systemImage: "square.grid.2x2") }

            CommandsTabView()
                .tag(SettingsTab.commands)
                .tabItem { Label("Commands", systemImage: "terminal") }

            PreferencesTabView()
                .environmentObject(appSettings)
                .tag(SettingsTab.preferences)
                .tabItem { Label("Preferences", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 480)
    }
}
