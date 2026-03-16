import Foundation

struct PortForwardingStatus {
    let isConfigured: Bool
    let isRuntimeActive: Bool
    let verificationError: String?
}

/// Detects and describes pfctl forwarding state (80→8080, 443→8443).
class PortForwardingService {
    static let shared = PortForwardingService()

    private let brew = HomebrewService.shared
    private let pfConfPath = "/etc/pf.conf"
    private let anchorPath = "/etc/pf.anchors/simpleserve"

    /// Creates anchor file, inserts rules in pf translation section, and reloads pf.
    var setupCommand: String {
        "sudo mkdir -p /etc/pf.anchors && printf 'rdr pass inet proto tcp from any to 127.0.0.1 port 80 -> 127.0.0.1 port 8080\\nrdr pass inet proto tcp from any to 127.0.0.1 port 443 -> 127.0.0.1 port 8443\\n' | sudo tee /etc/pf.anchors/simpleserve > /dev/null && sudo perl -0777 -i -pe 's|^rdr-anchor \"simpleserve\"\\n||gm; s|^load anchor \"simpleserve\" from \"[^\"]+\"\\n||gm; s|(rdr-anchor \"com\\.apple/\\*\")|$1\\nrdr-anchor \"simpleserve\"\\nload anchor \"simpleserve\" from \"/etc/pf.anchors/simpleserve\"|' /etc/pf.conf && sudo pfctl -ef /etc/pf.conf"
    }

    /// Removes all SimpleServe refs from pf.conf, reloads pf, then deletes anchor file.
    var revertCommand: String {
        "sudo perl -0777 -i -pe 's|^rdr-anchor \"simpleserve\"\\n||gm; s|^load anchor \"simpleserve\" from \"[^\"]+\"\\n||gm' /etc/pf.conf && sudo pfctl -ef /etc/pf.conf && sudo rm -f /etc/pf.anchors/simpleserve"
    }

    /// Legacy one-bit status used by older call sites.
    var isActive: Bool {
        status.isRuntimeActive
    }

    var status: PortForwardingStatus {
        let configured = isConfigured
        if !configured {
            return PortForwardingStatus(
                isConfigured: false,
                isRuntimeActive: false,
                verificationError: nil
            )
        }
        let runtime = runtimeState()
        return PortForwardingStatus(
            isConfigured: configured,
            isRuntimeActive: runtime.isActive,
            verificationError: runtime.error
        )
    }

    private var isConfigured: Bool {
        let anchorOK = anchorRulesConfigured()
        let pfBlockOK = pfConfContainsManagedBlock()
        return anchorOK && pfBlockOK
    }

    private func anchorRulesConfigured() -> Bool {
        guard
            let content = try? String(contentsOfFile: anchorPath, encoding: .utf8)
        else { return false }
        return content.contains("port 80 -> 127.0.0.1 port 8080")
            && content.contains("port 443 -> 127.0.0.1 port 8443")
    }

    private func pfConfContainsManagedBlock() -> Bool {
        guard
            let content = try? String(contentsOfFile: pfConfPath, encoding: .utf8)
        else { return false }
        return content.contains("rdr-anchor \"simpleserve\"")
            && content.contains("load anchor \"simpleserve\" from \"/etc/pf.anchors/simpleserve\"")
    }

    private func runtimeState() -> (isActive: Bool, error: String?) {
        let result = brew.run("/sbin/pfctl -s nat -a simpleserve 2>&1", timeout: 5)
        if result.exitCode != 0 {
            let out = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            // On modern macOS, reading pf NAT state requires elevated privileges.
            // If the rules are confirmed configured in pf.conf and the anchor file,
            // treat runtime as active rather than surfacing a misleading false negative.
            if out.localizedCaseInsensitiveContains("permission denied")
                || out.localizedCaseInsensitiveContains("/dev/pf")
            {
                return (true, nil)
            }
            let message = out.isEmpty ? "pfctl returned non-zero exit code (\(result.exitCode))."
                                  : "pfctl check failed: \(out)"
            return (false, message)
        }
        let lines = result.output.components(separatedBy: .newlines).map {
            $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let has80to8080 = lines.contains(where: { isForwardRule($0, fromPort: 80, toPort: 8080) })
        let has443to8443 = lines.contains(where: { isForwardRule($0, fromPort: 443, toPort: 8443) })
        return (has80to8080 && has443to8443, nil)
    }

    private func isForwardRule(_ line: String, fromPort: Int, toPort: Int) -> Bool {
        guard line.contains("rdr"), line.contains("->") else { return false }
        return line.contains("port \(fromPort)") && line.contains("port \(toPort)")
    }
}
