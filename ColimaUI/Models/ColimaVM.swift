import Foundation

/// Represents a Colima virtual machine instance
/// Parsed from `colima list --json`
struct ColimaVM: Codable, Identifiable {
    let name: String
    let status: String
    let arch: String
    let cpus: Int
    let memory: Int64
    let disk: Int64
    let runtime: String?  // Optional - not present when VM is stopped

    var id: String { name }

    var isRunning: Bool {
        status.lowercased() == "running"
    }

    var memoryGB: Double {
        Double(memory) / 1_073_741_824 // bytes to GB
    }

    var diskGB: Double {
        Double(disk) / 1_073_741_824
    }

    var formattedMemory: String {
        String(format: "%.0fGB", memoryGB)
    }

    var formattedDisk: String {
        String(format: "%.0fGB", diskGB)
    }
}
