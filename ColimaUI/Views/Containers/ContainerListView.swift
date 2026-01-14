import SwiftUI

/// List of containers with optional group filtering
struct ContainerListView: View {
    @Bindable var viewModel: AppViewModel
    let filterGroup: String?

    @State private var selectedContainer: Container?
    @State private var showLogs = false
    @State private var showDetails = false
    @State private var showRemoveAlert = false
    @State private var containerToRemove: Container?
    @State private var searchText = ""
    @State private var statusFilter: StatusFilter = .all
    @FocusState private var isSearchFocused: Bool

    enum StatusFilter: String, CaseIterable {
        case all = "All"
        case running = "Running"
        case stopped = "Stopped"
    }

    private var filteredContainers: [Container] {
        var containers = viewModel.docker.containers

        if let group = filterGroup {
            containers = containers.filter { $0.groupName == group }
        }

        // Apply status filter
        switch statusFilter {
        case .running:
            containers = containers.filter { $0.isRunning }
        case .stopped:
            containers = containers.filter { !$0.isRunning }
        case .all:
            break
        }

        if !searchText.isEmpty {
            containers = containers.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.Image.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Sort: running first, then by name
        return containers.sorted { a, b in
            if a.isRunning != b.isRunning {
                return a.isRunning
            }
            return a.name < b.name
        }
    }

    private var title: String {
        filterGroup ?? "All Containers"
    }

    private var runningCount: Int {
        filteredContainers.filter { $0.isRunning }.count
    }

    @State private var isComposeLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Theme.textPrimary)

                        HStack(spacing: 12) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Theme.statusRunning)
                                    .frame(width: 8, height: 8)
                                Text("\(runningCount) running")
                                    .font(.subheadline)
                                    .foregroundColor(Theme.textSecondary)
                            }

                            Text("·")
                                .foregroundColor(Theme.textMuted)

                            Text("\(filteredContainers.count) total")
                                .font(.subheadline)
                                .foregroundColor(Theme.textMuted)
                        }
                    }

                    Spacer()

                    // Refresh button
                    Button {
                        Task {
                            await viewModel.docker.refreshContainers()
                            await viewModel.docker.refreshStats()
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

                    // Compose controls for group views
                    if let group = filterGroup, viewModel.docker.composeDir(forGroup: group) != nil {
                        composeControls(for: group)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Search and filter bar
            HStack(spacing: 12) {
                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Theme.textMuted)
                        .font(.system(size: 12))

                    TextField("Search...", text: $searchText)
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

                // Status filter chips
                HStack(spacing: 4) {
                    ForEach(StatusFilter.allCases, id: \.self) { filter in
                        FilterChip(
                            label: filter.rawValue,
                            isSelected: statusFilter == filter
                        ) {
                            statusFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Container list
            if filteredContainers.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredContainers) { container in
                            ContainerRowView(
                                container: container,
                                stats: viewModel.docker.stats[container.containerID],
                                compact: false,
                                isLoading: viewModel.docker.loadingContainers.contains(container.containerID),
                                onStart: {
                                    Task { await viewModel.docker.startContainer(container.containerID) }
                                },
                                onStop: {
                                    Task { await viewModel.docker.stopContainer(container.containerID) }
                                },
                                onRestart: {
                                    Task { await viewModel.docker.restartContainer(container.containerID) }
                                },
                                onLogs: {
                                    selectedContainer = container
                                    showLogs = true
                                },
                                onRemove: {
                                    containerToRemove = container
                                    showRemoveAlert = true
                                },
                                onShell: {
                                    Task { await viewModel.docker.openShell(container.containerID) }
                                },
                                onShowDetails: {
                                    selectedContainer = container
                                    showDetails = true
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
        .sheet(isPresented: $showLogs) {
            if let container = selectedContainer {
                ContainerLogsView(container: container, docker: viewModel.docker)
            }
        }
        .overlay {
            if showDetails, let container = selectedContainer {
                ZStack {
                    // Dimmed background - tap to dismiss
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showDetails = false
                            }
                        }

                    // Modal content
                    ContainerDetailView(container: container, docker: viewModel.docker)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
                .onExitCommand {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showDetails = false
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: showDetails)
        .alert("Remove Container", isPresented: $showRemoveAlert, presenting: containerToRemove) { container in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task { await viewModel.docker.removeContainer(container.containerID, force: true) }
            }
        } message: { container in
            Text("Are you sure you want to remove \"\(container.name)\"? This action cannot be undone.")
        }
        .background {
            Button("") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    @ViewBuilder
    private func composeControls(for group: String) -> some View {
        HStack(spacing: 8) {
            // Start all
            Button {
                Task {
                    isComposeLoading = true
                    await viewModel.docker.composeUp(group: group)
                    isComposeLoading = false
                }
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(isComposeLoading)

            // Stop all
            Button {
                Task {
                    isComposeLoading = true
                    await viewModel.docker.composeDown(group: group)
                    isComposeLoading = false
                }
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(isComposeLoading)

            // Restart all
            Button {
                Task {
                    isComposeLoading = true
                    await viewModel.docker.composeRestart(group: group)
                    isComposeLoading = false
                }
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(isComposeLoading)

            if isComposeLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: searchText.isEmpty ? "shippingbox" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(Theme.textMuted)

            if searchText.isEmpty {
                Text("No containers")
                    .font(.headline)
                    .foregroundColor(Theme.textSecondary)

                Text("Start a container to see it here")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
            } else {
                Text("No results")
                    .font(.headline)
                    .foregroundColor(Theme.textSecondary)

                Text("No containers match \"\(searchText)\"")
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

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? Theme.textPrimary : Theme.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContainerListView(viewModel: AppViewModel(), filterGroup: nil)
}
