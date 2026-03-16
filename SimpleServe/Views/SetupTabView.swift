import SwiftUI

struct ComponentsTabView: View {
    @EnvironmentObject var siteManager: SiteManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Component Status")
                    .font(.headline)
                Spacer()
                Button(action: { siteManager.refreshComponents() }) {
                    Label("Refresh", systemImage: "arrow.counterclockwise")
                }
                .disabled(siteManager.isLoading)
            }

            if siteManager.isLoading {
                ProgressView("Checking components…")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if siteManager.components.isEmpty {
                Text("No components found. Is Homebrew installed?")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(siteManager.components) { comp in
                            ComponentRowView(component: comp)
                                .padding(.horizontal, 4)
                            if comp.id != siteManager.components.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if siteManager.components.isEmpty {
                DispatchQueue.main.async { siteManager.refreshComponents() }
            }
        }
    }
}

struct CommandsTabView: View {
    @State private var mkcertCAStatus: CAStatus?
    @State private var dnsStatus: DNSStatus? = nil
    @State private var portForwardingStatus: PortForwardingStatus? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Commands")
                    .font(.headline)
                Spacer()
                Button(action: {
                    refreshDNSStatus()
                    refreshMkcertStatus()
                    refreshPortForwardingStatus()
                }) {
                    Label("Refresh", systemImage: "arrow.counterclockwise")
                }
            }

            ScrollView {
            VStack(alignment: .leading, spacing: 16) {

            // DNS Resolver status
            GroupBox("DNS Resolver") {
                VStack(alignment: .leading, spacing: 8) {
                    if dnsStatus == nil {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Checking…")
                        }
                    } else if let s = dnsStatus {
                        HStack(spacing: 10) {
                            Label("Resolver", systemImage: s.resolverContentValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(s.resolverContentValid ? .green : .red)
                                .font(.caption)
                            Label("dnsmasq config", systemImage: s.dnsmasqDirectivePresent ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(s.dnsmasqDirectivePresent ? .green : .red)
                                .font(.caption)
                            Label("Running", systemImage: s.dnsmasqRunning ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(s.dnsmasqRunning ? .green : .secondary)
                                .font(.caption)
                        }
                        Text(s.isConfigured ? "DNS for .test domains is configured." : "DNS for .test domains is not fully configured.")
                            .font(.caption)
                    }

                    if dnsStatus?.isConfigured == false {
                        Text("Run this command in Terminal:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text(DnsmasqService.shared.resolverSetupCommand)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(6)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(4)
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(DnsmasqService.shared.resolverSetupCommand, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                            .help("Copy to clipboard")
                        }
                        Text(DnsmasqService.shared.diagnosticsText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // mkcert CA status
            GroupBox("mkcert Root CA") {
                VStack(alignment: .leading, spacing: 8) {
                    if mkcertCAStatus == nil {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Checking…")
                        }
                    } else if let status = mkcertCAStatus {
                        HStack(spacing: 10) {
                            Label("Trusted", systemImage: status == .trusted ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(status == .trusted ? .green : .red)
                                .font(.caption)
                            if status == .notTrusted {
                                Label("Not trusted", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                            }
                        }
                        Text(status == .trusted
                             ? "mkcert root CA is installed and trusted."
                             : status == .notTrusted
                                 ? "mkcert root CA is in the keychain but not trusted."
                                 : status == .notInKeychain
                                     ? "mkcert root CA is not in the system keychain."
                                     : "mkcert root CA is not installed.")
                            .font(.caption)
                    }

                    if let status = mkcertCAStatus, !status.isUsable {
                        Text(status == .notTrusted
                             ? "Run the install command in Terminal to trigger the macOS trust approval dialog:"
                             : "Run this command in Terminal to install the mkcert root CA. macOS will prompt you to approve the certificate trust:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(MkcertService.shared.installCommand)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(6)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(4)
                            Button(action: { copyToClipboard(MkcertService.shared.installCommand) }) {
                                Image(systemName: "doc.on.doc")
                            }
                            .help("Copy to clipboard")
                        }

                        Text("For Firefox support, install NSS first (see Components tab), then re-run the install command.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("After running the command and approving the prompt, click Refresh to verify.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if mkcertCAStatus == .trusted {
                        Text("For Firefox support, install NSS (see Components tab) and re-run the install command in Terminal. If Safari shows \"connection is not private\", try restarting Safari or use Chrome.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Port forwarding (optional port-free URLs)
            GroupBox("Port Forwarding") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if portForwardingStatus == nil {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Checking…")
                        } else if let s = portForwardingStatus {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 10) {
                                    Label("Configured", systemImage: s.isConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(s.isConfigured ? .green : .red)
                                        .font(.caption)
                                    Label("Active", systemImage: s.isRuntimeActive ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(s.isRuntimeActive ? .green : .secondary)
                                        .font(.caption)
                                }
                                if let err = s.verificationError {
                                    Text("Verification failed: \(err)")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .textSelection(.enabled)
                                } else if s.isRuntimeActive {
                                    Text("HTTP and HTTPS forwarding active (80→8080, 443→8443).")
                                        .font(.caption)
                                } else {
                                    Text("Forwarding not active. URLs will continue using :8080 / :8443.")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    Text("Run setup in Terminal to use port-free URLs (`http://site.test`, `https://site.test`). If networking breaks, run revert.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Setup:")
                            .font(.caption2)
                            .fontWeight(.medium)
                        HStack {
                            Text(PortForwardingService.shared.setupCommand)
                                .font(.system(size: 9, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(6)
                                .padding(6)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(4)
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(PortForwardingService.shared.setupCommand, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                            .help("Copy setup command")
                        }
                        Text("Revert (if networking breaks):")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.top, 4)
                        HStack {
                            Text(PortForwardingService.shared.revertCommand)
                                .font(.system(size: 9, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(2)
                                .padding(6)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(4)
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(PortForwardingService.shared.revertCommand, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                            .help("Copy revert command")
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        } // ScrollView
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshDNSStatus()
            refreshMkcertStatus()
            refreshPortForwardingStatus()
        }
    }

    private func refreshMkcertStatus() {
        DispatchQueue.main.async { mkcertCAStatus = nil }
        DispatchQueue.global(qos: .userInitiated).async {
            let status = MkcertService.shared.checkCAStatus()
            DispatchQueue.main.async {
                mkcertCAStatus = status
            }
        }
    }

    private func refreshDNSStatus() {
        DispatchQueue.main.async { dnsStatus = nil }
        DispatchQueue.global(qos: .userInitiated).async {
            let current = DnsmasqService.shared.status
            DispatchQueue.main.async {
                dnsStatus = current
            }
        }
    }

    private func refreshPortForwardingStatus() {
        DispatchQueue.main.async { portForwardingStatus = nil }
        DispatchQueue.global(qos: .userInitiated).async {
            let current = PortForwardingService.shared.status
            DispatchQueue.main.async {
                portForwardingStatus = current
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct ComponentRowView: View {
    let component: ComponentInfo

    var body: some View {
        HStack {
            Image(systemName: component.isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(component.isInstalled ? .green : (component.name.isRequired ? .red : .orange))

            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text(component.name.displayName).fontWeight(.medium)
                    if !component.name.isRequired {
                        Text("optional")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
                Text(component.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !component.isInstalled {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(component.installCommand, forType: .string)
                }) {
                    Label("Copy", systemImage: "doc.on.doc").font(.caption)
                }
                .help(component.installCommand)
            }
        }
        .padding(.vertical, 4)
    }
}
