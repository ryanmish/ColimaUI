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
    var hasColimaUICLI = false
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
        let hasSystemColimaUICLI = await checkCommandExists("colimaui")
        let hasUserColimaUICLI = await checkUserLocalCommandExists("colimaui")
        hasColimaUICLI = hasSystemColimaUICLI || hasUserColimaUICLI

        isChecking = false
    }

    /// Check if a command exists in common paths
    private func checkCommandExists(_ command: String) async -> Bool {
        for path in brewPaths {
            let fullPath = "\(path)/\(command)"
            if (try? await shell.run("test -x \(Self.shellEscape(fullPath))")) != nil {
                return true
            }
        }
        return false
    }

    private func checkUserLocalCommandExists(_ command: String) async -> Bool {
        let fullPath = "\(NSHomeDirectory())/.local/bin/\(command)"
        do {
            _ = try await shell.run("test -x '\(fullPath)'")
            return true
        } catch {
            return false
        }
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

            installProgress = "Installing colimaui domain CLI..."
            let cliInstalled = await installColimaUICLI()
            let hasSystemColimaUICLI = await checkCommandExists("colimaui")
            let hasUserColimaUICLI = await checkUserLocalCommandExists("colimaui")

            hasColima = true
            hasDocker = true
            hasColimaUICLI = cliInstalled || hasSystemColimaUICLI || hasUserColimaUICLI
            isInstalling = false
            installProgress = hasColimaUICLI
                ? "Installation complete!"
                : "Colima + Docker installed. colimaui CLI install needs attention."
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

    private func installColimaUICLI() async -> Bool {
        guard let sourcePath = resolveColimaUIScriptPath() else {
            return false
        }

        let systemBinDirs = await candidateSystemBinDirectories()
        let userTargetDir = "\(NSHomeDirectory())/.local/bin"
        let userTarget = "\(userTargetDir)/colimaui"
        let escapedSource = Self.shellEscape(sourcePath)

        for binDir in systemBinDirs {
            let target = "\(binDir)/colimaui"
            if await installColimaUIScript(
                escapedSource: escapedSource,
                target: target,
                privileged: false
            ) {
                return true
            }
        }

        if let privilegedTarget = systemBinDirs.first {
            if await installColimaUIScript(
                escapedSource: escapedSource,
                target: "\(privilegedTarget)/colimaui",
                privileged: true,
                prompt: "ColimaUI needs permission to install the colimaui command-line helper for local domain management."
            ) {
                return true
            }
        }

        if (try? await shell.run("mkdir -p '\(userTargetDir)' && install -m 755 \(escapedSource) '\(userTarget)'")) != nil {
            return true
        }

        return false
    }

    private func candidateSystemBinDirectories() async -> [String] {
        var candidates: [String] = []

        if let brewPrefix = try? await shell.run("brew --prefix") {
            let trimmed = brewPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                candidates.append("\(trimmed)/bin")
            }
        }

        candidates.append(contentsOf: brewPaths)

        var seen = Set<String>()
        var unique: [String] = []
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            guard FileManager.default.fileExists(atPath: trimmed) else { continue }
            seen.insert(trimmed)
            unique.append(trimmed)
        }
        return unique
    }

    private func installColimaUIScript(
        escapedSource: String,
        target: String,
        privileged: Bool,
        prompt: String? = nil
    ) async -> Bool {
        let targetDir = URL(fileURLWithPath: target).deletingLastPathComponent().path
        let escapedTargetDir = Self.shellEscape(targetDir)
        let escapedTarget = Self.shellEscape(target)
        let command = "test -d \(escapedTargetDir) && install -m 755 \(escapedSource) \(escapedTarget)"

        if privileged {
            return (try? await shell.runPrivileged(command, prompt: prompt)) != nil
        }
        return (try? await shell.run(command)) != nil
    }

    private func resolveColimaUIScriptPath() -> String? {
        let fm = FileManager.default
        var candidates: [String] = []

        if let bundled = Bundle.main.path(forResource: "colimaui", ofType: nil) {
            candidates.append(bundled)
        }

        let cwd = fm.currentDirectoryPath
        candidates.append("\(cwd)/scripts/colimaui")
        candidates.append("\(cwd)/ColimaUI/scripts/colimaui")

        if let bundleURL = Bundle.main.bundleURL.path.removingPercentEncoding {
            let appParent = URL(fileURLWithPath: bundleURL)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .path
            candidates.append("\(appParent)/scripts/colimaui")
        }

        for candidate in candidates {
            if fm.isReadableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
