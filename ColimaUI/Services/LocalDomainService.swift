import Foundation

struct LocalDomainCheck: Identifiable {
    let id: String
    let title: String
    let isPassing: Bool
    let detail: String
}

private enum LocalDomainSetupError: LocalizedError {
    case invalidSuffix
    case missingCLI

    var errorDescription: String? {
        switch self {
        case .invalidSuffix:
            return "Domain suffix is invalid."
        case .missingCLI:
            return "colimaui CLI is missing. Re-run onboarding to install it."
        }
    }
}

/// Handles local-domain setup and health checks through the colimaui CLI.
actor LocalDomainService {
    static let shared = LocalDomainService()

    private let shell = ShellExecutor.shared

    private init() {}

    func hasCompatibleCLI() async -> Bool {
        await resolveColimaUICLIInvocation() != nil
    }

    func normalizeSuffix(_ suffix: String) -> String {
        _ = suffix
        return LocalDomainDefaults.suffix
    }

    func setupAndCheck(suffix: String) async throws -> [LocalDomainCheck] {
        let normalized = normalizeSuffix(suffix)
        guard !normalized.isEmpty else {
            throw LocalDomainSetupError.invalidSuffix
        }

        let prep = try await runRequiredCLIAction("setup-prep", suffix: normalized)
        guard prep.exitCode == 0 else {
            throw ShellError.commandFailed(
                summarizeCLIError(prep.output, fallback: "Local-domain setup failed during preparation.")
            )
        }

        let apply = try await runRequiredPrivilegedCLIAction(
            "setup-apply",
            suffix: normalized,
            prompt: "ColimaUI needs administrator permission to configure DNS and resolver settings for .\(normalized) local domains."
        )
        guard apply.exitCode == 0 else {
            throw ShellError.commandFailed(
                summarizeCLIError(apply.output, fallback: "Local-domain setup failed while applying system changes.")
            )
        }

        let finalize = try await runRequiredCLIAction("setup-finalize", suffix: normalized)
        guard finalize.exitCode == 0 else {
            throw ShellError.commandFailed(
                summarizeCLIError(finalize.output, fallback: "Local-domain setup failed during finalization.")
            )
        }

        return await checkSetup(suffix: normalized)
    }

    func unsetup(suffix: String) async throws -> [LocalDomainCheck] {
        let normalized = normalizeSuffix(suffix)
        guard !normalized.isEmpty else {
            throw LocalDomainSetupError.invalidSuffix
        }

        let result = try await runRequiredPrivilegedCLIAction(
            "unsetup",
            suffix: normalized,
            prompt: "ColimaUI needs administrator permission to remove DNS and resolver settings for .\(normalized) local domains."
        )
        guard result.exitCode == 0 else {
            throw ShellError.commandFailed(
                summarizeCLIError(result.output, fallback: "Local-domain unsetup failed.")
            )
        }

        return await checkSetup(suffix: normalized)
    }

    func trustTLS(suffix: String) async throws -> [LocalDomainCheck] {
        let normalized = normalizeSuffix(suffix)
        guard !normalized.isEmpty else {
            throw LocalDomainSetupError.invalidSuffix
        }

        let result = try await runRequiredCLIAction("trust", suffix: normalized)
        guard result.exitCode == 0 else {
            throw ShellError.commandFailed(
                summarizeCLIError(result.output, fallback: "TLS trust update failed.")
            )
        }

        return await checkSetup(suffix: normalized)
    }

    func checkSetup(suffix: String) async -> [LocalDomainCheck] {
        let normalized = normalizeSuffix(suffix)
        guard !normalized.isEmpty else {
            return failingChecks("Domain suffix is invalid.")
        }

        do {
            let result = try await runRequiredCLIAction("check", suffix: normalized)
            if let parsed = parseCLICheckOutput(result.output), !parsed.isEmpty {
                return parsed
            }

            let detail = result.output.isEmpty
                ? "Unable to parse health output from colimaui CLI."
                : "Unexpected CLI health output.\n\(firstLine(of: result.output))"
            return failingChecks(detail)
        } catch {
            return failingChecks(error.localizedDescription)
        }
    }

    func syncProxyRoutes(suffix: String, force: Bool = false) async {
        _ = force
        let normalized = normalizeSuffix(suffix)
        guard !normalized.isEmpty else { return }
        _ = try? await runRequiredCLIAction("sync", suffix: normalized)
    }

    private struct CLICallResult {
        let exitCode: Int
        let output: String
    }

    private func runRequiredCLIAction(_ action: String, suffix: String) async throws -> CLICallResult {
        guard let result = try await runColimaUICLIAction(action, suffix: suffix, privilegedPrompt: nil) else {
            throw LocalDomainSetupError.missingCLI
        }
        return result
    }

    private func runRequiredPrivilegedCLIAction(_ action: String, suffix: String, prompt: String) async throws -> CLICallResult {
        guard let result = try await runColimaUICLIAction(action, suffix: suffix, privilegedPrompt: prompt) else {
            throw LocalDomainSetupError.missingCLI
        }
        return result
    }

    private func runColimaUICLIAction(_ action: String, suffix: String, privilegedPrompt: String?) async throws -> CLICallResult? {
        guard let cliInvocation = await resolveColimaUICLIInvocation() else {
            return nil
        }

        let suffixEscaped = Self.shellEscape(suffix)
        let marker = "__COLIMAUI_EXIT__="
        let command = """
        set +e
        \(cliInvocation) domains \(action) --suffix \(suffixEscaped) 2>&1
        exit_code=$?
        echo "\(marker)$exit_code"
        """

        let output: String
        if let privilegedPrompt {
            output = try await shell.runPrivileged(command, prompt: privilegedPrompt)
        } else {
            output = try await shell.run(command)
        }
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var exitCode = 0
        var filteredLines: [String] = []
        for line in lines {
            if line.hasPrefix(marker) {
                let raw = line.replacingOccurrences(of: marker, with: "")
                exitCode = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            } else {
                filteredLines.append(line)
            }
        }

        return CLICallResult(
            exitCode: exitCode,
            output: filteredLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func resolveColimaUICLIInvocation() async -> String? {
        let fileManager = FileManager.default
        let bundledCandidates = bundledScriptCandidates(fileManager: fileManager)
        for candidate in bundledCandidates where fileManager.isReadableFile(atPath: candidate) {
            let invocation = "bash \(Self.shellEscape(candidate))"
            if await isExpectedCLIVersion(invocation) {
                return invocation
            }
        }

        let installedCandidates = [
            "/opt/homebrew/bin/colimaui",
            "/usr/local/bin/colimaui",
            "\(NSHomeDirectory())/.local/bin/colimaui"
        ]

        for candidate in installedCandidates where fileManager.isReadableFile(atPath: candidate) {
            let invocation = Self.shellEscape(candidate)
            if await isExpectedCLIVersion(invocation) {
                return invocation
            }
        }

        if await commandSucceeds("command -v colimaui >/dev/null 2>&1"), await isExpectedCLIVersion("colimaui") {
            return "colimaui"
        }

        return nil
    }

    private func bundledScriptCandidates(fileManager: FileManager) -> [String] {
        var candidates: [String] = []

        if let bundledResource = Bundle.main.resourceURL?.appendingPathComponent("colimaui").path {
            candidates.append(bundledResource)
        }

        if let bundled = Bundle.main.path(forResource: "colimaui", ofType: nil) {
            candidates.append(bundled)
        }

        let cwd = fileManager.currentDirectoryPath
        candidates.append("\(cwd)/scripts/colimaui")
        candidates.append("\(cwd)/ColimaUI/scripts/colimaui")

        if let bundlePath = Bundle.main.bundleURL.path.removingPercentEncoding {
            let appParent = URL(fileURLWithPath: bundlePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .path
            candidates.append("\(appParent)/scripts/colimaui")
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private func isExpectedCLIVersion(_ invocation: String) async -> Bool {
        guard let version = await resolvedCLIVersion(for: invocation) else {
            return false
        }
        return version == LocalDomainDefaults.cliVersion
    }

    private func resolvedCLIVersion(for invocation: String) async -> String? {
        do {
            let output = try await shell.run("\(invocation) --version 2>/dev/null")
            return parseVersion(from: output)
        } catch {
            return nil
        }
    }

    private func parseVersion(from output: String) -> String? {
        let pattern = #"[0-9]+\.[0-9]+\.[0-9]+"#
        guard let range = output.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(output[range])
    }

    private func parseCLICheckOutput(_ output: String) -> [LocalDomainCheck]? {
        let orderedTitles: [String] = [
            "Homebrew",
            "Colima runtime",
            "Docker API",
            "dnsmasq",
            "dnsmasq service",
            "Wildcard DNS",
            "macOS resolver",
            "Wildcard resolution",
            "Reverse proxy",
            "mkcert",
            "TLS certificate",
            "Domain index",
            "TLS trust"
        ]

        let idsByTitle: [String: String] = [
            "Homebrew": "brew",
            "Colima runtime": "colima",
            "Docker API": "docker",
            "dnsmasq": "dnsmasq-binary",
            "dnsmasq service": "dnsmasq-service",
            "Wildcard DNS": "dnsmasq-wildcard",
            "macOS resolver": "resolver",
            "Wildcard resolution": "resolution",
            "Reverse proxy": "proxy",
            "mkcert": "mkcert",
            "TLS certificate": "cert",
            "Domain index": "index",
            "TLS trust": "tls-trust"
        ]

        var checksByID: [String: LocalDomainCheck] = [:]

        for rawLine in output.split(separator: "\n") {
            let line = String(rawLine)
            let isPass = line.hasPrefix("PASS  ")
            let isFail = line.hasPrefix("FAIL  ")
            guard isPass || isFail else { continue }

            let payload = String(line.dropFirst(6))
            let titleField = String(payload.prefix(22)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let id = idsByTitle[titleField] else { continue }
            let detail = String(payload.dropFirst(min(22, payload.count)))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            checksByID[id] = LocalDomainCheck(
                id: id,
                title: titleField,
                isPassing: isPass,
                detail: detail.isEmpty ? (isPass ? "Configured" : "Needs attention") : detail
            )
        }

        if checksByID.isEmpty {
            return nil
        }

        var orderedChecks: [LocalDomainCheck] = []
        for title in orderedTitles {
            guard let id = idsByTitle[title], let check = checksByID[id] else { continue }
            orderedChecks.append(check)
        }

        return orderedChecks.isEmpty ? nil : orderedChecks
    }

    private func failingChecks(_ detail: String) -> [LocalDomainCheck] {
        let titles: [(String, String)] = [
            ("brew", "Homebrew"),
            ("colima", "Colima runtime"),
            ("docker", "Docker API"),
            ("dnsmasq-binary", "dnsmasq"),
            ("dnsmasq-service", "dnsmasq service"),
            ("dnsmasq-wildcard", "Wildcard DNS"),
            ("resolver", "macOS resolver"),
            ("resolution", "Wildcard resolution"),
            ("proxy", "Reverse proxy"),
            ("mkcert", "mkcert"),
            ("cert", "TLS certificate"),
            ("index", "Domain index"),
            ("tls-trust", "TLS trust")
        ]

        return titles.enumerated().map { index, item in
            LocalDomainCheck(
                id: item.0,
                title: item.1,
                isPassing: false,
                detail: index == 0 ? detail : "Not verified"
            )
        }
    }

    private func commandSucceeds(_ command: String) async -> Bool {
        do {
            _ = try await shell.run(command)
            return true
        } catch {
            return false
        }
    }

    private func firstLine(of value: String) -> String {
        value
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .first ?? value
    }

    private func summarizeCLIError(_ output: String, fallback: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }

        let lines = trimmed
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return fallback }

        if let exact = lines.reversed().first(where: { $0.hasPrefix("ERROR:") || $0.hasPrefix("FAIL  ") }) {
            return exact
        }

        if let semantic = lines.reversed().first(where: {
            let lower = $0.lowercased()
            return lower.contains("failed") || lower.contains("error")
        }) {
            return semantic
        }

        return lines.last ?? fallback
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
