import Foundation

/// Describes the state of the mkcert root CA on this system.
enum CAStatus: Equatable {
    /// mkcert binary not found, or rootCA.pem does not exist on disk.
    case notFound
    /// rootCA.pem exists on disk but is not present in the system keychain.
    case notInKeychain
    /// Certificate is present in keychain (usable for local cert generation).
    case trusted

    var isUsable: Bool { self == .trusted }
}

class MkcertService {
    static let shared = MkcertService()
    private let brew = HomebrewService.shared
    private let certsDir: URL
    private var lastGenerationError: String?

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        certsDir = base.appendingPathComponent("SimpleServe/certs")
        try? FileManager.default.createDirectory(at: certsDir, withIntermediateDirectories: true)
    }

    var mkcertPath: String { "\(brew.brewPrefix)/bin/mkcert" }

    /// The Terminal command the user should run to install the mkcert root CA.
    /// Intentionally does not use sudo; running with sudo can create unreadable CA key files.
    var installCommand: String { "\"\(mkcertPath)\" -install" }

    private func caRootPath() -> String? {
        let caRootResult = brew.run("\(mkcertPath) -CAROOT", timeout: 5)
        let caRoot = caRootResult.output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return caRoot.isEmpty ? nil : caRoot
    }

    // MARK: - CA Status Check

    /// Checks CA availability: mkcert binary, rootCA.pem, and keychain presence.
    /// Runs subprocesses — call off the main thread.
    func checkCAStatus() -> CAStatus {
        // 1. Verify mkcert binary exists
        guard FileManager.default.fileExists(atPath: mkcertPath) else { return .notFound }

        // 2. Discover CA root directory and verify rootCA.pem exists on disk
        let caRootResult = brew.run("\(mkcertPath) -CAROOT", timeout: 5)
        let caRoot = caRootResult.output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !caRoot.isEmpty else { return .notFound }
        let caPath = "\(caRoot)/rootCA.pem"
        guard FileManager.default.fileExists(atPath: caPath) else { return .notFound }

        // 3. Compute fingerprint for rootCA.pem
        let fpResult = brew.run(
            "/usr/bin/openssl x509 -in \"\(caPath)\" -noout -fingerprint -sha1 2>/dev/null",
            timeout: 5
        )
        guard fpResult.exitCode == 0 else { return .notInKeychain }
        let fingerprint = fpResult.output
            .replacingOccurrences(of: "SHA1 Fingerprint=", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .uppercased()
        guard !fingerprint.isEmpty else { return .notInKeychain }

        // 4. Check if fingerprint exists in system or login keychain
        let keychainScan = brew.run(
            "/usr/bin/security find-certificate -a -Z /Library/Keychains/System.keychain \"$HOME/Library/Keychains/login.keychain-db\" 2>/dev/null",
            timeout: 5
        )
        let normalizedScan = keychainScan.output
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        guard normalizedScan.contains(fingerprint) else {
            return .notInKeychain
        }

        return .trusted
    }

    // MARK: - SSL Readiness

    /// Ensures the mkcert CA is installed/trusted and a certificate exists for the hostname.
    /// Call this before using SSL for a site. Returns nil on success, or an error message on failure.
    func ensureSSLReady(for hostname: String) -> String? {
        guard generateCert(for: hostname) != nil else {
            let status = checkCAStatus()
            switch status {
            case .notFound:
                return "mkcert is not installed or has no local CA yet. Install mkcert and run \"\(installCommand)\", then try adding the site again."
            case .notInKeychain:
                return "mkcert CA exists but is not in your macOS keychain. Run \"\(installCommand)\" once, then try adding the site again."
            case .trusted:
                if let details = lastGenerationError, !details.isEmpty {
                    if details.localizedCaseInsensitiveContains("failed to read the CA key") ||
                        (details.localizedCaseInsensitiveContains("rootCA-key.pem") &&
                         details.localizedCaseInsensitiveContains("permission denied")) {
                        if let caRoot = caRootPath() {
                            return "mkcert CA key is not readable by your user (usually caused by running install with sudo).\n\nRun in Terminal:\n1) sudo chown \"$USER\" \"\(caRoot)/rootCA-key.pem\" \"\(caRoot)/rootCA.pem\" && chmod 600 \"\(caRoot)/rootCA-key.pem\"\n2) \(installCommand)\n\nThen try adding the site again."
                        }
                        return "mkcert CA key is not readable by your user (usually caused by running install with sudo). Fix the files in ~/Library/Application Support/mkcert, run \(installCommand), then try adding the site again."
                    }
                    return "Failed to generate certificate for \(hostname).test. mkcert output: \(details)"
                }
                return "Failed to generate certificate for \(hostname).test. Open Settings -> Commands and verify mkcert setup, then try again."
            }
        }
        return nil
    }

    // MARK: - Certificate Generation

    func generateCert(for hostname: String) -> (certPath: String, keyPath: String)? {
        let certFile = certsDir.appendingPathComponent("\(hostname).pem").path
        let keyFile = certsDir.appendingPathComponent("\(hostname)-key.pem").path

        if FileManager.default.fileExists(atPath: certFile),
           FileManager.default.fileExists(atPath: keyFile) {
            lastGenerationError = nil
            return (certFile, keyFile)
        }

        let result = brew.runWithStderr(
            "cd \"\(certsDir.path)\" && \"\(mkcertPath)\" -cert-file \"\(hostname).pem\" -key-file \"\(hostname)-key.pem\" \(hostname).test localhost 127.0.0.1",
            timeout: 20
        )
        if result.exitCode == 0 {
            lastGenerationError = nil
            return (certFile, keyFile)
        }

        let details = [result.stderr, result.output]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        lastGenerationError = details
        return nil
    }

    func removeCert(for hostname: String) {
        try? FileManager.default.removeItem(atPath: certsDir.appendingPathComponent("\(hostname).pem").path)
        try? FileManager.default.removeItem(atPath: certsDir.appendingPathComponent("\(hostname)-key.pem").path)
    }
}
