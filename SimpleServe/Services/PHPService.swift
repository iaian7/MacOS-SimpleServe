import Foundation

class PHPService {
    static let shared = PHPService()
    private let brew = HomebrewService.shared

    func installedVersions() -> [String] {
        let result = brew.run("\(brew.brewBin) list --formula 2>/dev/null | grep -E '^php(@[0-9.]+)?$'")
        return result.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// Resolves "php" (unversioned) to its actual version e.g. "8.5" for config paths.
    private func resolvedVersion(for version: String) -> String {
        if version != "php" {
            return version.replacingOccurrences(of: "php@", with: "")
        }
        let result = brew.run("\(brew.brewPrefix)/opt/php/bin/php -r \"echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;\" 2>/dev/null")
        return result.output.isEmpty ? "8.5" : result.output
    }

    func socketPath(for version: String) -> String {
        if version == "php" {
            return "\(brew.brewPrefix)/var/run/php-fpm.sock"
        }
        let num = resolvedVersion(for: version)
        return "\(brew.brewPrefix)/var/run/php\(num)-fpm.sock"
    }

    func configureFPM(version: String) {
        let num = resolvedVersion(for: version)
        let confDir = "\(brew.brewPrefix)/etc/php/\(num)"
        let fpmConf = "\(confDir)/php-fpm.d/www.conf"
        guard var content = try? String(contentsOfFile: fpmConf, encoding: .utf8) else { return }
        let socket = socketPath(for: version)
        if let range = content.range(of: #"listen\s*=\s*.+"#, options: .regularExpression) {
            content.replaceSubrange(range, with: "listen = \(socket)")
            try? content.write(toFile: fpmConf, atomically: true, encoding: .utf8)
        }
    }

    func startFPM(version: String) { brew.startService(version) }
    func stopFPM(version: String) { brew.stopService(version) }
    func restartFPM(version: String) { brew.restartService(version) }
}
