import Foundation
import AppKit
import Observation

/// Checks for required dependencies (Colima, Docker, Homebrew)
@MainActor
@Observable
class DependencyChecker {
    static let shared = DependencyChecker()

    var hasHomebrew = false
    var hasColima = false
    var hasDocker = false
    var isChecking = false
    var isInstalling = false
    var installProgress: String = ""

    private let shell = ShellExecutor.shared

    private init() {}

    var allDependenciesMet: Bool {
        hasColima && hasDocker
    }

    var missingDependencies: [String] {
        var missing: [String] = []
        if !hasColima { missing.append("Colima") }
        if !hasDocker { missing.append("Docker CLI") }
        return missing
    }

    /// Common paths where Homebrew installs binaries
    private let brewPaths = [
        "/opt/homebrew/bin",  // Apple Silicon
        "/usr/local/bin"      // Intel
    ]

    /// Check all dependencies
    func checkAll() async {
        isChecking = true

        // Check with full paths since GUI apps don't have shell PATH
        hasHomebrew = await checkCommandExists("brew")
        hasColima = await checkCommandExists("colima")
        hasDocker = await checkCommandExists("docker")

        isChecking = false
    }

    /// Check if a command exists in common paths
    private func checkCommandExists(_ command: String) async -> Bool {
        for path in brewPaths {
            let fullPath = "\(path)/\(command)"
            do {
                _ = try await shell.run("test -x \(fullPath) && \(fullPath) --version")
                return true
            } catch {
                continue
            }
        }
        return false
    }

    /// Install Homebrew
    func installHomebrew() async -> Bool {
        isInstalling = true
        installProgress = "Installing Homebrew..."

        do {
            // Homebrew install script
            let script = """
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            """
            _ = try await shell.run(script)
            hasHomebrew = true
            isInstalling = false
            return true
        } catch {
            installProgress = "Failed to install Homebrew: \(error.localizedDescription)"
            isInstalling = false
            return false
        }
    }

    /// Install Colima and Docker via Homebrew
    func installColima() async -> Bool {
        guard hasHomebrew else {
            installProgress = "Homebrew required. Install it first."
            return false
        }

        isInstalling = true
        installProgress = "Installing Colima and Docker CLI..."

        do {
            _ = try await shell.run("brew install colima docker")
            installProgress = "Starting Colima for the first time..."
            _ = try await shell.run("colima start")

            hasColima = true
            hasDocker = true
            isInstalling = false
            installProgress = "Installation complete!"
            return true
        } catch {
            installProgress = "Installation failed: \(error.localizedDescription)"
            isInstalling = false
            return false
        }
    }

    /// Install just Docker CLI
    func installDocker() async -> Bool {
        guard hasHomebrew else {
            installProgress = "Homebrew required. Install it first."
            return false
        }

        isInstalling = true
        installProgress = "Installing Docker CLI..."

        do {
            _ = try await shell.run("brew install docker")
            hasDocker = true
            isInstalling = false
            return true
        } catch {
            installProgress = "Failed: \(error.localizedDescription)"
            isInstalling = false
            return false
        }
    }

    /// Open Homebrew website
    func openHomebrewWebsite() {
        if let url = URL(string: "https://brew.sh") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open Colima GitHub
    func openColimaWebsite() {
        if let url = URL(string: "https://github.com/abiosoft/colima") {
            NSWorkspace.shared.open(url)
        }
    }
}
