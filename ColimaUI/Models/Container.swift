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

    /// Extract docker-compose service from labels
    var composeService: String? {
        extractLabel("com.docker.compose.service")
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

    /// Build local domain candidates for this container.
    /// Compose containers prefer service.project.<suffix>, then container-name.<suffix>.
    func localDomains(domainSuffix: String, additionalDomains: [String] = []) -> [String] {
        let suffix = Self.normalizeDomainSuffix(domainSuffix)
        guard !suffix.isEmpty else { return [] }

        var domains: [String] = []

        if let service = composeService,
           let project = composeProject,
           let serviceLabel = Self.normalizeDomainLabel(service),
           let projectLabel = Self.normalizeDomainLabel(project) {
            domains.append("\(serviceLabel).\(projectLabel).\(suffix)")
        }

        if let containerLabel = Self.normalizeDomainLabel(name) {
            domains.append("\(containerLabel).\(suffix)")
        }

        let labelDomains = Self.parseDomainCSV(extractLabel("dev.colimaui.domains"))
        for domain in labelDomains {
            if let normalized = Self.normalizeFullDomain(domain) {
                domains.append(normalized)
            }
        }

        for domain in additionalDomains {
            if let normalized = Self.normalizeFullDomain(domain) {
                domains.append(normalized)
            }
        }

        return Self.unique(domains)
    }

    func primaryLocalDomain(domainSuffix: String, additionalDomains: [String] = []) -> String? {
        localDomains(domainSuffix: domainSuffix, additionalDomains: additionalDomains)
            .first(where: { !Self.isWildcardDomain($0) })
    }

    static func customDomains(from labels: [String: String]?) -> [String] {
        guard let labels else { return [] }
        let keys = [
            "dev.colimaui.domains"
        ]

        var domains: [String] = []
        for key in keys {
            domains.append(contentsOf: parseDomainCSV(labels[key]))
        }

        return unique(domains.compactMap(normalizeFullDomain))
    }

    static func isWildcardDomain(_ value: String) -> Bool {
        value.hasPrefix("*.")
    }

    // MARK: - Domain Helpers

    private static func parseDomainCSV(_ value: String?) -> [String] {
        guard let value else { return [] }
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizeDomainSuffix(_ value: String) -> String {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return normalizeFullDomain(trimmed) ?? ""
    }

    private static func normalizeDomainLabel(_ value: String) -> String? {
        let lowered = value
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")

        let sanitized = lowered.map { char -> Character in
            if char.isLetter || char.isNumber || char == "-" {
                return char
            }
            return "-"
        }

        let label = String(sanitized)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return label.isEmpty ? nil : label
    }

    private static func normalizeFullDomain(_ value: String) -> String? {
        var raw = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let schemeRange = raw.range(of: "://") {
            raw = String(raw[schemeRange.upperBound...])
        }

        if let slashIndex = raw.firstIndex(of: "/") {
            raw = String(raw[..<slashIndex])
        }

        raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if raw.isEmpty {
            return nil
        }

        let wildcard = raw.hasPrefix("*.")
        if raw.contains("*") && !wildcard {
            return nil
        }

        if wildcard {
            raw = String(raw.dropFirst(2))
            if raw.isEmpty {
                return nil
            }
        }

        let labels = raw.split(separator: ".")
        guard !labels.isEmpty else { return nil }

        for label in labels {
            guard normalizeDomainLabel(String(label)) == String(label) else {
                return nil
            }
        }

        return wildcard ? "*.\(raw)" : raw
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
