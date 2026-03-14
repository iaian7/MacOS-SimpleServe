import Foundation

class MkcertService {
    static let shared = MkcertService()
    private let brew = HomebrewService.shared
    private let certsDir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        certsDir = base.appendingPathComponent("SimpleServe/certs")
        try? FileManager.default.createDirectory(at: certsDir, withIntermediateDirectories: true)
    }

    var mkcertPath: String { "\(brew.brewPrefix)/bin/mkcert" }

    /// Checks whether the mkcert CA is installed in the system Keychain. Runs a subprocess — call off the main thread.
    func checkCAInstalled() -> Bool {
        guard FileManager.default.fileExists(atPath: mkcertPath) else { return false }
        let result = brew.run("/usr/bin/security find-certificate -a -c \"mkcert\" 2>/dev/null", timeout: 5)
        return result.exitCode == 0
    }

    /// Installs the mkcert root CA into the system trust store.
    /// Returns nil on success, or an error message on failure.
    func installCA() -> String? {
        let result = brew.run("\(mkcertPath) -install 2>&1")
        guard result.exitCode == 0 else {
            let msg = result.output.isEmpty ? "mkcert -install failed" : result.output
            return "Failed to install mkcert root CA: \(msg). Run 'mkcert -install' in Terminal and approve the Keychain prompt, then try again."
        }
        return nil
    }

    /// Ensures the mkcert CA is installed and a certificate exists for the hostname.
    /// Call this before using SSL for a site. Returns nil on success, or an error message on failure.
    func ensureSSLReady(for hostname: String) -> String? {
        if !checkCAInstalled() {
            if let err = installCA() { return err }
        }
        guard generateCert(for: hostname) != nil else {
            return "Failed to generate certificate for \(hostname).test. Run 'mkcert -install' in Terminal if you haven't, approve the Keychain prompt, then try again."
        }
        return nil
    }

    func generateCert(for hostname: String) -> (certPath: String, keyPath: String)? {
        let certFile = certsDir.appendingPathComponent("\(hostname).pem").path
        let keyFile = certsDir.appendingPathComponent("\(hostname)-key.pem").path

        if FileManager.default.fileExists(atPath: certFile),
           FileManager.default.fileExists(atPath: keyFile) {
            return (certFile, keyFile)
        }

        let result = brew.run(
            "cd \"\(certsDir.path)\" && \(mkcertPath) -cert-file \"\(hostname).pem\" -key-file \"\(hostname)-key.pem\" \(hostname).test localhost 127.0.0.1 2>&1"
        )
        return result.exitCode == 0 ? (certFile, keyFile) : nil
    }

    func removeCert(for hostname: String) {
        try? FileManager.default.removeItem(atPath: certsDir.appendingPathComponent("\(hostname).pem").path)
        try? FileManager.default.removeItem(atPath: certsDir.appendingPathComponent("\(hostname)-key.pem").path)
    }
}
