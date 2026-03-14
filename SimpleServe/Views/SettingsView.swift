import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var siteManager: SiteManager
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        TabView {
            ComponentsTabView()
                .environmentObject(siteManager)
                .tabItem { Label("Components", systemImage: "square.grid.2x2") }

            CommandsTabView()
                .tabItem { Label("Commands", systemImage: "terminal") }

            PreferencesTabView()
                .environmentObject(appSettings)
                .tabItem { Label("Preferences", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 480)
    }
}
