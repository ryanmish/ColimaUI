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
    var domainSetupHealthy = false
    var isChecking = false
    var isInstalling = false
    var installProgress: String = ""
    var lastFailedStep: String = ""
    var lastFailureDetail: String = ""

    private let shell = ShellExecutor.shared

    private init() {}

    var allDependenciesMet: Bool {
        hasColima && hasDocker
    }

    var isFullyReady: Bool {
        allDependenciesMet && hasColimaUICLI && domainSetupHealthy
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
        hasColimaUICLI = await LocalDomainService.shared.hasCompatibleCLI()
        if hasColima && hasDocker && hasColimaUICLI {
            domainSetupHealthy = await isDomainSetupHealthy(suffix: defaultDomainSuffix())
        } else {
            domainSetupHealthy = false
        }

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
            _ = await installColimaUICLI()
            let compatibleColimaUICLI = await LocalDomainService.shared.hasCompatibleCLI()

            hasColima = true
            hasDocker = true
            hasColimaUICLI = compatibleColimaUICLI
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

    /// Install only the colimaui helper CLI
    func installColimaUICLIOnly() async -> Bool {
        isInstalling = true
        installProgress = "Installing colimaui domain CLI..."

        _ = await installColimaUICLI()
        hasColimaUICLI = await LocalDomainService.shared.hasCompatibleCLI()

        isInstalling = false
        if hasColimaUICLI {
            installProgress = "colimaui CLI installed"
            return true
        }

        installProgress = "Failed to install colimaui CLI"
        return false
    }

    /// One-step onboarding flow: install runtime + CLI + domain setup/check.
    func installAndConfigureAll(domainSuffix: String) async -> Bool {
        _ = domainSuffix
        let suffix = LocalDomainDefaults.suffix

        isInstalling = true
        lastFailedStep = ""
        lastFailureDetail = ""
        installProgress = "Preparing setup..."

        defer { isInstalling = false }

        if !hasHomebrew {
            installProgress = "Installing Homebrew..."
            guard await installHomebrewCore() else {
                lastFailedStep = "Install Homebrew"
                if lastFailureDetail.isEmpty { lastFailureDetail = installProgress }
                return false
            }
            hasHomebrew = true
        }

        installProgress = "Installing Colima and Docker CLI..."
        do {
            _ = try await shell.run("brew install colima docker")
            hasColima = true
            hasDocker = true
        } catch {
            lastFailedStep = "Install Colima and Docker CLI"
            lastFailureDetail = error.localizedDescription
            installProgress = "Failed to install Colima/Docker."
            return false
        }

        installProgress = "Starting Colima..."
        do {
            if (try? await shell.run("colima status >/dev/null 2>&1")) == nil {
                _ = try await shell.run("colima start")
            }
        } catch {
            lastFailedStep = "Start Colima"
            lastFailureDetail = error.localizedDescription
            installProgress = "Failed to start Colima."
            return false
        }

        installProgress = "Installing colimaui CLI..."
        _ = await installColimaUICLI()
        hasColimaUICLI = await LocalDomainService.shared.hasCompatibleCLI()
        guard hasColimaUICLI else {
            lastFailedStep = "Install colimaui CLI"
            lastFailureDetail = "Unable to install colimaui CLI into system or user bin directories."
            installProgress = "Failed to install colimaui CLI."
            return false
        }

        installProgress = "Configuring local domains (.\(suffix))..."
        do {
            let checks = try await LocalDomainService.shared.setupAndCheck(suffix: suffix)
            let allPassing = checks.allSatisfy(\.isPassing)
            domainSetupHealthy = allPassing
            if !allPassing {
                let failedTitles = checks.filter { !$0.isPassing }.map(\.title).joined(separator: ", ")
                lastFailedStep = "Local domain setup"
                lastFailureDetail = failedTitles.isEmpty ? "Setup checks failed." : "Failed checks: \(failedTitles)"
                installProgress = "Local domain setup needs attention."
                return false
            }
        } catch {
            lastFailedStep = "Local domain setup"
            lastFailureDetail = error.localizedDescription
            installProgress = "Failed to configure local domains."
            return false
        }

        installProgress = "Verifying local domains..."
        let healthy = await isDomainSetupHealthy(suffix: suffix)
        domainSetupHealthy = healthy
        guard healthy else {
            lastFailedStep = "Verify local domains"
            lastFailureDetail = "Domain checks did not pass after setup."
            installProgress = "Local domain verification failed."
            return false
        }

        UserDefaults.standard.set(true, forKey: "enableContainerDomains")
        UserDefaults.standard.set(suffix, forKey: "containerDomainSuffix")

        installProgress = "Setup complete."
        await checkAll()
        return true
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

    /// Open ColimaUI GitHub
    func openColimaUIWebsite() {
        if let url = URL(string: "https://github.com/ryanmish/ColimaUI") {
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
        var targets: [String] = []

        if let activePath = await resolveActiveColimaUICLIPath() {
            targets.append(activePath)
        }

        if let preferredSystemBin = systemBinDirs.first {
            targets.append("\(preferredSystemBin)/colimaui")
        }

        targets.append(userTarget)

        var seen = Set<String>()
        var installedAny = false
        let homePrefix = NSHomeDirectory() + "/"

        for target in targets where seen.insert(target).inserted {
            if await installColimaUIScript(
                escapedSource: escapedSource,
                target: target,
                privileged: false
            ) {
                installedAny = true
                continue
            }

            if target.hasPrefix(homePrefix) {
                continue
            }

            if await installColimaUIScript(
                escapedSource: escapedSource,
                target: target,
                privileged: true,
                prompt: "ColimaUI needs permission to install or update the colimaui command-line helper for local domain management."
            ) {
                installedAny = true
            }
        }

        if !installedAny {
            return false
        }

        return await LocalDomainService.shared.hasCompatibleCLI()
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

    private func resolveActiveColimaUICLIPath() async -> String? {
        guard let resolved = try? await shell.run("command -v colimaui 2>/dev/null") else {
            return nil
        }
        let path = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/") else { return nil }
        return path
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

    private func installHomebrewCore() async -> Bool {
        do {
            let script = """
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            """
            _ = try await shell.run(script)
            return true
        } catch {
            lastFailureDetail = error.localizedDescription
            return false
        }
    }

    private func normalizedDomainSuffix(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func defaultDomainSuffix() -> String {
        LocalDomainDefaults.suffix
    }

    private func isDomainSetupHealthy(suffix: String) async -> Bool {
        let normalized = normalizedDomainSuffix(suffix)
        guard !normalized.isEmpty, hasColimaUICLI else { return false }
        let checks = await LocalDomainService.shared.checkSetup(suffix: normalized)
        return !checks.isEmpty && checks.allSatisfy(\.isPassing)
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
