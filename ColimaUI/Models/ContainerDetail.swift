import Foundation

/// Detailed container info from `docker inspect`
struct ContainerDetail: Codable {
    let id: String
    let name: String
    let image: String
    let state: ContainerState
    let config: ContainerConfig
    let networkSettings: NetworkSettings
    let mounts: [Mount]
    let hostConfig: HostConfig

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case image = "Image"
        case state = "State"
        case config = "Config"
        case networkSettings = "NetworkSettings"
        case mounts = "Mounts"
        case hostConfig = "HostConfig"
    }

    var cleanName: String {
        name.hasPrefix("/") ? String(name.dropFirst()) : name
    }
}

struct ContainerState: Codable {
    let status: String
    let running: Bool
    let startedAt: String
    let finishedAt: String

    enum CodingKeys: String, CodingKey {
        case status = "Status"
        case running = "Running"
        case startedAt = "StartedAt"
        case finishedAt = "FinishedAt"
    }
}

struct ContainerConfig: Codable {
    let hostname: String
    let env: [String]?
    let cmd: [String]?
    let image: String
    let workingDir: String
    let entrypoint: [String]?
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey {
        case hostname = "Hostname"
        case env = "Env"
        case cmd = "Cmd"
        case image = "Image"
        case workingDir = "WorkingDir"
        case entrypoint = "Entrypoint"
        case labels = "Labels"
    }
}

struct NetworkSettings: Codable {
    let ports: [String: [PortBinding]?]?
    let networks: [String: NetworkInfo]?

    enum CodingKeys: String, CodingKey {
        case ports = "Ports"
        case networks = "Networks"
    }
}

struct PortBinding: Codable {
    let hostIP: String
    let hostPort: String

    enum CodingKeys: String, CodingKey {
        case hostIP = "HostIp"
        case hostPort = "HostPort"
    }
}

struct NetworkInfo: Codable {
    let networkID: String
    let ipAddress: String
    let gateway: String
    let macAddress: String

    enum CodingKeys: String, CodingKey {
        case networkID = "NetworkID"
        case ipAddress = "IPAddress"
        case gateway = "Gateway"
        case macAddress = "MacAddress"
    }
}

struct Mount: Codable {
    let type: String
    let source: String
    let destination: String
    let mode: String
    let rw: Bool
    let propagation: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case source = "Source"
        case destination = "Destination"
        case mode = "Mode"
        case rw = "RW"
        case propagation = "Propagation"
        case name = "Name"
    }
}

struct HostConfig: Codable {
    let memory: Int64
    let cpuShares: Int
    let restartPolicy: RestartPolicy?

    enum CodingKeys: String, CodingKey {
        case memory = "Memory"
        case cpuShares = "CpuShares"
        case restartPolicy = "RestartPolicy"
    }
}

struct RestartPolicy: Codable {
    let name: String
    let maximumRetryCount: Int

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case maximumRetryCount = "MaximumRetryCount"
    }
}
