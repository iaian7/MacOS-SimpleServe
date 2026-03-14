import Foundation

class NginxService {
    static let shared = NginxService()
    private let brew = HomebrewService.shared
    private let serversDir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        serversDir = base.appendingPathComponent("SimpleServe/nginx-servers")
        try? FileManager.default.createDirectory(at: serversDir, withIntermediateDirectories: true)
    }

    func generateServerBlock(for site: Site, phpSocket: String?, certPath: String?, keyPath: String?) -> String {
        var c = "# SimpleServe: \(site.hostname)\n"
        c += "server {\n    listen 8080;\n    server_name \(site.domain);\n"
        c += "    root \(site.folderPath);\n    index index.html index.php;\n\n"
        c += "    location / {\n        try_files $uri $uri/ =404;\n    }\n"
        if let sock = phpSocket {
            c += "\n    location ~ \\.php$ {\n"
            c += "        fastcgi_pass unix:\(sock);\n"
            c += "        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;\n"
            c += "        include fastcgi_params;\n    }\n"
        }
        c += "}\n"

        if let cert = certPath, let key = keyPath {
            c += "\nserver {\n    listen 8443 ssl;\n    server_name \(site.domain);\n"
            c += "    root \(site.folderPath);\n    index index.html index.php;\n\n"
            c += "    ssl_certificate \(cert);\n    ssl_certificate_key \(key);\n\n"
            c += "    location / {\n        try_files $uri $uri/ =404;\n    }\n"
            if let sock = phpSocket {
                c += "\n    location ~ \\.php$ {\n"
                c += "        fastcgi_pass unix:\(sock);\n"
                c += "        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;\n"
                c += "        include fastcgi_params;\n    }\n"
            }
            c += "}\n"
        }
        return c
    }

    func writeSiteConfig(_ site: Site, phpSocket: String?, certPath: String?, keyPath: String?) {
        let config = generateServerBlock(for: site, phpSocket: phpSocket, certPath: certPath, keyPath: keyPath)
        try? config.write(to: serversDir.appendingPathComponent("\(site.hostname).conf"),
                          atomically: true, encoding: .utf8)
    }

    func removeSiteConfig(_ site: Site) {
        try? FileManager.default.removeItem(at: serversDir.appendingPathComponent("\(site.hostname).conf"))
    }

    func ensureIncludeDirective() {
        let nginxConf = "\(brew.brewPrefix)/etc/nginx/nginx.conf"
        guard var content = try? String(contentsOfFile: nginxConf, encoding: .utf8),
              !content.contains(serversDir.path) else { return }

        let inc = "\n    include \(serversDir.path)/*.conf;\n"

        // Use a regex to find the `http {` block opener, then walk forward
        // counting braces so we insert inside the correct closing `}` rather
        // than blindly before the last `}` in the whole file.
        guard let httpMatch = content.range(of: #"\bhttp\s*\{"#, options: .regularExpression) else {
            // No http block found – append one as a fallback.
            content += "\nhttp {\(inc)}\n"
            try? content.write(toFile: nginxConf, atomically: true, encoding: .utf8)
            return
        }

        // httpMatch.upperBound is the character just after the opening `{`.
        var depth = 1
        var idx = httpMatch.upperBound
        while idx < content.endIndex, depth > 0 {
            switch content[idx] {
            case "{": depth += 1
            case "}": depth -= 1
            default: break
            }
            if depth > 0 { idx = content.index(after: idx) }
        }
        guard depth == 0 else { return }   // malformed config – don't touch it
        content.insert(contentsOf: inc, at: idx)
        try? content.write(toFile: nginxConf, atomically: true, encoding: .utf8)
    }

    func start() { ensureIncludeDirective(); brew.startService("nginx") }
    func stop() { brew.stopService("nginx") }
    func restart() { brew.restartService("nginx") }
}
