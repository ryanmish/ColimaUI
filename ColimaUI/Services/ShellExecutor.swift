import Foundation
import AppKit

/// Async wrapper for executing shell commands.
actor ShellExecutor {
    static let shared = ShellExecutor()

    /// Environment with Homebrew paths added.
    private let shellEnvironment: [String: String]

    private init() {
        var env = ProcessInfo.processInfo.environment
        // Add Homebrew paths for Apple Silicon and Intel Macs.
        let brewPaths = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin"
        if let existingPath = env["PATH"] {
            env["PATH"] = "\(brewPaths):\(existingPath)"
        } else {
            env["PATH"] = "\(brewPaths):/usr/bin:/bin:/usr/sbin:/sbin"
        }
        // Do not hard-code DOCKER_HOST; rely on the active Docker context/profile.
        shellEnvironment = env
    }

    /// Execute a shell command string through zsh.
    func run(_ command: String) async throws -> String {
        try await runCommand("/bin/zsh", arguments: ["-c", command])
    }

    /// Execute a command with argument-safe invocation (no shell interpolation).
    func runCommand(
        _ executable: String,
        arguments: [String],
        workingDirectory: String? = nil,
        timeout: Duration = .seconds(120)
    ) async throws -> String {
        let resolvedExecutable = resolveExecutable(executable)
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: resolvedExecutable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = shellEnvironment

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        }

        do {
            try process.run()
        } catch {
            throw ShellError.commandFailed(error.localizedDescription)
        }

        let stdoutTask = Task.detached(priority: .utility) {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        let stderrTask = Task.detached(priority: .utility) {
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }

        do {
            try await waitForExit(process: process, timeout: timeout)
        } catch {
            if process.isRunning {
                process.terminate()
            }
            _ = await stdoutTask.result
            _ = await stderrTask.result
            throw error
        }

        let stdoutData = await stdoutTask.value
        let stderrData = await stderrTask.value
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            return stdout
        }

        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty {
            throw ShellError.commandFailed(message)
        }

        let fallback = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        throw ShellError.commandFailed(fallback.isEmpty ? "Unknown error" : fallback)
    }

    /// Execute a command without waiting for completion (fire and forget).
    func runDetached(_ command: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.environment = shellEnvironment
        try process.run()
    }

    /// Execute a command with macOS administrator privileges.
    /// This triggers the standard system password prompt.
    func runPrivileged(_ command: String, prompt: String? = nil) async throws -> String {
        let path = shellEnvironment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let home = shellEnvironment["HOME"] ?? NSHomeDirectory()
        let user = shellEnvironment["USER"] ?? NSUserName()
        let fullCommand = """
        export PATH=\(Self.shellQuote(path))
        export HOME=\(Self.shellQuote(home))
        export USER=\(Self.shellQuote(user))
        export LOGNAME=\(Self.shellQuote(user))
        \(command)
        """
        let escaped = Self.escapeForAppleScript(fullCommand)
        var script = "do shell script \"\(escaped)\""
        if let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let escapedPrompt = Self.escapeForAppleScript(prompt)
            script += " with prompt \"\(escapedPrompt)\""
        }
        script += " with administrator privileges"
        let scriptSource = script

        return try await MainActor.run {
            var errorInfo: NSDictionary?
            guard let appleScript = NSAppleScript(source: scriptSource) else {
                throw ShellError.commandFailed("Failed to create privileged script")
            }

            let result = appleScript.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let message = (errorInfo["NSAppleScriptErrorMessage"] as? String) ?? "Unknown error"
                throw ShellError.commandFailed(message)
            }

            return result.stringValue ?? ""
        }
    }

    /// Stream output from a long-running command string.
    func stream(_ command: String, onOutput: @escaping (String) -> Void) async throws -> Process {
        try await streamCommand("/bin/zsh", arguments: ["-c", command], onOutput: onOutput)
    }

    /// Stream output from a long-running command with argument-safe invocation.
    func streamCommand(
        _ executable: String,
        arguments: [String],
        onOutput: @escaping (String) -> Void
    ) async throws -> Process {
        let resolvedExecutable = resolveExecutable(executable)
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: resolvedExecutable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = shellEnvironment

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
            Task { @MainActor in
                onOutput(output)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
            Task { @MainActor in
                onOutput(output)
            }
        }

        process.terminationHandler = { _ in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
        }

        try process.run()
        return process
    }

    /// Resolve an executable to a full path using PATH search.
    func resolveExecutable(_ name: String) -> String {
        if name.contains("/") {
            return name
        }

        let fileManager = FileManager.default
        let path = shellEnvironment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in path.split(separator: ":") {
            let candidate = "\(directory)/\(name)"
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return name
    }

    /// Open command in Terminal.app using argument-safe shell quoting.
    func openInTerminal(_ executable: String, arguments: [String]) async throws {
        let resolvedExecutable = resolveExecutable(executable)
        let command = ([resolvedExecutable] + arguments)
            .map(Self.shellQuote)
            .joined(separator: " ")

        let script = """
        tell application "Terminal"
            activate
            do script "\(Self.escapeForAppleScript(command))"
        end tell
        """

        _ = try await runCommand("/usr/bin/osascript", arguments: ["-e", script], timeout: .seconds(30))
    }

    private func waitForExit(process: Process, timeout: Duration) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async {
                        process.waitUntilExit()
                        continuation.resume()
                    }
                }
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                if process.isRunning {
                    process.terminate()
                }
                throw ShellError.commandFailed("Command timed out")
            }

            do {
                _ = try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private static func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

enum ShellError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        }
    }
}
