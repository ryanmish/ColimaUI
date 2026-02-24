import SwiftUI
import AppKit

/// Detailed container information panel
struct ContainerDetailView: View {
    let container: Container
    let docker: DockerService
    @Environment(\.dismiss) private var dismiss

    @State private var detail: ContainerDetail?
    @State private var isLoading = true
    @State private var selectedTab = 0
    @State private var showLogs = false

    @AppStorage("enableContainerDomains") private var enableContainerDomains: Bool = true
    @AppStorage("preferHTTPSDomains") private var preferHTTPSDomains: Bool = false

    var body: some View {
        ZStack {
            // Solid background that renders immediately
            Color(hex: "1a1a1a")

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(container.isRunning ? Theme.statusRunning : Theme.statusStopped)
                                .frame(width: 10, height: 10)

                            Text(container.name)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                        }

                        Text(container.Image)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMuted)
                    }

                    Spacer()

                    // Quick actions
                    HStack(spacing: 8) {
                        if container.isRunning {
                            ActionButton(icon: "terminal", label: "Shell") {
                                Task { await docker.openShell(container.containerID) }
                            }
                        }

                        ActionButton(icon: "doc.text", label: "Logs") {
                            showLogs = true
                        }

                        if container.isRunning {
                            ActionButton(icon: "stop.fill", label: "Stop") {
                                Task { await docker.stopContainer(container.containerID) }
                            }
                        } else {
                            ActionButton(icon: "play.fill", label: "Start") {
                                Task { await docker.startContainer(container.containerID) }
                            }
                        }
                    }
                }
                .padding(20)
                .background(Color.black.opacity(0.3))

                // Tab selector
                HStack(spacing: 0) {
                    TabButton(title: "Overview", index: 0, selected: $selectedTab)
                    TabButton(title: "Ports", index: 1, selected: $selectedTab)
                    TabButton(title: "Volumes", index: 2, selected: $selectedTab)
                    TabButton(title: "Environment", index: 3, selected: $selectedTab)
                    TabButton(title: "Network", index: 4, selected: $selectedTab)
                    Spacer()
                }
                .background(Color.black.opacity(0.3))

                // Content
                if isLoading {
                    VStack(spacing: 16) {
                        Spacer()
                        ProgressView()
                            .controlSize(.regular)
                        Text("Loading container details...")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let detail = detail {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            switch selectedTab {
                            case 0: overviewTab(detail)
                            case 1: portsTab(detail)
                            case 2: volumesTab(detail)
                            case 3: environmentTab(detail)
                            case 4: networkTab(detail)
                            default: EmptyView()
                            }
                        }
                        .padding(20)
                    }
                } else {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.statusWarning)
                        Text("Failed to load container details")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text("Try again from the container list.")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 650, height: 550)
        .task {
            detail = await docker.inspectContainer(container.containerID)
            isLoading = false
        }
        .sheet(isPresented: $showLogs) {
            ContainerLogsView(container: container, docker: docker)
        }
    }

    @ViewBuilder
    private func overviewTab(_ detail: ContainerDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailSection(title: "General") {
                HStack {
                    Text("Container ID")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textMuted)
                        .frame(width: 100, alignment: .leading)

                    Text(String(detail.id.prefix(12)))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)

                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(detail.id, forType: .string)
                        ToastManager.shared.show("Container ID copied", type: .success)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .tooltip("Copy full ID")
                }
                DetailRow(label: "Image", value: detail.config.image)
                DetailRow(label: "Status", value: detail.state.status.capitalized)
                DetailRow(label: "Hostname", value: detail.config.hostname)
                if !detail.config.workingDir.isEmpty {
                    DetailRow(label: "Working Dir", value: detail.config.workingDir)
                }
            }

            if let cmd = detail.config.cmd, !cmd.isEmpty {
                DetailSection(title: "Command") {
                    Text(cmd.joined(separator: " "))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                }
            }

            if let entrypoint = detail.config.entrypoint, !entrypoint.isEmpty {
                DetailSection(title: "Entrypoint") {
                    Text(entrypoint.joined(separator: " "))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                }
            }

            if let restartPolicy = detail.hostConfig.restartPolicy {
                DetailSection(title: "Restart Policy") {
                    DetailRow(label: "Policy", value: restartPolicy.name.isEmpty ? "no" : restartPolicy.name)
                }
            }
        }
    }

    @ViewBuilder
    private func portsTab(_ detail: ContainerDetail) -> some View {
        let customDomains = Container.customDomains(from: detail.config.labels)
        let localDomains = enableContainerDomains
            ? container.localDomains(domainSuffix: LocalDomainDefaults.suffix, additionalDomains: customDomains)
            : []

        VStack(alignment: .leading, spacing: 16) {
            if !localDomains.isEmpty {
                DetailSection(title: "Local Domains") {
                    ForEach(localDomains, id: \.self) { domain in
                        HStack(spacing: 10) {
                            Text(domain)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(Theme.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            if !Container.isWildcardDomain(domain) {
                                Button {
                                    openDomain(domain)
                                } label: {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 12))
                                        .foregroundColor(Theme.textSecondary)
                                        .padding(6)
                                        .background(Color.white.opacity(0.06))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                .tooltip("Open \(domain)")
                            }

                            Button {
                                copyDomain(domain)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.textMuted)
                                    .padding(6)
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .tooltip("Copy URL")
                        }
                    }
                }
            }

            if let ports = detail.networkSettings.ports, !ports.isEmpty {
                let mappedPorts = ports.compactMap { (containerPort, bindings) -> (String, String)? in
                    guard let binding = bindings?.first else { return nil }
                    return (binding.hostPort, containerPort)
                }

                if mappedPorts.isEmpty {
                    if localDomains.isEmpty {
                        emptyState(icon: "network", message: "No port mappings configured")
                    }
                } else {
                    DetailSection(title: "Port Mappings") {
                        ForEach(mappedPorts, id: \.0) { hostPort, containerPort in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("localhost:\(hostPort)")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundColor(Theme.textPrimary)

                                    Text("Container port \(containerPort)")
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.textMuted)
                                }

                                Spacer()

                                Button {
                                    if let url = URL(string: "http://localhost:\(hostPort)") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 12))
                                        .foregroundColor(Theme.textSecondary)
                                        .padding(6)
                                        .background(Color.white.opacity(0.06))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(8)
                        }
                    }
                }
            } else {
                if localDomains.isEmpty {
                    emptyState(icon: "network", message: "No port mappings configured")
                }
            }
        }
    }

    @ViewBuilder
    private func volumesTab(_ detail: ContainerDetail) -> some View {
        if detail.mounts.isEmpty {
            emptyState(icon: "externaldrive", message: "No volumes mounted")
        } else {
            ForEach(detail.mounts, id: \.destination) { mount in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: mount.type == "bind" ? "folder" : "externaldrive")
                            .foregroundColor(Theme.textMuted)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mount.destination)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(Theme.textPrimary)

                            Text(mount.source)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Theme.textMuted)
                                .lineLimit(1)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Text(mount.type)
                                .font(.system(size: 10))
                                .foregroundColor(Theme.textMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(4)

                            Text(mount.rw ? "rw" : "ro")
                                .font(.system(size: 10))
                                .foregroundColor(mount.rw ? Theme.textMuted : Theme.statusWarning)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.03))
                .cornerRadius(8)
            }
        }
    }

    @ViewBuilder
    private func environmentTab(_ detail: ContainerDetail) -> some View {
        if let env = detail.config.env, !env.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(env, id: \.self) { variable in
                    let parts = variable.split(separator: "=", maxSplits: 1)
                    let key = String(parts.first ?? "")
                    let value = parts.count > 1 ? String(parts[1]) : ""

                    HStack(alignment: .top, spacing: 8) {
                        Text(key)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.textPrimary)
                            .frame(minWidth: 120, alignment: .leading)

                        Text(value)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(2)

                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(value, forType: .string)
                            ToastManager.shared.show("Copied", type: .success)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(6)
                }
            }
        } else {
            emptyState(icon: "list.bullet", message: "No environment variables")
        }
    }

    @ViewBuilder
    private func networkTab(_ detail: ContainerDetail) -> some View {
        if let networks = detail.networkSettings.networks, !networks.isEmpty {
            ForEach(Array(networks.keys), id: \.self) { networkName in
                if let network = networks[networkName] {
                    DetailSection(title: networkName) {
                        if !network.ipAddress.isEmpty {
                            DetailRow(label: "IP Address", value: network.ipAddress)
                        }
                        if !network.gateway.isEmpty {
                            DetailRow(label: "Gateway", value: network.gateway)
                        }
                        if !network.macAddress.isEmpty {
                            DetailRow(label: "MAC Address", value: network.macAddress)
                        }
                    }
                }
            }
        } else {
            emptyState(icon: "network", message: "No network configuration")
        }
    }

    @ViewBuilder
    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(Theme.textMuted)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(Theme.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func openDomain(_ domain: String) {
        let scheme = preferHTTPSDomains ? "https" : "http"
        if let url = URL(string: "\(scheme)://\(domain)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func copyDomain(_ domain: String) {
        let scheme = preferHTTPSDomains ? "https" : "http"
        let url = "\(scheme)://\(domain)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        ToastManager.shared.show("Copied \(url)", type: .success)
    }
}

// MARK: - Supporting Views

struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundColor(Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct TabButton: View {
    let title: String
    let index: Int
    @Binding var selected: Int
    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selected = index
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: selected == index ? .medium : .regular))
                .foregroundColor(selected == index ? Theme.textPrimary : (isHovered ? Theme.textSecondary : Theme.textMuted))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(selected == index ? Theme.accent : Color.clear)
                            .frame(height: 2)
                    }
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(selected == index ? [.isSelected] : [])
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textMuted)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(12)
            .background(Color.white.opacity(0.03))
            .cornerRadius(8)
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Theme.textMuted)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Theme.textPrimary)

            Spacer()
        }
    }
}

#Preview {
    ContainerDetailView(
        container: Container(
            containerID: "abc123",
            Names: "test-container",
            Image: "nginx:latest",
            State: "running",
            Status: "Up 2 hours",
            Ports: "80/tcp",
            Labels: "",
            CreatedAt: "2024-01-01"
        ),
        docker: DockerService.shared
    )
}
