import SwiftUI

/// Main dashboard showing VM status and overview
struct DashboardView: View {
    @Bindable var viewModel: AppViewModel
    @State private var isRefreshing = false
    @State private var showDeleteConfirmation = false

    private var runningContainers: [Container] {
        viewModel.docker.containers.filter(\.isRunning)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with refresh
                HStack {
                    Text("Dashboard")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.textPrimary)

                    Spacer()

                    Button {
                        Task {
                            isRefreshing = true
                            await viewModel.colima.refresh()
                            await viewModel.docker.refreshContainers()
                            await viewModel.docker.refreshStats()
                            await viewModel.docker.refreshDiskUsage()
                            isRefreshing = false
                        }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(isRefreshing)
                }

                // VM Status Card
                vmStatusCard
                    .appearAnimation(delay: 0)

                // Quick Stats
                HStack(spacing: 16) {
                    StatCard(
                        title: "Containers",
                        value: "\(viewModel.runningContainerCount)/\(viewModel.totalContainerCount)",
                        subtitle: "running",
                        icon: "shippingbox"
                    )
                    .appearAnimation(delay: 0.05)

                    StatCard(
                        title: "CPU",
                        value: String(format: "%.1f%%", viewModel.totalCPU),
                        subtitle: "total usage",
                        icon: "cpu"
                    )
                    .appearAnimation(delay: 0.1)

                    StatCard(
                        title: "Memory",
                        value: String(format: "%.1f%%", viewModel.totalMemory),
                        subtitle: "of VM allocation",
                        icon: "memorychip"
                    )
                    .appearAnimation(delay: 0.15)
                }

                // Disk Usage Card
                DiskUsageCard(diskUsage: viewModel.docker.diskUsage)
                    .appearAnimation(delay: 0.2)

                // Running Containers Preview
                if !runningContainers.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "shippingbox")
                                .foregroundColor(Theme.textMuted)
                            Text("Running Containers")
                                .font(.headline)
                                .foregroundColor(Theme.textPrimary)

                            Spacer()

                            Text("\(viewModel.runningContainerCount) active")
                                .font(.caption)
                                .foregroundColor(Theme.statusRunning)
                        }

                        VStack(spacing: 8) {
                            ForEach(Array(runningContainers.prefix(5))) { container in
                                ContainerRowView(
                                    container: container,
                                    stats: viewModel.docker.stats[container.containerID],
                                    compact: true,
                                    isLoading: viewModel.docker.loadingContainers.contains(container.containerID)
                                )
                            }
                        }

                        if runningContainers.count > 5 {
                            Divider()
                                .background(Theme.cardBorder)

                            Button {
                                viewModel.selectedDestination = .containers(group: nil)
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("View all \(viewModel.runningContainerCount) containers")
                                        .font(.caption)
                                        .foregroundColor(Theme.accent)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(Theme.accent)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .cardStyle()
                    .appearAnimation(delay: 0.25)
                }
            }
            .padding(24)
        }
        .background(Theme.contentBackground)
    }

    private var vmStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PulsingDot(isActive: viewModel.isVMRunning)
                    .scaleEffect(1.5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.colima.selectedProfile)
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)

                    Text(viewModel.isVMRunning ? "Running" : "Stopped")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                }

                Spacer()

                if viewModel.colima.vms.count > 1 {
                    Text("\(viewModel.colima.vms.count) profiles")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(4)
                }
            }

            if let vm = viewModel.colima.vm {
                HStack(spacing: 24) {
                    VMStatItem(label: "CPU", value: "\(vm.cpus) cores")
                    VMStatItem(label: "Memory", value: vm.formattedMemory)
                    VMStatItem(label: "Disk", value: vm.formattedDisk)
                    VMStatItem(label: "Arch", value: vm.arch)
                }
            }

            HStack(spacing: 12) {
                if viewModel.isVMRunning {
                    Button("Stop") {
                        Task { await viewModel.stopVM() }
                    }
                    .buttonStyle(GlassButtonStyle())

                    Button("Restart") {
                        Task { await viewModel.restartVM() }
                    }
                    .buttonStyle(GlassButtonStyle())

                    Button("SSH") {
                        Task { await viewModel.openSSH() }
                    }
                    .buttonStyle(GlassButtonStyle())
                } else {
                    Button("Start VM") {
                        Task { await viewModel.startVM() }
                    }
                    .buttonStyle(GlassButtonStyle())

                    Button("Delete") {
                        showDeleteConfirmation = true
                    }
                    .buttonStyle(GlassButtonStyle())
                }

                if viewModel.colima.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .cardStyle()
        .alert("Delete Profile", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteProfile(viewModel.colima.selectedProfile) }
            }
        } message: {
            Text("Are you sure you want to delete \"\(viewModel.colima.selectedProfile)\"? This cannot be undone.")
        }
    }
}

struct VMStatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(Theme.textMuted)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textSecondary)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(Theme.textMuted)
                Text(title)
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
            }

            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(Theme.textPrimary)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

struct DiskUsageCard: View {
    let diskUsage: DockerDiskUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "internaldrive")
                    .foregroundColor(Theme.textMuted)
                Text("Disk Usage")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)

                Spacer()

                if !diskUsage.imagesReclaimable.isEmpty && diskUsage.imagesReclaimable != "0B" {
                    Text("\(diskUsage.imagesReclaimable) reclaimable")
                        .font(.caption)
                        .foregroundColor(Theme.statusWarning)
                }
            }

            HStack(spacing: 24) {
                DiskUsageItem(label: "Images", value: diskUsage.imagesSize, icon: "square.stack.3d.up")
                DiskUsageItem(label: "Containers", value: diskUsage.containersSize, icon: "shippingbox")
                DiskUsageItem(label: "Volumes", value: diskUsage.volumesSize, icon: "cylinder")
                DiskUsageItem(label: "Build Cache", value: diskUsage.buildCacheSize, icon: "hammer")
            }
        }
        .cardStyle()
    }
}

struct DiskUsageItem: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.caption)
            }
            .foregroundColor(Theme.textMuted)

            Text(value.isEmpty ? "0B" : value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
        }
    }
}

#Preview {
    DashboardView(viewModel: AppViewModel())
}
