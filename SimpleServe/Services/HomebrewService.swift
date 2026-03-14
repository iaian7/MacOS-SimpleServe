import Foundation

class HomebrewService {
    static let shared = HomebrewService()

    let brewPrefix: String
    let brewBin: String

    private init() {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            brewPrefix = "/opt/homebrew"
        } else {
            brewPrefix = "/usr/local"
        }
        brewBin = "\(brewPrefix)/bin/brew"
    }

    var isBrewInstalled: Bool {
        FileManager.default.fileExists(atPath: brewBin)
    }

    @discardableResult
    func run(_ command: String, timeout: TimeInterval = 30) -> (output: String, exitCode: Int32) {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(brewPrefix)/bin:\(brewPrefix)/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env

        do {
            try process.run()
        } catch {
            return ("Error: \(error.localizedDescription)", 1)
        }

        // Watchdog: kill the process if it exceeds the timeout
        let deadline = DispatchTime.now() + timeout
        DispatchQueue.global().asyncAfter(deadline: deadline) {
            if process.isRunning { process.terminate() }
        }
        process.waitUntilExit()

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (output.trimmingCharacters(in: .whitespacesAndNewlines), process.terminationStatus)
    }

    func checkComponent(_ component: ComponentName) -> ComponentInfo {
        if component == .php { return checkPHP() }

        // `brew list --versions <name>` outputs "name version" if installed, empty if not.
        // This is a single fast command that avoids the pipe-buffer deadlock caused by
        // the verbose `brew list <name>` output (which can produce thousands of lines).
        let vr = run("\(brewBin) list --versions \(component.rawValue) 2>/dev/null")
        let parts = vr.output.split(separator: " ", maxSplits: 1)
        let installed = parts.count >= 2
        let versions: [String] = installed ? [String(parts[1]).trimmingCharacters(in: .whitespaces)] : []
        return ComponentInfo(name: component, isInstalled: installed, versions: versions)
    }

    private func checkPHP() -> ComponentInfo {
        // `brew list --formula` with grep gives just formula names, not file lists.
        let result = run("\(brewBin) list --formula 2>/dev/null | grep -E '^php(@[0-9.]+)?$'")
        let versions = result.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return ComponentInfo(name: .php, isInstalled: !versions.isEmpty, versions: versions)
    }

    func checkAllComponents() -> [ComponentInfo] {
        ComponentName.allCases.map { checkComponent($0) }
    }

    /// Start service on-demand (does not register for launch at login/boot).
    func startService(_ name: String) {
        run("\(brewBin) services stop \(name) 2>/dev/null")  // cleanup any prior registration
        run("\(brewBin) services run \(name)")
    }
    func stopService(_ name: String) { run("\(brewBin) services stop \(name)") }
    func restartService(_ name: String) { stopService(name); startService(name) }
}
