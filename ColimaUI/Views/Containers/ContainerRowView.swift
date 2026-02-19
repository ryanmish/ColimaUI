import SwiftUI
import AppKit

/// Single container row with status and actions
struct ContainerRowView: View {
    let container: Container
    let stats: ContainerStats?
    var compact: Bool = false
    var isLoading: Bool = false

    var onStart: (() -> Void)? = nil
    var onStop: (() -> Void)? = nil
    var onRestart: (() -> Void)? = nil
    var onLogs: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    var onShell: (() -> Void)? = nil
    var onShowDetails: (() -> Void)? = nil

    @AppStorage("enableContainerDomains") private var enableContainerDomains: Bool = true
    @AppStorage("containerDomainSuffix") private var containerDomainSuffix: String = "colima"
    @AppStorage("preferHTTPSDomains") private var preferHTTPSDomains: Bool = false

    @State private var isHovered = false

    private var primaryDomain: String? {
        guard enableContainerDomains else { return nil }
        return container.primaryLocalDomain(domainSuffix: containerDomainSuffix)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator or loading spinner
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 8, height: 8)
            } else {
                PulsingDot(isActive: container.isRunning)
            }

            // Container info
            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)

                if !compact {
                    Text(container.Image)
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }
            }

            if !compact {
                HStack(spacing: 4) {
                    if let domain = primaryDomain {
                        Button {
                            openDomain(domain)
                        } label: {
                            Text(domain)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(Theme.statusRunning)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.statusRunning.opacity(0.15))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .tooltip("Open \(domain)")
                    }

                    if let ports = container.exposedPorts, !ports.isEmpty {
                        ForEach(ports.prefix(3), id: \.self) { port in
                            Button {
                                if let url = URL(string: "http://localhost:\(port)") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Text(":\(port)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(Theme.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.accent.opacity(0.15))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .tooltip("Open localhost:\(port)")
                        }

                        if ports.count > 3 {
                            Text("+\(ports.count - 3)")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.textMuted)
                        }
                    }
                }
            }

            Spacer()

            // Stats (if running) with animated bars
            if container.isRunning, let stats = stats {
                HStack(spacing: 16) {
                    AnimatedStatBadge(
                        label: "CPU",
                        value: stats.cpuFormatted,
                        percent: stats.cpuPercent,
                        color: stats.cpuPercent > 80 ? Theme.statusWarning : Theme.accent
                    )
                    AnimatedStatBadge(
                        label: "MEM",
                        value: stats.memoryUsed,
                        percent: stats.memPercent,
                        color: stats.memPercent > 80 ? Theme.statusWarning : Theme.statusRunning
                    )
                }
            } else if !container.isRunning {
                Text(container.shortStatus)
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
            }

            // Action buttons (show on hover in non-compact mode)
            if !compact && isHovered {
                HStack(spacing: 4) {
                    if container.isRunning {
                        IconButton(icon: "terminal", tip: "Shell", action: onShell)
                        IconButton(icon: "stop.fill", tip: "Stop", action: onStop)
                        IconButton(icon: "arrow.clockwise", tip: "Restart", action: onRestart)
                    } else {
                        IconButton(icon: "play.fill", tip: "Start", action: onStart)
                        IconButton(icon: "trash", isDestructive: true, tip: "Remove", action: onRemove)
                    }
                    IconButton(icon: "doc.text", tip: "Logs", action: onLogs)
                    IconButton(icon: "info.circle", tip: "Details", action: onShowDetails)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 8 : 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered && !compact ? Color.white.opacity(0.05) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(compact ? Color.clear : Theme.cardBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onShowDetails?()
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if container.isRunning {
                Button {
                    onStop?()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }

                Button {
                    onRestart?()
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }

                Divider()

                Button {
                    onShell?()
                } label: {
                    Label("Open Shell", systemImage: "terminal")
                }
            } else {
                Button {
                    onStart?()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
            }

            Button {
                onLogs?()
            } label: {
                Label("View Logs", systemImage: "doc.text")
            }

            Button {
                onShowDetails?()
            } label: {
                Label("Show Details", systemImage: "info.circle")
            }

            if let domain = primaryDomain {
                Divider()

                Button {
                    openDomain(domain)
                } label: {
                    Label("Open Domain", systemImage: "network")
                }

                Button {
                    copyDomain(domain)
                } label: {
                    Label("Copy Domain URL", systemImage: "doc.on.doc")
                }
            }

            if !container.isRunning {
                Divider()

                Button(role: .destructive) {
                    onRemove?()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
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

struct AnimatedStatBadge: View {
    let label: String
    let value: String
    let percent: Double
    var color: Color = Theme.accent

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.textSecondary)

            AnimatedProgressBar(value: min(percent, 100), color: color)
                .frame(width: 50)
        }
    }
}

struct StatBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
        }
    }
}

struct IconButton: View {
    let icon: String
    var isDestructive: Bool = false
    var tip: String? = nil
    let action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(isDestructive ? .red.opacity(0.8) : Theme.textSecondary)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.08))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .if(tip != nil) { view in
            view.tooltip(tip!)
        }
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    VStack {
        ContainerRowView(
            container: Container(
                containerID: "abc123",
                Names: "homeportd-dev",
                Image: "docker-homeportd",
                State: "running",
                Status: "Up 2 hours",
                Ports: "8080:8080",
                Labels: "",
                CreatedAt: ""
            ),
            stats: ContainerStats(
                Container: "abc123",
                Name: "homeportd-dev",
                CPUPerc: "2.5%",
                MemUsage: "28MiB / 4GiB",
                MemPerc: "0.7%",
                NetIO: "1MB / 2MB",
                BlockIO: "0B / 0B",
                PIDs: "10"
            ),
            compact: false
        )
    }
    .padding()
    .background(Theme.contentBackground)
}
