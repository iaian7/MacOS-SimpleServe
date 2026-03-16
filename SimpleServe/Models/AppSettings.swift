import SwiftUI

enum PreferredBrowser: String, CaseIterable {
    case `default` = "default"
    case safari = "safari"
    case chrome = "chrome"
    case firefox = "firefox"

    var displayName: String {
        switch self {
        case .default: return "Default browser"
        case .safari: return "Safari"
        case .chrome: return "Chrome"
        case .firefox: return "Firefox"
        }
    }

    /// Bundle URL for the application, or nil for default.
    var appURL: URL? {
        switch self {
        case .default: return nil
        case .safari:
            return FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
                .first?.appendingPathComponent("Safari.app")
        case .chrome:
            return URL(fileURLWithPath: "/Applications/Google Chrome.app")
        case .firefox:
            return URL(fileURLWithPath: "/Applications/Firefox.app")
        }
    }
}

enum MenuBarIcon: String, CaseIterable {
    case serverRack = "server.rack"
    case network = "network"
    case antenna = "antenna.radiowaves.left.and.right"

    var displayName: String {
        switch self {
        case .serverRack: return "Server"
        case .network: return "Network"
        case .antenna: return "Radio"
        }
    }
}

class AppSettings: ObservableObject {
    @AppStorage("menuBarIcon") var menuBarIcon: String = MenuBarIcon.serverRack.rawValue
    @AppStorage("startAtLogin") var startAtLogin: Bool = false
    @AppStorage("hasCompletedSetup") var hasCompletedSetup: Bool = false
    @AppStorage("preferredBrowser") var preferredBrowserRaw: String = PreferredBrowser.default.rawValue
    @AppStorage("globalServerEnabled") var globalServerEnabled: Bool = true

    var preferredBrowser: PreferredBrowser {
        get { PreferredBrowser(rawValue: preferredBrowserRaw) ?? .default }
        set { preferredBrowserRaw = newValue.rawValue }
    }

    var menuBarIconEnum: MenuBarIcon {
        get { MenuBarIcon(rawValue: menuBarIcon) ?? .serverRack }
        set { menuBarIcon = newValue.rawValue }
    }
}
