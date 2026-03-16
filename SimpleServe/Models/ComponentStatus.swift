import Foundation

enum ComponentName: String, CaseIterable, Codable {
    case httpd
    case php
    case dnsmasq
    case mkcert
    case nss
    case nginx

    var displayName: String {
        switch self {
        case .httpd: return "Apache (httpd)"
        case .php: return "PHP"
        case .dnsmasq: return "dnsmasq"
        case .mkcert: return "mkcert"
        case .nss: return "NSS (certutil)"
        case .nginx: return "Nginx"
        }
    }

    var isRequired: Bool {
        switch self {
        case .httpd, .dnsmasq, .mkcert: return true
        case .php, .nss, .nginx: return false
        }
    }

    var installCommand: String {
        "brew install \(rawValue)"
    }
}

struct ComponentInfo: Identifiable, Codable {
    var id: String { name.rawValue }
    let name: ComponentName
    var isInstalled: Bool
    var versions: [String]

    var installCommand: String { name.installCommand }

    var statusText: String {
        if isInstalled {
            return versions.isEmpty ? "Installed" : versions.joined(separator: ", ")
        }
        return "Not installed"
    }
}
