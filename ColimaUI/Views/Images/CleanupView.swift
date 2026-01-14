import SwiftUI

/// Disk cleanup view with prune options
struct CleanupView: View {
    @Bindable var viewModel: AppViewModel

    @State private var isLoading = false
    @State private var lastResult: String?
    @State private var showSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cleanup")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.textPrimary)

                    Text("Free up disk space by removing unused Docker resources")
                        .font(.subheadline)
                        .foregroundColor(Theme.textMuted)
                }

                // Disk usage overview
                VStack(alignment: .leading, spacing: 16) {
                    Text("Disk Usage")
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)

                    VStack(spacing: 12) {
                        DiskUsageRow(
                            icon: "square.stack.3d.up",
                            label: "Images",
                            size: viewModel.docker.diskUsage.imagesSize,
                            reclaimable: viewModel.docker.diskUsage.imagesReclaimable
                        )
                        DiskUsageRow(
                            icon: "shippingbox",
                            label: "Containers",
                            size: viewModel.docker.diskUsage.containersSize
                        )
                        DiskUsageRow(
                            icon: "externaldrive",
                            label: "Volumes",
                            size: viewModel.docker.diskUsage.volumesSize
                        )
                        DiskUsageRow(
                            icon: "hammer",
                            label: "Build Cache",
                            size: viewModel.docker.diskUsage.buildCacheSize
                        )
                    }
                }
                .cardStyle()
                .appearAnimation(delay: 0.05)

                // Cleanup actions
                VStack(alignment: .leading, spacing: 16) {
                    Text("Actions")
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)

                    VStack(spacing: 12) {
                        CleanupActionCard(
                            title: "Clean Dangling Images",
                            description: "Removes orphaned image layers from failed builds. This is always safe to run.",
                            icon: "square.stack.3d.up.trianglebadge.exclamationmark",
                            buttonLabel: "Clean",
                            isLoading: isLoading
                        ) {
                            await performCleanup {
                                await viewModel.docker.pruneImages()
                            }
                        }

                        CleanupActionCard(
                            title: "Clean Unused Resources",
                            description: "Removes stopped containers, unused networks, and dangling images. Running containers are not affected.",
                            icon: "arrow.3.trianglepath",
                            buttonLabel: "Clean",
                            isLoading: isLoading
                        ) {
                            await performCleanup {
                                await viewModel.docker.pruneAll()
                            }
                        }

                        CleanupActionCard(
                            title: "Nuclear Option",
                            description: "Removes everything not actively in use, including volumes. Database data and other persistent storage will be deleted.",
                            icon: "trash.slash",
                            buttonLabel: "Delete All",
                            isDestructive: true,
                            isLoading: isLoading
                        ) {
                            await performCleanup {
                                await viewModel.docker.pruneAllWithVolumes()
                            }
                        }
                    }
                }

                // Animated success result
                if showSuccess, let result = lastResult {
                    SuccessCard(message: "Reclaimed: \(result)") {
                        withAnimation(Theme.animationDefault) {
                            showSuccess = false
                            lastResult = nil
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .padding(24)
        }
        .background(Theme.contentBackground)
        .task {
            await viewModel.docker.refreshDiskUsage()
        }
    }

    private func performCleanup(_ action: () async -> String) async {
        withAnimation(Theme.animationDefault) {
            isLoading = true
            showSuccess = false
            lastResult = nil
        }
        let result = await action()
        withAnimation(Theme.animationSpring) {
            lastResult = result
            showSuccess = true
            isLoading = false
        }
    }
}

/// Animated success card with checkmark
struct SuccessCard: View {
    let message: String
    let onDismiss: () -> Void

    @State private var showCheckmark = false
    @State private var showText = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.statusRunning.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .scaleEffect(showCheckmark ? 1.0 : 0.5)

                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.statusRunning)
                    .scaleEffect(showCheckmark ? 1.0 : 0.0)
                    .rotationEffect(.degrees(showCheckmark ? 0 : -90))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Cleanup Complete")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
            }
            .opacity(showText ? 1 : 0)
            .offset(x: showText ? 0 : -10)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .opacity(showText ? 1 : 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.statusRunning.opacity(0.05))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.statusRunning.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            withAnimation(Theme.animationSpring) {
                showCheckmark = true
            }
            withAnimation(Theme.animationDefault.delay(0.15)) {
                showText = true
            }
        }
    }
}

struct DiskUsageRow: View {
    let icon: String
    let label: String
    let size: String
    var reclaimable: String? = nil

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Theme.textMuted)
                .frame(width: 24)

            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)

            Spacer()

            if let reclaimable = reclaimable, reclaimable != "0B" {
                Text(reclaimable)
                    .font(.caption)
                    .foregroundColor(Theme.statusWarning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.statusWarning.opacity(0.1))
                    .cornerRadius(4)
            }

            Text(size)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
        }
    }
}

struct CleanupActionCard: View {
    let title: String
    let description: String
    let icon: String
    let buttonLabel: String
    var isDestructive: Bool = false
    let isLoading: Bool
    let action: () async -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Simple icon
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(isDestructive ? .red.opacity(0.7) : Theme.textSecondary)
                .frame(width: 28)

            // Text content
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isDestructive ? .red.opacity(0.9) : Theme.textPrimary)

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(2)
            }

            Spacer()

            // Action button
            Button {
                Task { await action() }
            } label: {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 60, height: 28)
                } else {
                    Text(buttonLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isDestructive ? .red.opacity(0.9) : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.06))
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.white.opacity(0.04) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    CleanupView(viewModel: AppViewModel())
}
