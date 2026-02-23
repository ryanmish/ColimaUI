import Foundation
import Observation

/// Service for interacting with Docker CLI
@MainActor
@Observable
class DockerService {
    static let shared = DockerService()

    var containers: [Container] = []
    var stats: [String: ContainerStats] = [:] // keyed by container ID
    var images: [DockerImage] = []
    var volumes: [DockerVolume] = []
    var diskUsage: DockerDiskUsage = DockerDiskUsage()
    var isLoading = false
    var loadingContainers: Set<String> = [] // Container IDs currently being started/stopped
    var error: String?

    private let shell = ShellExecutor.shared
    private var logProcess: Process?

    private init() {}

    // MARK: - Containers

    /// Fetch all containers
    func refreshContainers() async {
        do {
            let output = try await shell.run("docker ps -a --format \"{{json .}}\"")
            let lines = output.split(separator: "\n")

            var newContainers: [Container] = []
            let decoder = JSONDecoder()

            for line in lines {
                if let data = String(line).data(using: .utf8) {
                    if let container = try? decoder.decode(Container.self, from: data) {
                        newContainers.append(container)
                    }
                }
            }

            containers = newContainers

            if UserDefaults.standard.bool(forKey: "enableContainerDomains") {
                let suffix = UserDefaults.standard.string(forKey: "containerDomainSuffix") ?? "local"
                Task {
                    await LocalDomainService.shared.syncProxyRoutes(suffix: suffix)
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Fetch real-time stats for running containers
    func refreshStats() async {
        do {
            let output = try await shell.run("docker stats --no-stream --format \"{{json .}}\"")
            let lines = output.split(separator: "\n")

            var newStats: [String: ContainerStats] = [:]
            let decoder = JSONDecoder()

            for line in lines {
                if let data = String(line).data(using: .utf8) {
                    if let stat = try? decoder.decode(ContainerStats.self, from: data) {
                        newStats[stat.Container] = stat
                    }
                }
            }

            stats = newStats
        } catch {
            // Stats command may fail if no containers running - not an error
        }
    }

    /// Start a container
    func startContainer(_ id: String) async {
        loadingContainers.insert(id)
        defer { loadingContainers.remove(id) }

        do {
            _ = try await shell.run("docker start \(id)")
            await refreshContainers()
            ToastManager.shared.show("Container started", type: .success)
        } catch {
            self.error = error.localizedDescription
            ToastManager.shared.show("Failed to start container", type: .error)
        }
    }

    /// Stop a container
    func stopContainer(_ id: String) async {
        loadingContainers.insert(id)
        defer { loadingContainers.remove(id) }

        do {
            _ = try await shell.run("docker stop \(id)")
            await refreshContainers()
            ToastManager.shared.show("Container stopped", type: .success)
        } catch {
            self.error = error.localizedDescription
            ToastManager.shared.show("Failed to stop container", type: .error)
        }
    }

    /// Restart a container
    func restartContainer(_ id: String) async {
        loadingContainers.insert(id)
        defer { loadingContainers.remove(id) }

        do {
            _ = try await shell.run("docker restart \(id)")
            await refreshContainers()
            ToastManager.shared.show("Container restarted", type: .success)
        } catch {
            self.error = error.localizedDescription
            ToastManager.shared.show("Failed to restart container", type: .error)
        }
    }

    /// Remove a container
    func removeContainer(_ id: String, force: Bool = false) async {
        do {
            let forceFlag = force ? "-f" : ""
            _ = try await shell.run("docker rm \(forceFlag) \(id)")
            await refreshContainers()
            ToastManager.shared.show("Container removed", type: .success)
        } catch {
            self.error = error.localizedDescription
            ToastManager.shared.show("Failed to remove container", type: .error)
        }
    }

    /// Get detailed container info
    func inspectContainer(_ id: String) async -> ContainerDetail? {
        do {
            let output = try await shell.run("docker inspect \(id)")
            if let data = output.data(using: .utf8) {
                let details = try JSONDecoder().decode([ContainerDetail].self, from: data)
                return details.first
            }
        } catch {
            self.error = error.localizedDescription
        }
        return nil
    }

    /// Open shell in container (opens Terminal)
    func openShell(_ id: String, shell shellType: String = "/bin/sh") async {
        do {
            let script = """
            tell application "Terminal"
                activate
                do script "docker exec -it \(id) \(shellType)"
            end tell
            """
            _ = try await shell.run("osascript -e '\(script)'")
            ToastManager.shared.show("Opening shell...", type: .info)
        } catch {
            self.error = error.localizedDescription
            ToastManager.shared.show("Failed to open shell", type: .error)
        }
    }

    /// Get container logs
    func getLogs(_ id: String, tail: Int = 100) async -> String {
        do {
            return try await shell.run("docker logs --tail \(tail) \(id) 2>&1")
        } catch {
            return "Failed to fetch logs: \(error.localizedDescription)"
        }
    }

    /// Stream container logs (returns Process to allow cancellation)
    func streamLogs(_ id: String, onOutput: @escaping (String) -> Void) async -> Process? {
        do {
            return try await shell.stream("docker logs -f --tail 100 \(id) 2>&1", onOutput: onOutput)
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    // MARK: - Images

    /// Fetch all images
    func refreshImages() async {
        do {
            let output = try await shell.run("docker images --format \"{{json .}}\"")
            let lines = output.split(separator: "\n")

            var newImages: [DockerImage] = []
            let decoder = JSONDecoder()

            for line in lines {
                if let data = String(line).data(using: .utf8) {
                    if let image = try? decoder.decode(DockerImage.self, from: data) {
                        newImages.append(image)
                    }
                }
            }

            // Sort by size descending
            images = newImages.sorted { $0.sizeBytes > $1.sizeBytes }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Remove an image
    func removeImage(_ id: String, force: Bool = false) async {
        do {
            let forceFlag = force ? "-f" : ""
            _ = try await shell.run("docker rmi \(forceFlag) \(id)")
            await refreshImages()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Volumes

    /// Fetch all volumes
    func refreshVolumes() async {
        do {
            let output = try await shell.run("docker volume ls --format \"{{json .}}\"")
            let lines = output.split(separator: "\n")

            var newVolumes: [DockerVolume] = []
            let decoder = JSONDecoder()

            for line in lines {
                if let data = String(line).data(using: .utf8) {
                    if let volume = try? decoder.decode(DockerVolume.self, from: data) {
                        newVolumes.append(volume)
                    }
                }
            }

            volumes = newVolumes.sorted { $0.name < $1.name }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Remove a volume
    func removeVolume(_ name: String, force: Bool = false) async {
        do {
            let forceFlag = force ? "-f" : ""
            _ = try await shell.run("docker volume rm \(forceFlag) \(name)")
            await refreshVolumes()
            ToastManager.shared.show("Volume removed", type: .success)
        } catch {
            self.error = error.localizedDescription
            ToastManager.shared.show("Failed to remove volume", type: .error)
        }
    }

    /// Prune unused volumes
    func pruneVolumes() async -> String {
        do {
            let output = try await shell.run("docker volume prune -f")
            await refreshVolumes()

            if let range = output.range(of: "Total reclaimed space: ") {
                let reclaimed = String(output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                ToastManager.shared.show("Reclaimed \(reclaimed)", type: .success)
                return reclaimed
            }
            ToastManager.shared.show("Volumes pruned", type: .success)
            return "0B"
        } catch {
            ToastManager.shared.show("Prune failed", type: .error)
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Cleanup

    /// Fetch disk usage
    func refreshDiskUsage() async {
        do {
            let output = try await shell.run("docker system df --format \"{{.Type}}|{{.Size}}|{{.Reclaimable}}\"")
            let lines = output.split(separator: "\n")

            var usage = DockerDiskUsage()

            for line in lines {
                let parts = line.split(separator: "|")
                if parts.count >= 2 {
                    let type = String(parts[0])
                    let size = String(parts[1])
                    let reclaimable = parts.count > 2 ? String(parts[2]) : "0B"

                    switch type {
                    case "Images":
                        usage.imagesSize = size
                        usage.imagesReclaimable = reclaimable
                    case "Containers":
                        usage.containersSize = size
                    case "Local Volumes":
                        usage.volumesSize = size
                    case "Build Cache":
                        usage.buildCacheSize = size
                    default:
                        break
                    }
                }
            }

            diskUsage = usage
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Prune dangling images
    func pruneImages() async -> String {
        do {
            let output = try await shell.run("docker image prune -f")
            await refreshImages()
            await refreshDiskUsage()

            // Extract reclaimed space from output
            if let range = output.range(of: "Total reclaimed space: ") {
                let reclaimed = String(output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                ToastManager.shared.show("Reclaimed \(reclaimed)", type: .success)
                return reclaimed
            }
            ToastManager.shared.show("Cleanup complete", type: .success)
            return "0B"
        } catch {
            ToastManager.shared.show("Cleanup failed", type: .error)
            return "Error: \(error.localizedDescription)"
        }
    }

    /// Prune all unused data (aggressive)
    func pruneAll() async -> String {
        do {
            let output = try await shell.run("docker system prune -f")
            await refreshContainers()
            await refreshImages()
            await refreshDiskUsage()

            if let range = output.range(of: "Total reclaimed space: ") {
                let reclaimed = String(output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                ToastManager.shared.show("Reclaimed \(reclaimed)", type: .success)
                return reclaimed
            }
            ToastManager.shared.show("Cleanup complete", type: .success)
            return "0B"
        } catch {
            ToastManager.shared.show("Cleanup failed", type: .error)
            return "Error: \(error.localizedDescription)"
        }
    }

    /// Prune everything including volumes (most aggressive)
    func pruneAllWithVolumes() async -> String {
        do {
            let output = try await shell.run("docker system prune -a --volumes -f")
            await refreshContainers()
            await refreshImages()
            await refreshDiskUsage()

            if let range = output.range(of: "Total reclaimed space: ") {
                let reclaimed = String(output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                ToastManager.shared.show("Reclaimed \(reclaimed)", type: .success)
                return reclaimed
            }
            ToastManager.shared.show("Deep clean complete", type: .success)
            return "0B"
        } catch {
            ToastManager.shared.show("Deep clean failed", type: .error)
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Grouping

    /// Group containers by compose project
    var containersByGroup: [String: [Container]] {
        Dictionary(grouping: containers) { $0.groupName }
    }

    /// Sorted group names
    var sortedGroups: [String] {
        let groups = Array(containersByGroup.keys)
        // Custom sort: Homeport first, Manifold second, Other last
        return groups.sorted { a, b in
            let order = ["Homeport": 0, "Manifold": 1, "Other": 99]
            return (order[a] ?? 50) < (order[b] ?? 50)
        }
    }

    /// Get the compose working directory for a group
    func composeDir(forGroup group: String) -> String? {
        containersByGroup[group]?.first?.composeWorkingDir
    }

    // MARK: - Docker Compose Operations

    /// Start all containers in a compose project
    func composeUp(group: String) async {
        guard let dir = composeDir(forGroup: group) else {
            ToastManager.shared.show("No compose file found", type: .error)
            return
        }

        ToastManager.shared.show("Starting \(group)...", type: .info)
        do {
            _ = try await shell.run("cd \"\(dir)\" && docker compose up -d")
            await refreshContainers()
            ToastManager.shared.show("\(group) started", type: .success)
        } catch {
            ToastManager.shared.show("Failed to start \(group)", type: .error)
        }
    }

    /// Stop all containers in a compose project
    func composeDown(group: String) async {
        guard let dir = composeDir(forGroup: group) else {
            ToastManager.shared.show("No compose file found", type: .error)
            return
        }

        ToastManager.shared.show("Stopping \(group)...", type: .info)
        do {
            _ = try await shell.run("cd \"\(dir)\" && docker compose down")
            await refreshContainers()
            ToastManager.shared.show("\(group) stopped", type: .success)
        } catch {
            ToastManager.shared.show("Failed to stop \(group)", type: .error)
        }
    }

    /// Restart all containers in a compose project
    func composeRestart(group: String) async {
        guard let dir = composeDir(forGroup: group) else {
            ToastManager.shared.show("No compose file found", type: .error)
            return
        }

        ToastManager.shared.show("Restarting \(group)...", type: .info)
        do {
            _ = try await shell.run("cd \"\(dir)\" && docker compose restart")
            await refreshContainers()
            ToastManager.shared.show("\(group) restarted", type: .success)
        } catch {
            ToastManager.shared.show("Failed to restart \(group)", type: .error)
        }
    }

    /// Rebuild images for a compose project
    func composeBuild(group: String) async {
        guard let dir = composeDir(forGroup: group) else {
            ToastManager.shared.show("No compose file found", type: .error)
            return
        }

        ToastManager.shared.show("Building \(group)...", type: .info)
        do {
            _ = try await shell.run("cd \"\(dir)\" && docker compose build")
            ToastManager.shared.show("\(group) built", type: .success)
        } catch {
            ToastManager.shared.show("Build failed", type: .error)
        }
    }
}
