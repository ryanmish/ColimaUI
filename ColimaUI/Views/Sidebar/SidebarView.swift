import SwiftUI

/// Navigation sidebar with dark glass appearance
struct SidebarView: View {
    @Bindable var viewModel: AppViewModel
    @State private var showCreateProfile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Navigation items
            VStack(alignment: .leading, spacing: 4) {
                Spacer().frame(height: 12)

                // VMs Section
                Text("VMS")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)

                if viewModel.colima.vms.isEmpty {
                    // Empty state
                    VStack(spacing: 8) {
                        Text("No VMs")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMuted)
                        Text("Create a profile to get started")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textMuted.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    ForEach(viewModel.colima.vms) { vm in
                        VMSidebarItem(
                            vm: vm,
                            isSelected: vm.name == viewModel.colima.selectedProfile && viewModel.selectedDestination == .dashboard,
                            onSelect: {
                                viewModel.selectProfile(vm.name)
                                viewModel.selectedDestination = .dashboard
                            },
                            onDelete: {
                                Task { await viewModel.deleteProfile(vm.name) }
                            },
                            canDelete: !vm.isRunning
                        )
                    }
                }

                // New Profile button
                NewProfileButton {
                    showCreateProfile = true
                }

                Divider()
                    .background(Theme.cardBorder)
                    .padding(.vertical, 8)

                Text("CONTAINERS")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)

                // All containers
                SidebarItem(
                    icon: "shippingbox",
                    title: "All",
                    badge: "\(viewModel.totalContainerCount)",
                    isSelected: viewModel.selectedDestination == .containers(group: nil)
                ) {
                    viewModel.selectedDestination = .containers(group: nil)
                }

                // Container groups
                ForEach(viewModel.docker.sortedGroups, id: \.self) { group in
                    let count = viewModel.docker.containersByGroup[group]?.count ?? 0
                    SidebarItem(
                        icon: "folder",
                        title: group,
                        badge: "\(count)",
                        isSelected: viewModel.selectedDestination == .containers(group: group),
                        indent: true
                    ) {
                        viewModel.selectedDestination = .containers(group: group)
                    }
                }

                Divider()
                    .background(Theme.cardBorder)
                    .padding(.vertical, 8)

                SidebarItem(
                    icon: "square.stack.3d.up",
                    title: "Images",
                    isSelected: viewModel.selectedDestination == .images
                ) {
                    viewModel.selectedDestination = .images
                }

                SidebarItem(
                    icon: "externaldrive",
                    title: "Volumes",
                    isSelected: viewModel.selectedDestination == .volumes
                ) {
                    viewModel.selectedDestination = .volumes
                }

                SidebarItem(
                    icon: "trash",
                    title: "Cleanup",
                    isSelected: viewModel.selectedDestination == .cleanup
                ) {
                    viewModel.selectedDestination = .cleanup
                }
            }

            Spacer()

            // Bottom VM control section
            Divider()
                .background(Theme.cardBorder)

            VMControlSection(viewModel: viewModel)
        }
        .background(Color.black.opacity(0.4))
        .background(.ultraThinMaterial.opacity(0.5))
        .sheet(isPresented: $showCreateProfile) {
            CreateProfileSheet(viewModel: viewModel, isPresented: $showCreateProfile)
        }
    }
}

/// VM item in sidebar
struct VMSidebarItem: View {
    let vm: ColimaVM
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let canDelete: Bool

    @State private var isHovered = false
    @State private var showDetails = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var showDeleteConfirmation = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Status dot
                Circle()
                    .fill(vm.isRunning ? Theme.statusRunning : Theme.statusStopped)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(vm.name)
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)

                    if showDetails || isSelected {
                        Text("\(vm.cpus) CPU · \(vm.formattedMemory)")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textMuted)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.white.opacity(0.1) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
            )
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: showDetails)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering in
            isHovered = hovering

            // Cancel any pending hover task
            hoverTask?.cancel()

            if hovering {
                // Delay showing details by 0.5 seconds
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    if !Task.isCancelled {
                        withAnimation(.easeOut(duration: 0.15)) {
                            showDetails = true
                        }
                    }
                }
            } else {
                // Hide immediately
                withAnimation(.easeOut(duration: 0.15)) {
                    showDetails = false
                }
            }
        }
        .contextMenu {
            Button {
                onSelect()
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }

            if canDelete {
                Divider()

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Profile", systemImage: "trash")
                }
            }
        }
        .alert("Delete Profile", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete \"\(vm.name)\"? This cannot be undone.")
        }
    }
}

/// Individual sidebar navigation item
struct SidebarItem: View {
    let icon: String
    let title: String
    var badge: String? = nil
    var isSelected: Bool
    var indent: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)

                Spacer()

                if let badge = badge {
                    Text(badge)
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.cardBackground)
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.leading, indent ? 12 : 0)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.white.opacity(0.1) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// New profile button with hover state
struct NewProfileButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 8)

                Text("New Profile")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textMuted)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.white.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Bottom section with help and settings
struct VMControlSection: View {
    @Bindable var viewModel: AppViewModel
    @State private var settingsHovered = false
    @State private var helpHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Spacer()

            // Help button
            Button {
                if let url = URL(string: "https://github.com/ryanmish/ColimaUI/discussions") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 11))
                    .foregroundColor(helpHovered ? Theme.textSecondary : Theme.textMuted)
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(helpHovered ? 0.12 : 0.06))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .onHover { helpHovered = $0 }
            .tooltip("Help & Discussions")

            // Settings button
            Button {
                viewModel.selectedDestination = .settings
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 11))
                    .foregroundColor(settingsHovered ? Theme.textSecondary : Theme.textMuted)
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(settingsHovered ? 0.12 : 0.06))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .onHover { settingsHovered = $0 }
            .tooltip("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    SidebarView(viewModel: AppViewModel())
        .frame(width: 220, height: 500)
}
