import Foundation
import Observation

/// Service for interacting with Colima CLI
@MainActor
@Observable
class ColimaService {
    static let shared = ColimaService()

    var vms: [ColimaVM] = []
    var selectedProfile: String = "default"
    var isLoading = false
    var error: String?

    private let shell = ShellExecutor.shared

    private init() {}

    private func colimaPath() async -> String {
        await shell.resolveExecutable("colima")
    }

    // MARK: - Computed Properties

    /// Currently selected VM
    var selectedVM: ColimaVM? {
        vms.first { $0.name == selectedProfile }
    }

    /// Whether any VM is running
    var hasRunningVM: Bool {
        vms.contains { $0.isRunning }
    }

    /// Legacy compatibility - returns selected VM
    var vm: ColimaVM? {
        selectedVM
    }

    // MARK: - Refresh

    /// Fetch all VM profiles
    func refresh() async {
        isLoading = true
        error = nil

        let output = (try? await shell.runCommand(await colimaPath(), arguments: ["list", "--json"])) ?? ""
        let lines = output.split(separator: "\n")

        var newVMs: [ColimaVM] = []
        let decoder = JSONDecoder()

        for line in lines {
            if let data = String(line).data(using: .utf8),
               let vm = try? decoder.decode(ColimaVM.self, from: data) {
                newVMs.append(vm)
            }
        }

        vms = newVMs

        // If selected profile no longer exists, select first available or default
        if !vms.contains(where: { $0.name == selectedProfile }) {
            selectedProfile = vms.first?.name ?? "default"
        }

        isLoading = false
    }

    // MARK: - VM Actions

    /// Start selected VM profile
    func start() async {
        isLoading = true
        error = nil
        ToastManager.shared.show("Starting \(selectedProfile)...", type: .info)

        do {
            _ = try await shell.runCommand(await colimaPath(), arguments: ["start", "--profile", selectedProfile])
            await refresh()
            ToastManager.shared.show("\(selectedProfile) started", type: .success)
        } catch {
            self.error = error.localizedDescription
            ToastManager.shared.show("Failed to start VM", type: .error)
        }

        isLoading = false
    }

    /// Stop selected VM profile
    func stop() async {
        isLoading = true
        error = nil
        ToastManager.shared.show("Stopping \(selectedProfile)...", type: .info)

        do {
            _ = try await shell.runCommand(await colimaPath(), arguments: ["stop", "--profile", selectedProfile])
            await refresh()
            ToastManager.shared.show("\(selectedProfile) stopped", type: .success)
        } catch {
            self.error = error.localizedDescription
            ToastManager.shared.show("Failed to stop VM", type: .error)
        }

        isLoading = false
    }

    /// Restart selected VM profile
    func restart() async {
        isLoading = true
        error = nil
        ToastManager.shared.show("Restarting \(selectedProfile)...", type: .info)

        do {
            _ = try await shell.runCommand(await colimaPath(), arguments: ["restart", "--profile", selectedProfile])
            await refresh()
            ToastManager.shared.show("\(selectedProfile) restarted", type: .success)
        } catch {
            self.error = error.localizedDescription
            ToastManager.shared.show("Failed to restart VM", type: .error)
        }

        isLoading = false
    }

    /// Open SSH session in Terminal for selected profile
    func ssh() async {
        do {
            try await shell.openInTerminal(await colimaPath(), arguments: ["ssh", "--profile", selectedProfile])
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Profile Management

    /// Create a new VM profile
    func createProfile(name: String, cpus: Int = 2, memory: Int = 2, disk: Int = 60) async {
        isLoading = true
        ToastManager.shared.show("Creating \(name)...", type: .info)

        do {
            _ = try await shell.runCommand(
                await colimaPath(),
                arguments: ["start", "--profile", name, "--cpu", "\(cpus)", "--memory", "\(memory)", "--disk", "\(disk)"]
            )
            await refresh()
            selectedProfile = name
            ToastManager.shared.show("\(name) created", type: .success)
        } catch {
            self.error = error.localizedDescription
            ToastManager.shared.show("Failed to create profile", type: .error)
        }

        isLoading = false
    }

    /// Delete a VM profile
    func deleteProfile(_ name: String) async {
        // Don't allow deleting if it's the only profile
        guard vms.count > 1 else {
            ToastManager.shared.show("Cannot delete only profile", type: .error)
            return
        }

        // Don't allow deleting running profile
        if let vm = vms.first(where: { $0.name == name }), vm.isRunning {
            ToastManager.shared.show("Stop VM before deleting", type: .error)
            return
        }

        isLoading = true
        ToastManager.shared.show("Deleting \(name)...", type: .info)

        do {
            _ = try await shell.runCommand(await colimaPath(), arguments: ["delete", "--profile", name, "--force"])

            // If we deleted the selected profile, switch to another
            if selectedProfile == name {
                selectedProfile = vms.first { $0.name != name }?.name ?? "default"
            }

            await refresh()
            ToastManager.shared.show("\(name) deleted", type: .success)
        } catch {
            self.error = error.localizedDescription
            ToastManager.shared.show("Failed to delete profile", type: .error)
        }

        isLoading = false
    }

    // MARK: - Legacy Methods (for compatibility)

    /// Start with specific profile (legacy)
    func start(profile: String) async {
        let previousProfile = selectedProfile
        selectedProfile = profile
        await start()
        if selectedVM == nil {
            selectedProfile = previousProfile
        }
    }

    /// Stop with specific profile (legacy)
    func stop(profile: String) async {
        let previousProfile = selectedProfile
        selectedProfile = profile
        await stop()
        selectedProfile = previousProfile
    }

    /// Restart with specific profile (legacy)
    func restart(profile: String) async {
        let previousProfile = selectedProfile
        selectedProfile = profile
        await restart()
        selectedProfile = previousProfile
    }

    /// SSH with specific profile (legacy)
    func ssh(profile: String) async {
        let previousProfile = selectedProfile
        selectedProfile = profile
        await ssh()
        selectedProfile = previousProfile
    }

    /// Delete with specific profile (legacy)
    func delete(profile: String) async {
        await deleteProfile(profile)
    }
}
