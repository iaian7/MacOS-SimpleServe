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
                DirectoryIndex index.php index.html index.htm
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

    private static let systemApacheFix = """
        To temporarily stop macOS Apache, run in Terminal:
        sudo /usr/sbin/apachectl stop

        To disable it permanently:
        sudo launchctl unload -w /System/Library/LaunchDaemons/org.apache.httpd.plist
        """

    private static let launchctlBootstrapFix = """
        Unload stale user launchd entries, then click Restart in SimpleServe. In Terminal:
        launchctl bootout gui/$(id -u) "$HOME/Library/LaunchAgents/homebrew.mxcl.httpd.plist" 2>/dev/null
        brew services stop httpd
        brew services cleanup
        """

    private static let rootOwnedServiceFix = """
        httpd appears to be registered as root. Re-register it under your user account:
        sudo brew services stop httpd
        sudo launchctl bootout system/homebrew.mxcl.httpd 2>/dev/null
        brew services cleanup
        brew services start httpd
        """

    /// Diagnoses why Homebrew httpd failed to start and returns a user-facing message plus fix commands.
    /// Call when brew services list reports httpd as "error".
    func diagnoseStartupFailure() -> String {
        let brewBin = brew.brewBin
        let logPath = "\(brew.brewPrefix)/var/log/httpd/error_log"

        // Gather all diagnostics (do NOT run brew services run here - it can worsen the failure)
        let brewServices = brew.run("\(brewBin) services list 2>&1")
        let systemApache = brew.run("ps aux 2>/dev/null | grep /usr/sbin/httpd | grep -v grep")
        let systemApacheRunning = !systemApache.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let portBindings = brew.run("lsof -i :8080 -i :8443 2>/dev/null")
        let port8080 = brew.run("lsof -i :8080 -t 2>/dev/null")
        let port8443 = brew.run("lsof -i :8443 -t 2>/dev/null")
        let port8080InUse = !port8080.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let port8443InUse = !port8443.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let launchctlList = brew.run("launchctl list 2>/dev/null | grep -E 'httpd|homebrew' || true")
        let logTail = brew.run("tail -30 \"\(logPath)\" 2>/dev/null")
        let logOutput = logTail.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let httpdLine = brewServices.output.components(separatedBy: "\n").first { $0.hasPrefix("httpd") } ?? brewServices.output
        let serviceLooksRootOwned = httpdLine.contains(" root ")
        let launchctlHttpdLine = launchctlList.output
            .components(separatedBy: "\n")
            .first { $0.contains("homebrew.mxcl.httpd") } ?? ""
        let isLaunchctlErrorState = launchctlHttpdLine.contains("\t1\t") || launchctlHttpdLine.contains(" 1 ")
        let logShowsResumed = logOutput.contains("resuming normal operations") || logOutput.contains("AH00163")

        // Build structured findings
        var findings: [String] = []
        findings.append("System Apache: \(systemApacheRunning ? "running" : "not running")")
        findings.append("Port 8080: \(port8080InUse ? "in use" : "free")")
        findings.append("Port 8443: \(port8443InUse ? "in use" : "free")")

        func formatMessage(summary: String, fix: String) -> String {
            var msg = summary
            msg += "\n\nFindings:\n" + findings.map { "- \($0)" }.joined(separator: "\n")
            if !portBindings.output.isEmpty {
                msg += "\n\nPort bindings (lsof -i :8080 -i :8443):\n\(portBindings.output)"
            }
            msg += "\n\nBrew services (httpd):\n\(httpdLine)"
            if !launchctlList.output.isEmpty {
                msg += "\n\nLaunchctl (httpd/homebrew):\n\(launchctlList.output)"
            }
            if !logOutput.isEmpty {
                msg += "\n\nRecent httpd error log:\n\(logOutput)"
            }
            msg += "\n\nFix: \(fix)"
            return msg
        }

        if systemApacheRunning {
            let fix = Self.systemApacheFix + "\n\nThen click Restart in SimpleServe."
            return formatMessage(summary: "macOS built-in Apache is running and may conflict with Homebrew httpd.", fix: fix)
        }

        if port8080InUse || port8443InUse {
            let fix = "Stop the process using ports 8080/8443 (see lsof above), then click Restart."
            return formatMessage(summary: "Ports 8080 or 8443 appear to be in use.", fix: fix)
        }

        if serviceLooksRootOwned {
            return formatMessage(
                summary: "Homebrew reports httpd under root. This usually means it was started with sudo and now conflicts with user launchd.",
                fix: Self.rootOwnedServiceFix + "\nThen click Restart in SimpleServe."
            )
        }

        if isLaunchctlErrorState && !systemApacheRunning {
            let fix = Self.launchctlBootstrapFix + "\nThen click Restart in SimpleServe."
            let summary = "launchctl bootstrap failed (exit 5). This is usually a stale service in launchd, not system Apache."
            return formatMessage(summary: summary, fix: fix)
        }

        if logShowsResumed {
            // Apache started but brew reports error; system Apache already handled above
            let summary = "Apache appears to have started (log shows 'resuming normal operations'), but brew services reports an error."
            let fix = Self.launchctlBootstrapFix + "\nThen click Restart in SimpleServe."
            return formatMessage(summary: summary, fix: fix)
        }

        if !logOutput.isEmpty {
            let fix = Self.launchctlBootstrapFix + "\nThen click Restart."
            return formatMessage(summary: "httpd failed to start.", fix: fix)
        }

        let fix = Self.launchctlBootstrapFix + "\nThen click Restart."
        return formatMessage(summary: "httpd service is in error state.", fix: fix)
    }

    /// Returns true when Homebrew httpd is actually running, even if `brew services list` is stale.
    func isHomebrewApacheRunning() -> Bool {
        let httpdBin = "\(brew.brewPrefix)/opt/httpd/bin/httpd"
        let process = brew.run("ps aux 2>/dev/null | grep \"\(httpdBin)\" | grep -v grep")
        if !process.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        let listener = brew.run("lsof -nP -iTCP:8080 -sTCP:LISTEN 2>/dev/null")
        return !listener.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Service Control

    func start() { ensureIncludeDirective(); brew.startService("httpd") }
    func stop() { brew.stopService("httpd") }
    func restart() { ensureIncludeDirective(); brew.restartService("httpd") }
}
