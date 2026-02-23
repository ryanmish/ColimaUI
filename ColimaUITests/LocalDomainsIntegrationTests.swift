import XCTest

final class LocalDomainsIntegrationTests: XCTestCase {
    func testURLsContainContainerDomain() throws {
        guard command("command -v docker >/dev/null 2>&1").status == 0 else {
            throw XCTSkip("docker CLI is not available.")
        }
        guard command("docker info >/dev/null 2>&1").status == 0 else {
            throw XCTSkip("Docker is unreachable. Start Colima first.")
        }

        let name = "colimaui-it-\(UUID().uuidString.prefix(8).lowercased())"
        defer {
            _ = command("docker rm -f \(shellEscape(name)) >/dev/null 2>&1 || true")
        }

        _ = command("docker rm -f \(shellEscape(name)) >/dev/null 2>&1 || true")

        let run = command("docker run -d --name \(shellEscape(name)) nginx:alpine")
        XCTAssertEqual(run.status, 0, "Failed to start integration container: \(run.output)")

        let scriptPath = repoRootURL()
            .appendingPathComponent("scripts/colimaui")
            .path
        let escapedScript = shellEscape(scriptPath)

        let sync = command("bash \(escapedScript) domains sync")
        XCTAssertEqual(sync.status, 0, "domains sync failed: \(sync.output)")

        let expected = "https://\(name).dev.local"
        var found = false
        var lastOutput = ""

        for _ in 0..<20 {
            let urls = command("bash \(escapedScript) domains urls")
            lastOutput = urls.output
            if urls.status == 0 && urls.output.contains(expected) {
                found = true
                break
            }
            usleep(500_000)
        }

        XCTAssertTrue(found, "Expected URL not found: \(expected). Output: \(lastOutput)")
    }

    @discardableResult
    private func command(_ cmd: String) -> (status: Int32, output: String) {
        let process = Process()
        let out = Pipe()
        let err = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", cmd]
        process.standardOutput = out
        process.standardError = err
        var env = ProcessInfo.processInfo.environment
        let brewPaths = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin"
        if let existing = env["PATH"], !existing.isEmpty {
            env["PATH"] = "\(brewPaths):\(existing)"
        } else {
            env["PATH"] = "\(brewPaths):/usr/bin:/bin:/usr/sbin:/sbin"
        }
        process.environment = env

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (1, "Failed to execute command: \(error.localizedDescription)")
        }

        let outputData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        return (process.terminationStatus, (output + stderr).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ColimaUITests
            .deletingLastPathComponent() // repo root
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
