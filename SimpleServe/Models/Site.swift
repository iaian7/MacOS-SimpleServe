import Foundation

enum ServerType: String, Codable, CaseIterable, Identifiable {
    case apache = "Apache"
    case nginx = "Nginx"
    var id: String { rawValue }
}

struct Site: Codable, Identifiable, Equatable {
    var id: UUID
    var folderPath: String
    var hostname: String
    var serverType: ServerType
    var phpVersion: String?
    var isActive: Bool
    var useSSL: Bool

    var domain: String { "\(hostname).test" }

    init(folderPath: String, hostname: String, serverType: ServerType = .apache,
         phpVersion: String? = nil, isActive: Bool = true, useSSL: Bool = true) {
        self.id = UUID()
        self.folderPath = folderPath
        self.hostname = hostname
        self.serverType = serverType
        self.phpVersion = phpVersion
        self.isActive = isActive
        self.useSSL = useSSL
    }
}

class SiteURLResolver {
    static let shared = SiteURLResolver()

    func urlString(for site: Site, allowPortlessWhenForwarding: Bool = true) -> String {
        let scheme = site.useSSL ? "https" : "http"
        if allowPortlessWhenForwarding && PortForwardingService.shared.status.isRuntimeActive {
            return "\(scheme)://\(site.domain)"
        }
        let port = site.useSSL ? 8443 : 8080
        return "\(scheme)://\(site.domain):\(port)"
    }

    func fallbackHTTPURLString(for site: Site) -> String {
        if PortForwardingService.shared.status.isRuntimeActive {
            return "http://\(site.domain)"
        }
        return "http://\(site.domain):8080"
    }
}
