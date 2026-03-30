import Foundation
import Combine

enum ServerRunStatus: Equatable {
    case unknown
    case running
    case stopped
    case error(String)
}

class SiteManager: ObservableObject {
    static let shared = SiteManager()

    @Published var sites: [Site] = []
    @Published var components: [ComponentInfo] = []
    @Published var isLoading = false
    @Published var serverStatus: ServerRunStatus = .unknown
    @Published var lastError: String?

    private let sitesFileURL: URL
    private let componentsFileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("SimpleServe")
        sitesFileURL = dir.appendingPathComponent("sites.json")
        componentsFileURL = dir.appendingPathComponent("components.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        loadSites()
        loadComponents()
    }

    // MARK: - Persistence

    func loadSites() {
        guard let data = try? Data(contentsOf: sitesFileURL),
              let decoded = try? JSONDecoder().decode([Site].self, from: data) else {
            sites = []
            return
        }
        sites = decoded
        sortSites()
    }

    func saveSites() {
        sortSites()
        do {
            let data = try JSONEncoder().encode(sites)
            try data.write(to: sitesFileURL)
        } catch {
            print("SimpleServe: failed to save sites – \(error)")
        }
    }

    private func sortSites() {
        sites.sort { $0.hostname.localizedStandardCompare($1.hostname) == .orderedAscending }
    }

    private func loadComponents() {
        guard let data = try? Data(contentsOf: componentsFileURL),
              let decoded = try? JSONDecoder().decode([ComponentInfo].self, from: data) else { return }
        components = decoded
    }

    private func saveComponents() {
        guard let data = try? JSONEncoder().encode(components) else { return }
        try? data.write(to: componentsFileURL)
    }

    // MARK: - Component Status

    func refreshComponents() {
        guard !isLoading else { return }   // prevent concurrent refreshes
        isLoading = true
        components = []                    // clear stale data before each refresh
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = HomebrewService.shared.checkAllComponents()
            DispatchQueue.main.async {
                self?.components = result
                self?.isLoading = false
                self?.saveComponents()     // persist so next launch skips the check
            }
        }
    }

    var hasRequiredComponents: Bool {
        let required: [ComponentName] = [.httpd, .dnsmasq, .mkcert]
        return required.allSatisfy { name in
            components.first(where: { $0.name == name })?.isInstalled == true
        }
    }

    // MARK: - Site Management

    /// Adds a site. Returns false if SSL setup failed (error stored in lastError).
    @discardableResult
    func addSite(_ site: Site) -> Bool {
        if let err = MkcertService.shared.ensureSSLReady(for: site.hostname) {
            DispatchQueue.main.async { self.lastError = err }
            return false
        }
        sites.append(site)
        saveSites()
        if site.isActive { configureSite(site); restartServers() }
        DispatchQueue.main.async { self.lastError = nil }
        return true
    }

    /// Updates a site. Returns false if SSL setup failed (error stored in lastError).
    @discardableResult
    func updateSite(_ site: Site) -> Bool {
        guard let idx = sites.firstIndex(where: { $0.id == site.id }) else { return false }
        let old = sites[idx]
        if old.hostname != site.hostname {
            removeSiteConfig(old)
            MkcertService.shared.removeCert(for: old.hostname)
        }
        if let err = MkcertService.shared.ensureSSLReady(for: site.hostname) {
            DispatchQueue.main.async { self.lastError = err }
            return false
        }
        sites[idx] = site
        saveSites()
        if site.isActive { configureSite(site) } else { removeSiteConfig(site) }
        restartServers()
        DispatchQueue.main.async { self.lastError = nil }
        return true
    }

    func removeSite(_ site: Site) {
        removeSiteConfig(site)
        MkcertService.shared.removeCert(for: site.hostname)
        sites.removeAll { $0.id == site.id }
        saveSites()
        restartServers()
    }

    func toggleSite(_ site: Site) {
        guard let idx = sites.firstIndex(where: { $0.id == site.id }) else { return }
        let willActivate = !sites[idx].isActive
        if willActivate {
            if let err = MkcertService.shared.ensureSSLReady(for: sites[idx].hostname) {
                DispatchQueue.main.async { self.lastError = err }
                return
            }
        }
        sites[idx].isActive.toggle()
        saveSites()
        if sites[idx].isActive { configureSite(sites[idx]) } else { removeSiteConfig(sites[idx]) }
        restartServers()
        DispatchQueue.main.async {
            DispatchQueue.main.async { self.lastError = nil }
        }
    }

    // MARK: - Configuration

    private func configureSite(_ site: Site) {
        let phpSocket = site.phpVersion.map { PHPService.shared.socketPath(for: $0) }
        guard let cert = MkcertService.shared.generateCert(for: site.hostname) else {
            DispatchQueue.main.async {
                self.lastError = "Failed to generate certificate for \(site.hostname).test. Open Settings -> Commands and verify mkcert setup."
            }
            return
        }

        switch site.serverType {
        case .apache:
            ApacheService.shared.writeSiteConfig(site, phpSocket: phpSocket,
                                                  certPath: cert.certPath, keyPath: cert.keyPath)
        case .nginx:
            NginxService.shared.writeSiteConfig(site, phpSocket: phpSocket,
                                                 certPath: cert.certPath, keyPath: cert.keyPath)
        }
    }

    private func removeSiteConfig(_ site: Site) {
        switch site.serverType {
        case .apache: ApacheService.shared.removeSiteConfig(site)
        case .nginx: NginxService.shared.removeSiteConfig(site)
        }
    }

    // MARK: - Server Control

    func restartServers() {
        // When the server is globally disabled, skip service restarts.
        // Config files are still written/removed by the caller so they are
        // ready the moment the global toggle is turned back on.
        guard UserDefaults.standard.bool(forKey: "globalServerEnabled") else { return }

        let snapshot = sites
        DispatchQueue.main.async { self.serverStatus = .unknown }
        DispatchQueue.global(qos: .userInitiated).async {
            guard snapshot.contains(where: { $0.isActive }) else {
                self.stopAllServices()
                return
            }
            if snapshot.contains(where: { $0.isActive && $0.serverType == .apache }) {
                ApacheService.shared.restart()
            } else {
                ApacheService.shared.stop()
            }
            if snapshot.contains(where: { $0.isActive && $0.serverType == .nginx }) {
                NginxService.shared.restart()
            } else {
                NginxService.shared.stop()
            }
            let neededPHPVersions = Set(snapshot.compactMap { $0.isActive ? $0.phpVersion : nil })
            for v in neededPHPVersions {
                PHPService.shared.configureFPM(version: v)
                PHPService.shared.restartFPM(version: v)
            }
            for v in PHPService.shared.installedVersions() {
                if !neededPHPVersions.contains(v) {
                    PHPService.shared.stopFPM(version: v)
                }
            }
            self.checkServerStatus(snapshot: snapshot)
        }
    }

    func startAllServices() {
        let snapshot = sites
        DispatchQueue.main.async { self.serverStatus = .unknown }
        DispatchQueue.global(qos: .userInitiated).async {
            guard snapshot.contains(where: { $0.isActive }) else {
                self.stopAllServices()
                return
            }
            if snapshot.contains(where: { $0.isActive && $0.serverType == .apache }) {
                ApacheService.shared.start()
            }
            if snapshot.contains(where: { $0.isActive && $0.serverType == .nginx }) {
                NginxService.shared.start()
            }
            let phpVersions = Set(snapshot.compactMap { $0.isActive ? $0.phpVersion : nil })
            for v in phpVersions {
                PHPService.shared.configureFPM(version: v)
                PHPService.shared.startFPM(version: v)
            }
            self.checkServerStatus(snapshot: snapshot)
        }
    }

    /// Stops all services. Runs synchronously so it completes before app quit.
    func stopAllServices() {
        ApacheService.shared.stop()
        NginxService.shared.stop()
        for v in PHPService.shared.installedVersions() {
            PHPService.shared.stopFPM(version: v)
        }
        checkServerStatus(snapshot: [])
    }

    // MARK: - Status Check

    /// Shells out to `brew services list` off-main and publishes state on the main thread.
    func checkServerStatus(snapshot: [Site]? = nil) {
        let snapshot = snapshot ?? sites
        DispatchQueue.global(qos: .userInitiated).async {
            let brew = HomebrewService.shared
            let result = brew.run("\(brew.brewBin) services list 2>&1")
            let output = result.output

            // Parse the httpd line from `brew services list` output.
            // Format: "httpd   started  admin  ..."
            //    or:  "httpd   error  1  root  ..."
            //    or:  "httpd   none"
            let lines = output.components(separatedBy: "\n")
            let httpdLine = lines.first(where: { $0.hasPrefix("httpd") }) ?? ""

            let apacheExpected = snapshot.contains { $0.isActive && $0.serverType == .apache }
            let apacheActuallyRunning = apacheExpected && ApacheService.shared.isHomebrewApacheRunning()

            let newStatus: ServerRunStatus
            var errorMsg: String? = nil

            if httpdLine.contains("started") || apacheActuallyRunning {
                newStatus = .running
            } else if httpdLine.contains("error") {
                errorMsg = ApacheService.shared.diagnoseStartupFailure()
                newStatus = .error(errorMsg ?? "")
            } else {
                newStatus = .stopped
            }

            DispatchQueue.main.async {
                self.serverStatus = newStatus
                self.lastError = errorMsg
            }
        }
    }
}
