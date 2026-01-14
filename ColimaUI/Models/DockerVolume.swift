import Foundation

/// Docker volume info from `docker volume ls --format "{{json .}}"`
struct DockerVolume: Codable, Identifiable {
    let driver: String
    let labels: String
    let mountpoint: String
    let name: String
    let scope: String
    let size: String

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case driver = "Driver"
        case labels = "Labels"
        case mountpoint = "Mountpoint"
        case name = "Name"
        case scope = "Scope"
        case size = "Size"
    }

    /// Check if volume is in use by any container
    var inUse: Bool {
        // This would need to be set externally based on container mounts
        false
    }

    /// Format size for display
    var formattedSize: String {
        if size.isEmpty || size == "N/A" {
            return "N/A"
        }
        return size
    }
}
