import SwiftUI

/// List of Docker volumes
struct VolumeListView: View {
    @Bindable var viewModel: AppViewModel

    @State private var searchText = ""
    @State private var isPruning = false
    @State private var showRemoveAlert = false
    @State private var volumeToRemove: DockerVolume?
    @FocusState private var isSearchFocused: Bool

    private var filteredVolumes: [DockerVolume] {
        if searchText.isEmpty {
            return viewModel.docker.volumes
        }
        return viewModel.docker.volumes.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Volumes")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Theme.textPrimary)

                        Text("\(viewModel.docker.volumes.count) volumes")
                            .font(.subheadline)
                            .foregroundColor(Theme.textMuted)
                    }

                    Spacer()

                    // Refresh button
                    Button {
                        Task {
                            await viewModel.docker.refreshVolumes()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .tooltip("Refresh")

                    // Prune button
                    Button {
                        Task {
                            isPruning = true
                            _ = await viewModel.docker.pruneVolumes()
                            isPruning = false
                        }
                    } label: {
                        if isPruning {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 80)
                        } else {
                            Label("Prune Unused", systemImage: "trash")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(6)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isPruning)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.textMuted)
                    .font(.system(size: 12))

                TextField("Search volumes...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.textMuted)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Volume list
            if filteredVolumes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredVolumes) { volume in
                            VolumeRowView(
                                volume: volume,
                                onRemove: {
                                    volumeToRemove = volume
                                    showRemoveAlert = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(Theme.contentBackground)
        .task {
            await viewModel.docker.refreshVolumes()
        }
        .alert("Remove Volume", isPresented: $showRemoveAlert, presenting: volumeToRemove) { volume in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task { await viewModel.docker.removeVolume(volume.name) }
            }
        } message: { volume in
            Text("Are you sure you want to remove \"\(volume.name)\"? This action cannot be undone.")
        }
        .background {
            Button("") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: searchText.isEmpty ? "externaldrive" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(Theme.textMuted)

            if searchText.isEmpty {
                Text("No volumes")
                    .font(.headline)
                    .foregroundColor(Theme.textSecondary)

                Text("Docker volumes will appear here")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
            } else {
                Text("No results")
                    .font(.headline)
                    .foregroundColor(Theme.textSecondary)

                Text("No volumes match \"\(searchText)\"")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)

                Button("Clear search") {
                    searchText = ""
                }
                .buttonStyle(GlassButtonStyle())
                .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct VolumeRowView: View {
    let volume: DockerVolume
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive")
                .font(.system(size: 16))
                .foregroundColor(Theme.textMuted)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(volume.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                Text(volume.mountpoint)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                Text(volume.driver)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(4)

                if volume.formattedSize != "N/A" {
                    Text(volume.formattedSize)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                }
            }

            if isHovered {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.8))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .tooltip("Remove volume")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.white.opacity(0.05) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
        .onHover { isHovered = $0 }
    }
}

#Preview {
    VolumeListView(viewModel: AppViewModel())
}
