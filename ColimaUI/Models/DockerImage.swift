import Foundation

/// Represents a Docker image
/// Parsed from `docker images --format "{{json .}}"`
struct DockerImage: Codable, Identifiable {
    let imageID: String
    let Repository: String
    let Tag: String
    let Size: String
    let CreatedAt: String

    var id: String { imageID }

    enum CodingKeys: String, CodingKey {
        case imageID = "ID"
        case Repository, Tag, Size, CreatedAt
    }

    var fullName: String {
        if Tag == "<none>" {
            return Repository
        }
        return "\(Repository):\(Tag)"
    }

    var isNone: Bool {
        Repository == "<none>"
    }

    /// Size in bytes for sorting
    var sizeBytes: Int64 {
        // Parse size like "1.35GB" or "307MB"
        let cleaned = Size.uppercased()

        if cleaned.contains("GB") {
            let num = cleaned.replacingOccurrences(of: "GB", with: "")
            if let val = Double(num) {
                return Int64(val * 1_073_741_824)
            }
        } else if cleaned.contains("MB") {
            let num = cleaned.replacingOccurrences(of: "MB", with: "")
            if let val = Double(num) {
                return Int64(val * 1_048_576)
            }
        } else if cleaned.contains("KB") {
            let num = cleaned.replacingOccurrences(of: "KB", with: "")
            if let val = Double(num) {
                return Int64(val * 1024)
            }
        }

        return 0
    }
}

/// Docker disk usage summary
/// From `docker system df`
struct DockerDiskUsage {
    var imagesSize: String = "0B"
    var imagesReclaimable: String = "0B"
    var containersSize: String = "0B"
    var volumesSize: String = "0B"
    var buildCacheSize: String = "0B"
    var totalSize: String = "0B"
}
