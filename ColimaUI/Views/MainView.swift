import SwiftUI

/// Main application view with sidebar navigation
struct MainView: View {
    @State private var viewModel = AppViewModel()

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 320, ideal: Theme.sidebarWidth, max: 380)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.contentBackground)
                .ignoresSafeArea(edges: .top)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .withToasts()
        .task {
            await viewModel.loadInitialData()
        }
        .onDisappear {
            viewModel.stopRefreshLoop()
        }
        .overlay(alignment: .top) {
            if let activeError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.statusWarning)
                    Text(activeError)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(2)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.colima.error = nil
                        viewModel.docker.error = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.orange.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                )
                .cornerRadius(8)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
        // Keyboard shortcuts
        .background {
            Button("Refresh") {
                Task {
                    await viewModel.docker.refreshContainers()
                    await viewModel.docker.refreshStats()
                    ToastManager.shared.show("Refreshed", type: .info)
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .hidden()
        }
    }

    private var activeError: String? {
        viewModel.colima.error ?? viewModel.docker.error
    }

    @ViewBuilder
    private var detailView: some View {
        switch viewModel.selectedDestination {
        case .dashboard:
            DashboardView(viewModel: viewModel)
                .id("dashboard")
        case .containers(let group):
            ContainerListView(viewModel: viewModel, filterGroup: group)
                .id("containers-\(group ?? "all")")
        case .images:
            ImageListView(viewModel: viewModel)
                .id("images")
        case .volumes:
            VolumeListView(viewModel: viewModel)
                .id("volumes")
        case .cleanup:
            CleanupView(viewModel: viewModel)
                .id("cleanup")
        case .settings:
            SettingsView()
                .id("settings")
        }
    }
}

#Preview {
    MainView()
}
