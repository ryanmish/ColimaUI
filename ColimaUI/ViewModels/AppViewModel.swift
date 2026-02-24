import Foundation
import SwiftUI

/// Navigation destinations
enum NavigationDestination: Hashable {
    case dashboard
    case containers(group: String?)
    case images
    case volumes
    case cleanup
    case settings
}

/// Main application state coordinator
@MainActor
@Observable
class AppViewModel {
    // Services
    let colima = ColimaService.shared
    let docker = DockerService.shared

    // Navigation
    var selectedDestination: NavigationDestination = .dashboard

    // Refresh timer
    private var refreshTask: Task<Void, Never>?

    init() {
        startRefreshLoop()
    }

    /// Initial data load - runs all fetches in parallel
    func loadInitialData() async {
        async let colimaTask: () = colima.refresh()
        async let containersTask: () = docker.refreshContainers()
        async let statsTask: () = docker.refreshStats()
        async let diskTask: () = docker.refreshDiskUsage()

        // Wait for all to complete
        _ = await (colimaTask, containersTask, statsTask, diskTask)
    }

    /// Start periodic refresh
    func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await refreshData()
                let configuredInterval = UserDefaults.standard.double(forKey: "refreshInterval")
                let interval = configuredInterval > 0 ? configuredInterval : 2.0
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Stop periodic refresh
    func stopRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Refresh all data - runs in parallel
    private func refreshData() async {
        async let colimaTask: () = colima.refresh()
        async let containersTask: () = docker.refreshContainers()
        async let statsTask: () = docker.refreshStats()

        _ = await (colimaTask, containersTask, statsTask)
    }

    /// Refresh images and disk usage (on-demand) - runs in parallel
    func refreshImagesAndDisk() async {
        async let imagesTask: () = docker.refreshImages()
        async let diskTask: () = docker.refreshDiskUsage()

        _ = await (imagesTask, diskTask)
    }

    // MARK: - Computed Properties

    var isVMRunning: Bool {
        colima.selectedVM?.isRunning ?? false
    }

    var anyVMRunning: Bool {
        colima.hasRunningVM
    }

    var runningContainerCount: Int {
        docker.containers.filter { $0.isRunning }.count
    }

    var totalContainerCount: Int {
        docker.containers.count
    }

    /// Total CPU usage across all containers
    var totalCPU: Double {
        docker.stats.values.reduce(0) { $0 + $1.cpuPercent }
    }

    /// Total memory usage across all containers
    var totalMemory: Double {
        docker.stats.values.reduce(0) { $0 + $1.memPercent }
    }

    // MARK: - Actions

    func startVM() async {
        await colima.start()
    }

    func stopVM() async {
        await colima.stop()
    }

    func restartVM() async {
        await colima.restart()
    }

    func openSSH() async {
        await colima.ssh()
    }

    // MARK: - Profile Management

    func selectProfile(_ name: String) {
        colima.selectedProfile = name
    }

    func createProfile(name: String, cpus: Int, memory: Int, disk: Int) async {
        await colima.createProfile(name: name, cpus: cpus, memory: memory, disk: disk)
    }

    func deleteProfile(_ name: String) async {
        await colima.deleteProfile(name)
    }
}
