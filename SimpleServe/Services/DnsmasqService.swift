import Foundation

struct DNSStatus {
    let resolverFileExists: Bool
    let resolverContentValid: Bool
    let dnsmasqDirectivePresent: Bool
    let dnsmasqRunning: Bool
    let diagnostics: [String]

    var isConfigured: Bool {
        resolverContentValid && dnsmasqDirectivePresent && dnsmasqRunning
    }
}

class DnsmasqService {
    static let shared = DnsmasqService()
    private let brew = HomebrewService.shared

    var configPath: String { "\(brew.brewPrefix)/etc/dnsmasq.conf" }
    var resolverPath: String { "/etc/resolver/test" }

    var isResolverConfigured: Bool {
        status.isConfigured
    }

    var status: DNSStatus {
        var diagnostics: [String] = []

        let resolverExists = FileManager.default.fileExists(atPath: resolverPath)
        let resolverContent = (try? String(contentsOfFile: resolverPath, encoding: .utf8)) ?? ""
        let resolverHasNameserver = resolverContent
            .lowercased()
            .contains("nameserver 127.0.0.1")
        if !resolverExists {
            diagnostics.append("Missing /etc/resolver/test.")
        } else if !resolverHasNameserver {
            diagnostics.append("Resolver file exists but does not contain 'nameserver 127.0.0.1'.")
        }

        let dnsmasqContent = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
        let hasDirective = dnsmasqContent.contains("address=/.test/127.0.0.1")
        if !hasDirective {
            diagnostics.append("dnsmasq.conf is missing 'address=/.test/127.0.0.1'.")
        }

        let running = isDnsmasqRunning
        if !running {
            diagnostics.append("dnsmasq process is not running.")
        }

        return DNSStatus(
            resolverFileExists: resolverExists,
            resolverContentValid: resolverHasNameserver,
            dnsmasqDirectivePresent: hasDirective,
            dnsmasqRunning: running,
            diagnostics: diagnostics
        )
    }

    var diagnosticsText: String {
        let items = status.diagnostics
        if items.isEmpty { return "DNS resolver and dnsmasq configuration look correct." }
        return items.joined(separator: "\n")
    }

    var resolverSetupCommand: String {
        "sudo mkdir -p /etc/resolver && echo 'nameserver 127.0.0.1' | sudo tee /etc/resolver/test && grep -qF 'address=/.test/127.0.0.1' \"\(configPath)\" 2>/dev/null || echo 'address=/.test/127.0.0.1' >> \"\(configPath)\" && sudo \(brew.brewBin) services restart dnsmasq"
    }

    func configureDnsmasq() {
        let directive = "address=/.test/127.0.0.1"
        if let content = try? String(contentsOfFile: configPath, encoding: .utf8) {
            guard !content.contains(directive) else { return }
            try? (content + "\n\(directive)\n").write(toFile: configPath, atomically: true, encoding: .utf8)
        } else {
            try? "\(directive)\n".write(toFile: configPath, atomically: true, encoding: .utf8)
        }
    }

    /// Returns true if dnsmasq appears to be running (process exists).
    var isDnsmasqRunning: Bool {
        let result = brew.run("pgrep -x dnsmasq 2>/dev/null")
        return !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func start() { configureDnsmasq(); brew.startService("dnsmasq") }
    func stop() { brew.stopService("dnsmasq") }
    func restart() { configureDnsmasq(); brew.restartService("dnsmasq") }
}
