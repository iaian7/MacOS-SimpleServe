import SwiftUI

struct SiteRowView: View {
    let site: Site
    let onEdit: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject var siteManager: SiteManager
    @EnvironmentObject var appSettings: AppSettings

    private var canOpenInBrowser: Bool {
        site.isActive && DnsmasqService.shared.isResolverConfigured
    }

    private var openInBrowserHelp: String {
        DnsmasqService.shared.isResolverConfigured ? "Open in browser" : "Configure .test DNS first"
    }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { site.isActive },
                set: { _ in
                    DispatchQueue.main.async { siteManager.toggleSite(site) }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(site.domain)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(site.isActive ? .primary : .secondary)
                Text(site.folderPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            HStack(spacing: 6) {
                Button(action: openInBrowser) {
                    Image(systemName: "safari")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help(openInBrowserHelp)
                .disabled(!canOpenInBrowser)

                Button(action: openInFinder) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Open in Finder")

                Button(action: onEdit) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Edit site settings")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .contextMenu {
            Button("Delete Site", role: .destructive, action: onDelete)
        }
    }

    private func openInBrowser() {
        let urlString = SiteURLResolver.shared.urlString(for: site)
        guard let url = URL(string: urlString) else { return }

        // Ensure dnsmasq is running; if not, start it and wait briefly
        if !DnsmasqService.shared.isDnsmasqRunning {
            DnsmasqService.shared.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                openURL(url)
            }
        } else {
            openURL(url)
        }
    }

    private func openURL(_ url: URL) {
        switch appSettings.preferredBrowser {
        case .default:
            NSWorkspace.shared.open(url)
        case .safari, .chrome, .firefox:
            if let appURL = appSettings.preferredBrowser.appURL {
                NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func openInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: site.folderPath)
    }
}
