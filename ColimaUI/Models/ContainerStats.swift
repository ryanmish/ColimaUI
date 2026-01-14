import Foundation

/// Real-time container statistics
/// Parsed from `docker stats --no-stream --format "{{json .}}"`
struct ContainerStats: Codable, Identifiable {
    let Container: String
    let Name: String
    let CPUPerc: String
    let MemUsage: String
    let MemPerc: String
    let NetIO: String
    let BlockIO: String
    let PIDs: String

    var id: String { Container }

    /// CPU percentage as Double (e.g., "12.5%" -> 12.5)
    var cpuPercent: Double {
        let cleaned = CPUPerc.replacingOccurrences(of: "%", with: "")
        return Double(cleaned) ?? 0
    }

    /// Memory percentage as Double
    var memPercent: Double {
        let cleaned = MemPerc.replacingOccurrences(of: "%", with: "")
        return Double(cleaned) ?? 0
    }

    /// Memory usage formatted (e.g., "43.16MiB / 3.814GiB" -> "43MB")
    var memoryUsed: String {
        let parts = MemUsage.split(separator: "/")
        guard let used = parts.first else { return MemUsage }
        let trimmed = used.trimmingCharacters(in: .whitespaces)

        // Convert MiB to MB for cleaner display
        if trimmed.contains("MiB") {
            let num = trimmed.replacingOccurrences(of: "MiB", with: "")
            if let val = Double(num.trimmingCharacters(in: .whitespaces)) {
                return String(format: "%.0fMB", val)
            }
        } else if trimmed.contains("GiB") {
            let num = trimmed.replacingOccurrences(of: "GiB", with: "")
            if let val = Double(num.trimmingCharacters(in: .whitespaces)) {
                return String(format: "%.1fGB", val)
            }
        }
        return trimmed
    }

    /// Formatted CPU for display
    var cpuFormatted: String {
        String(format: "%.0f%%", cpuPercent)
    }
}
