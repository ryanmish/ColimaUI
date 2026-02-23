import Foundation
import Observation

enum LocalDomainsReconcileTrigger: String {
    case manual
    case settingsChange = "settings-change"
    case periodic
    case dockerEvent = "docker-event"
}

struct LocalDomainsAutopilotPolicy {
    static func shouldAttemptRepair(trigger: LocalDomainsReconcileTrigger) -> Bool {
        switch trigger {
        case .manual, .settingsChange:
            return true
        case .periodic, .dockerEvent:
            return false
        }
    }
}

/// Background reconciler that keeps local domains healthy with minimal user action.
@MainActor
@Observable
class LocalDomainsAutopilot {
    static let shared = LocalDomainsAutopilot()

    var status: String = "Disabled"
    var detail: String = "Enable Local Domains to start autopilot."
    var isHealthy: Bool = false
    var isRunning: Bool = false
    var lastReconciledAt: Date?

    private let shell = ShellExecutor.shared

    private var monitorTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var eventProcess: Process?
    private var pendingEventBuffer: String = ""
    private var setupCooldownUntil: Date = .distantPast
    private var defaultsObserver: NSObjectProtocol?

    private init() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.handleSettingsChange()
            }
        }
    }

    func start() {
        guard monitorTask == nil else { return }

        isRunning = true
        status = "Starting"
        detail = "Preparing local domain autopilot."

        monitorTask = Task { [weak self] in
            guard let self else { return }
            await self.handleSettingsChange()
        }

        periodicTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                await self.reconcile(trigger: .periodic)
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil

        periodicTask?.cancel()
        periodicTask = nil

        debounceTask?.cancel()
        debounceTask = nil

        stopEventStream()
        isRunning = false
        isHealthy = false
        status = "Disabled"
        detail = "Autopilot stopped."
    }

    func reconcileNow() async {
        await reconcile(trigger: .manual)
    }

    private func isEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: "enableContainerDomains")
    }

    private func handleSettingsChange() async {
        guard isRunning else { return }

        if isEnabled() {
            status = "Starting"
            detail = "Watching Docker events and reconciling routes."
            await startEventStreamIfNeeded()
            await reconcile(trigger: .settingsChange)
        } else {
            stopEventStream()
            isHealthy = false
            status = "Disabled"
            detail = "Enable Local Domains to start autopilot."
        }
    }

    private func startEventStreamIfNeeded() async {
        guard isRunning, isEnabled(), eventProcess == nil else { return }

        do {
            pendingEventBuffer = ""
            let command = """
            docker events \
              --filter type=container \
              --filter event=start \
              --filter event=stop \
              --filter event=die \
              --filter event=destroy \
              --filter event=rename \
              --format '{{json .}}'
            """

            let process = try await shell.stream(command) { [weak self] chunk in
                guard let self else { return }
                Task { @MainActor in
                    self.handleEventChunk(chunk)
                }
            }
            eventProcess = process
            process.terminationHandler = { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleEventStreamExit()
                }
            }
        } catch {
            status = "Needs attention"
            detail = "Event stream failed: \(error.localizedDescription)"
            isHealthy = false
        }
    }

    private func stopEventStream() {
        eventProcess?.terminationHandler = nil
        if let process = eventProcess, process.isRunning {
            process.terminate()
        }
        eventProcess = nil
        pendingEventBuffer = ""
    }

    private func handleEventStreamExit() async {
        guard isRunning, isEnabled() else { return }
        eventProcess = nil
        try? await Task.sleep(for: .seconds(2))
        await startEventStreamIfNeeded()
    }

    private func handleEventChunk(_ chunk: String) {
        pendingEventBuffer += chunk
        while let newline = pendingEventBuffer.firstIndex(of: "\n") {
            let line = pendingEventBuffer[..<newline].trimmingCharacters(in: .whitespacesAndNewlines)
            pendingEventBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            scheduleDebouncedReconcile()
        }
    }

    private func scheduleDebouncedReconcile() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(700))
            await self.reconcile(trigger: .dockerEvent)
        }
    }

    private func reconcile(trigger: LocalDomainsReconcileTrigger) async {
        guard isRunning, isEnabled() else { return }
        let suffix = LocalDomainDefaults.suffix

        do {
            _ = try await shell.run("docker info >/dev/null 2>&1")
        } catch {
            isHealthy = false
            status = "Needs attention"
            detail = "Docker is unreachable. Start Colima."
            return
        }

        status = "Reconciling"
        detail = "Updating routes for .\(suffix) (\(trigger.rawValue))."

        await LocalDomainService.shared.syncProxyRoutes(suffix: suffix, force: true)
        var checks = await LocalDomainService.shared.checkSetup(suffix: suffix)

        let needsRepair = checks.isEmpty || !checks.allSatisfy(\.isPassing)
        let canAttemptSetup = LocalDomainsAutopilotPolicy.shouldAttemptRepair(trigger: trigger)

        if needsRepair && canAttemptSetup && Date() >= setupCooldownUntil {
            status = "Repairing"
            detail = "Attempting automatic repair for .\(suffix)."
            setupCooldownUntil = Date().addingTimeInterval(300)
            _ = try? await LocalDomainService.shared.setupAndCheck(suffix: suffix)
            checks = await LocalDomainService.shared.checkSetup(suffix: suffix)
        }

        lastReconciledAt = Date()
        let failedChecks = checks.filter { !$0.isPassing }
        if checks.isEmpty {
            isHealthy = false
            status = "Needs attention"
            detail = "No health checks available yet."
        } else if failedChecks.isEmpty {
            isHealthy = true
            status = "Healthy"
            detail = "Autopilot is keeping .\(suffix) routes healthy."
        } else {
            isHealthy = false
            status = "Needs attention"
            detail = "Issue detected: \(failedChecks.first?.title ?? "Unknown check")."
        }
    }
}
