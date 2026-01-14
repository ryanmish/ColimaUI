import Foundation

/// Represents a Docker container
/// Parsed from `docker ps -a --format "{{json .}}"`
struct Container: Codable, Identifiable {
    let containerID: String
    let Names: String
    let Image: String
    let State: String
    let Status: String
    let Ports: String
    let Labels: String
    let CreatedAt: String

    var id: String { containerID }

    enum CodingKeys: String, CodingKey {
        case containerID = "ID"
        case Names, Image, State, Status, Ports, Labels, CreatedAt
    }

    var name: String { Names }

    var isRunning: Bool {
        State.lowercased() == "running"
    }

    /// Extract docker-compose project from labels
    var composeProject: String? {
        extractLabel("com.docker.compose.project")
    }

    /// Extract docker-compose working directory from labels
    var composeWorkingDir: String? {
        extractLabel("com.docker.compose.project.working_dir")
    }

    /// Extract a label value by key
    private func extractLabel(_ key: String) -> String? {
        let pairs = Labels.split(separator: ",")
        for pair in pairs {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 && kv[0] == key {
                return String(kv[1])
            }
        }
        return nil
    }

    /// Friendly group name based on compose project
    var groupName: String {
        guard let project = composeProject else { return "Other" }

        // Map known projects to friendly names
        if project == "docker" {
            return "Homeport"
        } else if project.contains("manifold") || project.starts(with: "fm_") {
            return "Manifold"
        } else {
            return project.capitalized
        }
    }

    /// Short status for display
    var shortStatus: String {
        if isRunning {
            // Extract uptime like "Up 23 hours"
            if let range = Status.range(of: "Up ") {
                return String(Status[range.upperBound...])
            }
            return "Running"
        } else {
            return "Stopped"
        }
    }

    /// Extract exposed host ports from Ports string
    /// Format is like "0.0.0.0:8080->80/tcp, 0.0.0.0:443->443/tcp"
    var exposedPorts: [String]? {
        guard !Ports.isEmpty else { return nil }

        var ports: [String] = []
        let mappings = Ports.split(separator: ",")

        for mapping in mappings {
            let trimmed = mapping.trimmingCharacters(in: .whitespaces)
            // Look for host:port->container pattern
            if let arrowRange = trimmed.range(of: "->") {
                let hostPart = String(trimmed[..<arrowRange.lowerBound])
                // Extract port from "0.0.0.0:8080" or ":::8080"
                if let colonRange = hostPart.range(of: ":", options: .backwards) {
                    let port = String(hostPart[colonRange.upperBound...])
                    if !port.isEmpty && !ports.contains(port) {
                        ports.append(port)
                    }
                }
            }
        }

        return ports.isEmpty ? nil : ports
    }
}
