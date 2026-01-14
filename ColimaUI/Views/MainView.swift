import SwiftUI

/// Main application view with sidebar navigation
struct MainView: View {
    @State private var viewModel = AppViewModel()
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 200, ideal: Theme.sidebarWidth, max: 280)
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
