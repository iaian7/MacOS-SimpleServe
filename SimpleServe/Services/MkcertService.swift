import Foundation

/// Describes the state of the mkcert root CA on this system.
enum CAStatus: Equatable {
    /// mkcert binary not found, or rootCA.pem does not exist on disk.
    case notFound
    /// rootCA.pem exists on disk but is not present in the system keychain.
    case notInKeychain
    /// Certificate is in the system keychain but not marked as trusted.
    case notTrusted
    /// Certificate is in the system keychain and trusted.
    case trusted

    var isUsable: Bool { self == .trusted }
}

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

    /// The full Terminal command the user should run to install the mkcert root CA.
    /// Requires sudo so macOS presents the trust approval dialog.
    var installCommand: String { "sudo \(mkcertPath) -install" }

    // MARK: - CA Status Check

    /// Checks the full status of the mkcert root CA: existence, keychain presence, and trust.
    /// Runs subprocesses — call off the main thread.
    func checkCAStatus() -> CAStatus {
        // 1. Verify mkcert binary exists
        guard FileManager.default.fileExists(atPath: mkcertPath) else { return .notFound }

        // 2. Discover CA root directory and verify rootCA.pem exists on disk
        let caRootResult = brew.run("\(mkcertPath) -CAROOT", timeout: 5)
        let caRoot = caRootResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !caRoot.isEmpty else { return .notFound }
        let caPath = "\(caRoot)/rootCA.pem"
        guard FileManager.default.fileExists(atPath: caPath) else { return .notFound }

        // 3. Check whether the mkcert CA certificate is present in the system keychain
        let findResult = brew.run(
            "/usr/bin/security find-certificate -c \"mkcert\" -a /Library/Keychains/System.keychain 2>&1",
            timeout: 5
        )
        guard findResult.exitCode == 0, findResult.output.contains("mkcert") else {
            return .notInKeychain
        }

        // 4. Check whether the certificate is trusted (admin trust-settings domain)
        let trustResult = brew.run(
            "/usr/bin/security dump-trust-settings -d 2>&1",
            timeout: 5
        )
        // dump-trust-settings exits 0 and lists certs when trust entries exist.
        // If mkcert appears in the output, the CA has explicit trust set.
        if trustResult.exitCode == 0, trustResult.output.contains("mkcert") {
            return .trusted
        }

        return .notTrusted
    }

    // MARK: - SSL Readiness

    /// Ensures the mkcert CA is installed/trusted and a certificate exists for the hostname.
    /// Call this before using SSL for a site. Returns nil on success, or an error message on failure.
    func ensureSSLReady(for hostname: String) -> String? {
        let status = checkCAStatus()
        if !status.isUsable {
            switch status {
            case .notFound:
                return "mkcert root CA is not installed. Open Settings \u{2192} Commands and follow the mkcert setup instructions."
            case .notInKeychain:
                return "mkcert root CA exists on disk but has not been added to the system keychain. Open Settings \u{2192} Commands and run the install command in Terminal."
            case .notTrusted:
                return "mkcert root CA is in the keychain but not trusted. Open Settings \u{2192} Commands and run \"\(installCommand)\" in Terminal to approve the trust dialog."
            case .trusted:
                break // unreachable given the guard above
            }
        }

        guard generateCert(for: hostname) != nil else {
            return "Failed to generate certificate for \(hostname).test. Ensure mkcert is working by running \"\(installCommand)\" in Terminal, then try again."
        }
        return nil
    }

    // MARK: - Certificate Generation

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
