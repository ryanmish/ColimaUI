import SwiftUI
import AppKit

@main
struct ColimaUIApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 700)

        MenuBarExtra {
            MenuBarMenuView()
        } label: {
            Image("ColimaToolbarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .padding(.horizontal, 1)
        }
    }
}

struct MenuBarMenuView: View {
    @State private var colima = ColimaService.shared
    @State private var docker = DockerService.shared
    @State private var isRefreshing = false
    @State private var domainSummary = "Domain checks pending"
    @State private var domainHealthy = false

    @AppStorage("enableContainerDomains") private var enableContainerDomains: Bool = false
    @AppStorage("containerDomainSuffix") private var containerDomainSuffix: String = "colima"
    @AppStorage("preferHTTPSDomains") private var preferHTTPSDomains: Bool = false

    private struct DomainEntry: Identifiable {
        let id: String
        let containerName: String
        let domains: [String]
    }

    private var runningContainerCount: Int {
        docker.containers.filter(\.isRunning).count
    }

    private var runningContainers: [Container] {
        docker.containers
            .filter(\.isRunning)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var normalizedSuffix: String {
        containerDomainSuffix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private var domainEntries: [DomainEntry] {
        guard enableContainerDomains else { return [] }
        let suffix = normalizedSuffix.isEmpty ? "colima" : normalizedSuffix

        return runningContainers.compactMap { container in
            let domains = container.localDomains(domainSuffix: suffix)
                .filter { !Container.isWildcardDomain($0) }
                .sorted()
            guard !domains.isEmpty else { return nil }
            return DomainEntry(id: container.id, containerName: container.name, domains: domains)
        }
    }

    var body: some View {
        Group {
            Button("Open ColimaUI") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }

            Divider()

            Text(colima.hasRunningVM ? "Colima running" : "Colima stopped")
                .foregroundColor(.secondary)
            Text("\(runningContainerCount)/\(docker.containers.count) containers running")
                .foregroundColor(.secondary)

            Divider()

            if enableContainerDomains {
                Menu("Local Domains") {
                    Button("Open Domain Index") {
                        openDomainIndex()
                    }

                    Button("Copy Domain Index URL") {
                        copyDomainIndex()
                    }

                    Divider()

                    if domainEntries.isEmpty {
                        Text("No routed container domains yet")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(domainEntries) { entry in
                            Menu(entry.containerName) {
                                ForEach(entry.domains, id: \.self) { domain in
                                    Button(domain) {
                                        openDomain(domain)
                                    }
                                }

                                Divider()

                                Button("Copy all domains") {
                                    copyDomains(entry.domains)
                                }
                            }
                        }
                    }
                }

                Button("Sync Local Domains") {
                    Task { await syncDomains() }
                }

                Button(isRefreshing ? "Checking Domains..." : "Check Local Domains") {
                    Task { await refreshDomainStatus() }
                }
                .disabled(isRefreshing)

                Text(domainSummary)
                    .foregroundColor(domainHealthy ? .green : .secondary)
            } else {
                Text("Local domains disabled")
                    .foregroundColor(.secondary)
            }

            Divider()

            Button(colima.hasRunningVM ? "Stop Colima" : "Start Colima") {
                Task {
                    if colima.hasRunningVM {
                        await colima.stop()
                    } else {
                        await colima.start()
                    }
                    await refreshRuntime()
                }
            }

            Button("Restart Colima") {
                Task {
                    await colima.restart()
                    await refreshRuntime()
                }
            }
            .disabled(!colima.hasRunningVM)

            Divider()

            Button("Quit ColimaUI") {
                NSApp.terminate(nil)
            }
        }
        .task {
            await refreshRuntime()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await refreshRuntime()
            }
        }
    }

    private func refreshRuntime() async {
        await colima.refresh()
        await docker.refreshContainers()
        await refreshDomainStatus()
    }

    private func syncDomains() async {
        guard enableContainerDomains else { return }
        await LocalDomainService.shared.syncProxyRoutes(suffix: normalizedSuffix, force: true)
        await refreshDomainStatus()
    }

    private func refreshDomainStatus() async {
        guard enableContainerDomains else {
            domainHealthy = false
            domainSummary = "Local domains disabled"
            return
        }

        isRefreshing = true
        let checks = await LocalDomainService.shared.checkSetup(suffix: normalizedSuffix)
        let failing = checks.filter { !$0.isPassing }
        domainHealthy = failing.isEmpty
        domainSummary = failing.isEmpty
            ? "Domains healthy (.\(normalizedSuffix))"
            : "\(failing.count) domain checks need attention"
        isRefreshing = false
    }

    private func openDomainIndex() {
        guard enableContainerDomains else { return }
        let scheme = preferHTTPSDomains ? "https" : "http"
        let suffix = normalizedSuffix.isEmpty ? "colima" : normalizedSuffix
        guard let url = URL(string: "\(scheme)://index.\(suffix)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openDomain(_ domain: String) {
        let scheme = preferHTTPSDomains ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(domain)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyDomains(_ domains: [String]) {
        let scheme = preferHTTPSDomains ? "https" : "http"
        let text = domains
            .map { "\(scheme)://\($0)" }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyDomainIndex() {
        let scheme = preferHTTPSDomains ? "https" : "http"
        let suffix = normalizedSuffix.isEmpty ? "colima" : normalizedSuffix
        let value = "\(scheme)://index.\(suffix)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

/// Root view that shows onboarding or main app based on dependency status
struct RootView: View {
    @State private var checker = DependencyChecker.shared
    @State private var hasCompletedOnboarding = false
    @State private var isChecking = true
    private let forceOnboarding = ProcessInfo.processInfo.arguments.contains("-force-onboarding")

    private var currentView: ViewState {
        if forceOnboarding {
            return .onboarding
        } else if isChecking {
            return .loading
        } else if checker.allDependenciesMet || hasCompletedOnboarding {
            return .main
        } else {
            return .onboarding
        }
    }

    private enum ViewState {
        case loading, onboarding, main
    }

    var body: some View {
        ZStack {
            Theme.contentBackground
                .ignoresSafeArea()

            switch currentView {
            case .loading:
                LoadingView()

            case .onboarding:
                OnboardingView(checker: checker) {
                    hasCompletedOnboarding = true
                }

            case .main:
                MainView()
            }
        }
        .task {
            await checker.checkAll()
            isChecking = false
        }
    }
}

/// Simple loading view (no animations for performance)
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.textSecondary)

            Text("ColimaUI")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(Theme.textPrimary)

            ProgressView()
                .controlSize(.small)

            Text("Checking dependencies...")
                .font(.caption)
                .foregroundColor(Theme.textMuted)
        }
    }
}
