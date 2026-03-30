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

    var domain: String { "\(hostname).test" }

    init(folderPath: String, hostname: String, serverType: ServerType = .apache,
         phpVersion: String? = nil, isActive: Bool = true) {
        self.id = UUID()
        self.folderPath = folderPath
        self.hostname = hostname
        self.serverType = serverType
        self.phpVersion = phpVersion
        self.isActive = isActive
    }
}

class SiteURLResolver {
    static let shared = SiteURLResolver()

    func urlString(for site: Site, allowPortlessWhenForwarding: Bool = true) -> String {
        let forwarding = PortForwardingService.shared.status
        if allowPortlessWhenForwarding && forwarding.isConfigured {
            return "https://\(site.domain)"
        }
        return "https://\(site.domain):8443"
    }
}
