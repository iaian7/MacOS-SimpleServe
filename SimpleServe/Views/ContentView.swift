import SwiftUI

struct ContentView: View {
    @EnvironmentObject var siteManager: SiteManager
    @State private var showingAddSite = false
    @State private var editingSite: Site?
    @State private var resolverWarningDismissed = false
    /// Mirrors serverStatus; updated via NotificationCenter so the popover refreshes even when @EnvironmentObject observation fails
    @State private var displayedServerStatus: ServerRunStatus = .unknown

    private var resolverMissing: Bool {
        !DnsmasqService.shared.isResolverConfigured && !resolverWarningDismissed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SimpleServe")
                    .font(.headline)
                    .fontWeight(.semibold)

                // Server status indicator
                serverStatusBadge

                Spacer()

                // Restart button (shows spinner while restarting)
                Button(action: {
                    siteManager.restartServers()
                }) {
                    if displayedServerStatus == .unknown {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)
                .help("Restart all servers")
                .disabled(displayedServerStatus == .unknown)

                Button(action: { showingAddSite = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Add new site")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Resolver warning banner
            if resolverMissing {
                resolverWarningBanner
            }

            // Error banner
            if let error = siteManager.lastError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 12))
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Error")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Spacer()
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(error, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Copy diagnostics")
                        }
                        ScrollView {
                            Text(error)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
            }

            Divider()

            if siteManager.sites.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No sites configured")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Click + to add your first site")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(siteManager.sites) { site in
                            SiteRowView(
                                site: site,
                                onEdit: { editingSite = site },
                                onDelete: { siteManager.removeSite(site) }
                            )
                        }
                    }
                }
            }
        }
        .frame(minWidth: 340, maxWidth: 340, minHeight: 200)
        .onAppear { displayedServerStatus = siteManager.serverStatus }
        .onReceive(NotificationCenter.default.publisher(for: .simpleServeServerStatusDidChange)) { _ in
            displayedServerStatus = siteManager.serverStatus
        }
        .sheet(isPresented: $showingAddSite) {
            AddSiteView(mode: .add)
                .environmentObject(siteManager)
        }
        .sheet(item: $editingSite) { site in
            AddSiteView(mode: .edit(site))
                .environmentObject(siteManager)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var serverStatusBadge: some View {
        switch displayedServerStatus {
        case .running:
            Label("Running", systemImage: "circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
                .labelStyle(StatusLabelStyle())
        case .stopped:
            Label("Stopped", systemImage: "circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
                .labelStyle(StatusLabelStyle())
        case .error:
            Label("Error", systemImage: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
                .labelStyle(StatusLabelStyle())
        case .unknown:
            Label("Checking…", systemImage: "circle.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(StatusLabelStyle())
        }
    }

    private var resolverWarningBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: 12))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(".test domains not routed")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("Run this once in Terminal to enable DNS:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(DnsmasqService.shared.resolverSetupCommand)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                    .cornerRadius(4)
                Text("Until then, use the full URL with port (e.g. https://mysite.test:8443).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(action: { resolverWarningDismissed = true }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.12))
    }
}

// MARK: - Helper Label Style

private struct StatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 7))
            configuration.title
        }
    }
}
