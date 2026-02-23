import Foundation
import AppKit

/// Async wrapper for executing shell commands
actor ShellExecutor {
    static let shared = ShellExecutor()

    /// Environment with Homebrew paths added
    private let shellEnvironment: [String: String]

    private init() {
        var env = ProcessInfo.processInfo.environment
        // Add Homebrew paths for Apple Silicon and Intel Macs
        let brewPaths = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin"
        if let existingPath = env["PATH"] {
            env["PATH"] = "\(brewPaths):\(existingPath)"
        } else {
            env["PATH"] = "\(brewPaths):/usr/bin:/bin:/usr/sbin:/sbin"
        }
        // Do not hard-code DOCKER_HOST; rely on the active Docker context/profile.
        shellEnvironment = env
    }

    /// Execute a shell command and return stdout
    func run(_ command: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.standardOutput = pipe
            process.standardError = errorPipe
            process.environment = shellEnvironment

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: ShellError.commandFailed(errorOutput))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Execute a command without waiting for completion (fire and forget)
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

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                var errorInfo: NSDictionary?
                guard let appleScript = NSAppleScript(source: script) else {
                    continuation.resume(throwing: ShellError.commandFailed("Failed to create privileged script"))
                    return
                }

                let result = appleScript.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let message = (errorInfo["NSAppleScriptErrorMessage"] as? String) ?? "Unknown error"
                    continuation.resume(throwing: ShellError.commandFailed(message))
                    return
                }

                continuation.resume(returning: result.stringValue ?? "")
            }
        }
    }

    /// Stream output from a long-running command
    func stream(_ command: String, onOutput: @escaping (String) -> Void) async throws -> Process {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.environment = shellEnvironment

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                DispatchQueue.main.async {
                    onOutput(output)
                }
            }
        }

        try process.run()
        return process
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
