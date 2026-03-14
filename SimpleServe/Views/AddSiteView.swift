import SwiftUI

enum AddSiteMode: Identifiable {
    case add
    case edit(Site)
    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let site): return site.id.uuidString
        }
    }
}

struct AddSiteView: View {
    let mode: AddSiteMode
    @EnvironmentObject var siteManager: SiteManager
    @Environment(\.dismiss) var dismiss

    @State private var folderPath = ""
    @State private var hostname = ""
    @State private var serverType: ServerType = .apache
    @State private var phpVersion = "none"
    @State private var useSSL = true
    @State private var sslError: String?
    @State private var mkcertCAInstalled: Bool = true

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var phpVersions: [String] {
        siteManager.components.first(where: { $0.name == .php })?.versions ?? []
    }

    private var availableServers: [ServerType] {
        var s: [ServerType] = [.apache]
        if siteManager.components.first(where: { $0.name == .nginx })?.isInstalled == true {
            s.append(.nginx)
        }
        return s
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(isEditing ? "Edit Site" : "Add Site")
                .font(.headline)
                .padding(.top, 8)

            Form {
                HStack {
                    TextField("Project Folder", text: $folderPath)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                    Button("Browse…") { pickFolder() }
                }

                HStack {
                    TextField("Hostname", text: $hostname)
                        .textFieldStyle(.roundedBorder)
                    Text(".test")
                        .foregroundStyle(.secondary)
                }

                Picker("Server", selection: $serverType) {
                    ForEach(availableServers) { s in
                        Text(s.rawValue).tag(s)
                    }
                }

                Picker("PHP", selection: $phpVersion) {
                    Text("None").tag("none")
                    ForEach(phpVersions, id: \.self) { v in
                        Text(v).tag(v)
                    }
                }

                Toggle("Enable HTTPS (SSL)", isOn: $useSSL)
                    .disabled(!mkcertCAInstalled)
                    .help(mkcertCAInstalled ? "Use HTTPS for this site" : "Run mkcert -install in Terminal (Settings > Commands)")
                if !mkcertCAInstalled {
                    Text("Run mkcert -install in Terminal (Settings > Commands).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Save" : "Add Site") { saveSite() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(folderPath.isEmpty || hostname.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .frame(width: 380)
        .alert("SSL Setup Failed", isPresented: Binding(
            get: { sslError != nil },
            set: { if !$0 { sslError = nil } }
        )) {
            Button("OK", role: .cancel) { sslError = nil }
        } message: {
            if let err = sslError {
                Text(err)
            }
        }
        .onAppear {
            if case .edit(let site) = mode {
                folderPath = site.folderPath
                hostname = site.hostname
                serverType = site.serverType
                phpVersion = site.phpVersion ?? "none"
                useSSL = site.useSSL
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let installed = MkcertService.shared.checkCAInstalled()
                DispatchQueue.main.async {
                    mkcertCAInstalled = installed
                    if !installed && useSSL { useSSL = false }
                }
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the project root directory"
        // Raise the panel above the menu bar popover and any floating sheets.
        panel.level = .popUpMenu
        panel.orderFrontRegardless()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            folderPath = url.path
            if hostname.isEmpty {
                hostname = url.lastPathComponent
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "-")
                    .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
            }
        }
    }

    private func saveSite() {
        sslError = nil
        let php = phpVersion == "none" ? nil : phpVersion
        let ok: Bool
        if case .edit(var existing) = mode {
            existing.folderPath = folderPath
            existing.hostname = hostname
            existing.serverType = serverType
            existing.phpVersion = php
            existing.useSSL = useSSL
            ok = siteManager.updateSite(existing)
        } else {
            let site = Site(folderPath: folderPath, hostname: hostname,
                            serverType: serverType, phpVersion: php,
                            isActive: true, useSSL: useSSL)
            ok = siteManager.addSite(site)
        }
        if ok {
            dismiss()
        } else {
            sslError = siteManager.lastError
        }
    }
}
