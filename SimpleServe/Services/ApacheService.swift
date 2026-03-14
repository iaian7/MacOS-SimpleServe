import Foundation

class ApacheService {
    static let shared = ApacheService()

    private let brew = HomebrewService.shared
    private let appSupportDir: URL
    private let vhostsDir: URL
    private let logsDir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appSupportDir = base.appendingPathComponent("SimpleServe")
        vhostsDir = appSupportDir.appendingPathComponent("vhosts")
        logsDir = appSupportDir.appendingPathComponent("logs")
        try? FileManager.default.createDirectory(at: vhostsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    }

    var httpdConfPath: String { "\(brew.brewPrefix)/etc/httpd/httpd.conf" }

    // MARK: - Configuration

    func ensureIncludeDirective() {
        guard var content = try? String(contentsOfFile: httpdConfPath, encoding: .utf8) else { return }
        let quotedDirective = "IncludeOptional \"\(vhostsDir.path)/*.conf\""
        // Remove any previously-written unquoted directive (which breaks when path has spaces)
        let unquotedDirective = "IncludeOptional \(vhostsDir.path)/*.conf"
        if content.contains(unquotedDirective) {
            content = content.replacingOccurrences(
                of: "\n\n# SimpleServe virtual hosts\n\(unquotedDirective)\n",
                with: "")
        }
        if !content.contains(quotedDirective) {
            content += "\n\n# SimpleServe virtual hosts\n\(quotedDirective)\n"
            try? content.write(toFile: httpdConfPath, atomically: true, encoding: .utf8)
        }
        enableRequiredModules()  // Always run (modules, ServerName, Listen 8443)
    }

    private func enableRequiredModules() {
        guard var content = try? String(contentsOfFile: httpdConfPath, encoding: .utf8) else { return }
        let modules = ["rewrite_module", "ssl_module", "proxy_module", "proxy_fcgi_module", "vhost_alias_module"]
        for mod in modules {
            content = content.replacingOccurrences(of: "#LoadModule \(mod)", with: "LoadModule \(mod)")
        }
        // Suppress AH00558: uncomment standard ServerName line or add if missing
        let commentedPatterns = ["#ServerName www.example.com:8080", "#ServerName www.example.com:80"]
        let fixed = commentedPatterns.first { content.contains($0) }.map { p in
            content.replacingOccurrences(of: p, with: "ServerName localhost")
        }
        if let c = fixed {
            content = c
        } else {
            let hasServerName = content.components(separatedBy: .newlines).contains { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return !t.isEmpty && !t.hasPrefix("#") && t.hasPrefix("ServerName ")
            }
            if !hasServerName {
                content += "\nServerName localhost\n"
            }
        }
        // Ensure Listen 8080 for HTTP (match VirtualHost *:8080)
        if !content.contains("Listen 8080") {
            content += "\nListen 8080\n"
        }
        // Ensure Listen 8443 for SSL
        if !content.contains("Listen 8443") {
            content += "\nListen 8443\n"
        }
        try? content.write(toFile: httpdConfPath, atomically: true, encoding: .utf8)
    }

    // MARK: - VHost Generation

    func generateVhostConfig(for site: Site, phpSocket: String?, certPath: String?, keyPath: String?) -> String {
        var c = "# SimpleServe: \(site.hostname)\n"

        // HTTP
        c += "<VirtualHost *:8080>\n"
        c += "    ServerName \(site.domain)\n"
        c += "    DocumentRoot \"\(site.folderPath)\"\n\n"
        c += directoryBlock(site.folderPath)
        if let sock = phpSocket { c += phpProxyBlock(sock) }
        c += logBlock(site.hostname)
        c += "</VirtualHost>\n\n"

        // HTTPS
        if let cert = certPath, let key = keyPath {
            c += "<VirtualHost *:8443>\n"
            c += "    ServerName \(site.domain)\n"
            c += "    DocumentRoot \"\(site.folderPath)\"\n\n"
            c += "    SSLEngine on\n"
            c += "    SSLCertificateFile \"\(cert)\"\n"
            c += "    SSLCertificateKeyFile \"\(key)\"\n\n"
            c += directoryBlock(site.folderPath)
            if let sock = phpSocket { c += phpProxyBlock(sock) }
            c += logBlock("\(site.hostname)-ssl")
            c += "</VirtualHost>\n"
        }
        return c
    }

    private func directoryBlock(_ path: String) -> String {
        """
            <Directory "\(path)">
                Options Indexes FollowSymLinks
                AllowOverride All
                Require all granted
            </Directory>

        """
    }

    private func phpProxyBlock(_ socket: String) -> String {
        """
            <FilesMatch \\.php$>
                SetHandler "proxy:unix:\(socket)|fcgi://localhost"
            </FilesMatch>

        """
    }

    private func logBlock(_ name: String) -> String {
        """
            ErrorLog "\(logsDir.path)/\(name)-error.log"
            CustomLog "\(logsDir.path)/\(name)-access.log" combined

        """
    }

    // MARK: - Write / Remove

    func writeSiteConfig(_ site: Site, phpSocket: String?, certPath: String?, keyPath: String?) {
        let config = generateVhostConfig(for: site, phpSocket: phpSocket, certPath: certPath, keyPath: keyPath)
        let file = vhostsDir.appendingPathComponent("\(site.hostname).conf")
        try? config.write(to: file, atomically: true, encoding: .utf8)
    }

    func removeSiteConfig(_ site: Site) {
        let file = vhostsDir.appendingPathComponent("\(site.hostname).conf")
        try? FileManager.default.removeItem(at: file)
    }

    // MARK: - Startup Failure Diagnostics

    /// Diagnoses why Homebrew httpd failed to start and returns a user-facing message plus fix commands.
    /// Call when brew services list reports httpd as "error".
    func diagnoseStartupFailure() -> String {
        // Check if macOS built-in Apache is running
        let systemApache = brew.run("ps aux 2>/dev/null | grep /usr/sbin/httpd | grep -v grep")
        let systemApacheRunning = !systemApache.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // Check if ports 8080/8443 are in use
        let port8080 = brew.run("lsof -i :8080 -t 2>/dev/null")
        let port8443 = brew.run("lsof -i :8443 -t 2>/dev/null")
        let port8080InUse = !port8080.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let port8443InUse = !port8443.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // Get Homebrew httpd error log
        let logPath = "\(brew.brewPrefix)/var/log/httpd/error_log"
        let logTail = brew.run("tail -20 \"\(logPath)\" 2>/dev/null")
        let logOutput = logTail.output.trimmingCharacters(in: .whitespacesAndNewlines)

        if systemApacheRunning {
            var msg = "macOS built-in Apache is running and may conflict with Homebrew httpd."
            msg += "\n\nTo temporarily stop it, run in Terminal:"
            msg += "\n\nsudo /usr/sbin/apachectl stop"
            msg += "\n\nTo disable it permanently:"
            msg += "\n\nsudo launchctl unload -w /System/Library/LaunchDaemons/org.apache.httpd.plist"
            msg += "\n\nThen click Restart in SimpleServe."
            return msg
        }

        if port8080InUse || port8443InUse {
            var msg = "Ports 8080 or 8443 appear to be in use. To see what is using them:"
            msg += "\n\nlsof -i :8080 -i :8443"
            msg += "\n\nStop the process using those ports, then click Restart."
            if !logOutput.isEmpty {
                msg += "\n\nRecent httpd log:\n\(logOutput)"
            }
            return msg
        }

        if !logOutput.isEmpty {
            // Log shows "resuming normal operations" = Apache started; brew services may be stale or system Apache conflicts
            if logOutput.contains("resuming normal operations") || logOutput.contains("AH00163") {
                return "Apache appears to have started (log shows 'resuming normal operations'), but brew services reports an error. Stopping system Apache often fixes this.\n\nTo temporarily stop macOS Apache, run in Terminal:\n\nsudo /usr/sbin/apachectl stop\n\nTo disable it permanently:\n\nsudo launchctl unload -w /System/Library/LaunchDaemons/org.apache.httpd.plist\n\nThen click Restart in SimpleServe."
            }
            return "httpd failed to start.\n\nRecent error log:\n\(logOutput)\n\nStop system Apache first, then click Restart. In Terminal:\n\nsudo /usr/sbin/apachectl stop\n\nOr to disable it permanently:\n\nsudo launchctl unload -w /System/Library/LaunchDaemons/org.apache.httpd.plist"
        }

        return "httpd service is in error state.\n\nStop system Apache first, then click Restart. In Terminal:\n\nsudo /usr/sbin/apachectl stop\n\nOr to disable it permanently:\n\nsudo launchctl unload -w /System/Library/LaunchDaemons/org.apache.httpd.plist"
    }

    // MARK: - Service Control

    func start() { ensureIncludeDirective(); brew.startService("httpd") }
    func stop() { brew.stopService("httpd") }
    func restart() { brew.restartService("httpd") }
}
