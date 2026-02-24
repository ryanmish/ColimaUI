import SwiftUI
import AppKit

/// App settings view
struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 2.0
    @AppStorage("showStoppedContainers") private var showStoppedContainers: Bool = true
    @AppStorage("enableContainerDomains") private var enableContainerDomains: Bool = true
    @AppStorage("containerDomainSuffix") private var containerDomainSuffix: String = LocalDomainDefaults.suffix
    @AppStorage("preferHTTPSDomains") private var preferHTTPSDomains: Bool = false
    @State private var isColimaHovered = false
    @State private var autopilot = LocalDomainsAutopilot.shared
    @State private var setupChecks: [LocalDomainCheck] = []
    @State private var isAutoSetupRunning = false
    @State private var setupStatusLabel: String = "Pending"
    @State private var setupTask: Task<Void, Never>?
    @State private var showOnboardingSheet = false
    @State private var showTechnicalChecks = false
    @State private var showAdvancedTools = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Settings")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Theme.textPrimary)

                VStack(alignment: .leading, spacing: 24) {
                    SettingsRow(
                        icon: "arrow.clockwise",
                        title: "Refresh Interval",
                        subtitle: "How often to update container stats"
                    ) {
                        Picker("", selection: $refreshInterval) {
                            Text("1s").tag(1.0)
                            Text("2s").tag(2.0)
                            Text("5s").tag(5.0)
                            Text("10s").tag(10.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }

                    Divider().background(Theme.cardBorder)

                    SettingsRow(
                        icon: "eye",
                        title: "Show Stopped Containers",
                        subtitle: "Display exited containers in lists"
                    ) {
                        Toggle("", isOn: $showStoppedContainers)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    Divider().background(Theme.cardBorder)

                    SettingsRow(
                        icon: "network",
                        title: "Local Domains",
                        subtitle: "Show domain links for containers"
                    ) {
                        Toggle("", isOn: $enableContainerDomains)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    SettingsRow(
                        icon: "lock",
                        title: "Prefer HTTPS",
                        subtitle: "Open domain links with https:// instead of http://"
                    ) {
                        Toggle("", isOn: $preferHTTPSDomains)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(!enableContainerDomains)
                    }

                    SettingsRow(
                        icon: "sparkles",
                        title: "Local Domains Autopilot",
                        subtitle: "Automatically reconciles routes and repairs .\(LocalDomainDefaults.suffix) setup"
                    ) {
                        autopilotControls
                    }

                    SettingsRow(
                        icon: "wrench.and.screwdriver",
                        title: "Advanced Tools",
                        subtitle: "Manual setup/check/unsetup and technical diagnostics"
                    ) {
                        setupActionButton(title: showAdvancedTools ? "Hide" : "Show") {
                            showAdvancedTools.toggle()
                        }
                    }

                    SettingsRow(
                        icon: "list.clipboard",
                        title: "Onboarding",
                        subtitle: "Open onboarding again to re-run full install and setup"
                    ) {
                        Button("Open") {
                            showOnboardingSheet = true
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.07))
                        .cornerRadius(6)
                        .disabled(isAutoSetupRunning)
                    }

                    SettingsRow(
                        icon: "list.bullet.rectangle",
                        title: "Domain Index",
                        subtitle: "Open the live local-domain index page"
                    ) {
                        domainIndexControls
                    }

                    if enableContainerDomains {
                        if showAdvancedTools {
                            setupPermissionNote

                            Divider().background(Theme.cardBorder)

                            automaticSetupControls

                            if !setupChecks.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(localDomainSummaryChecks) { check in
                                        LocalDomainCheckRow(check: check)
                                    }
                                }

                                Button(showTechnicalChecks ? "Hide technical checks" : "Show technical checks") {
                                    showTechnicalChecks.toggle()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.07))
                                .cornerRadius(6)
                            }

                            if showTechnicalChecks {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(setupChecks) { check in
                                        LocalDomainCheckRow(check: check)
                                    }
                                }
                            }

                            Divider().background(Theme.cardBorder)
                        }

                        devWorkflowCopyPack
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "cube.transparent.fill")
                            .font(.system(size: 32))
                            .foregroundColor(Theme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("ColimaUI")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)

                            Text("Version \(appVersion)")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textMuted)
                        }

                        Spacer()

                        Link(destination: URL(string: "https://github.com/ryanmish/ColimaUI")!) {
                            Image("GitHubIcon")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                                .foregroundColor(Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("A native macOS GUI for managing Colima virtual machines and Docker containers.")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSecondary)
                        .lineSpacing(2)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("POWERED BY")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.textMuted)
                            .tracking(0.5)

                        Link(destination: URL(string: "https://github.com/abiosoft/colima")!) {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 10) {
                                    Image(systemName: "shippingbox.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(Theme.textSecondary)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Colima")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(Theme.textPrimary)

                                        Text("Container runtimes on macOS")
                                            .font(.system(size: 11))
                                            .foregroundColor(Theme.textMuted)
                                    }

                                    Spacer()

                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.textMuted)
                                }
                                .padding(12)

                                Text("© 2021 Abiola Ibrahim · MIT License")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.textMuted)
                                    .padding(.leading, 38)
                                    .padding(.bottom, 10)
                            }
                            .background(Color.white.opacity(isColimaHovered ? 0.08 : 0.04))
                            .cornerRadius(8)
                            .animation(.easeOut(duration: 0.15), value: isColimaHovered)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            isColimaHovered = hovering
                        }
                    }

                    Text("© 2026 Ryan Mish")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textMuted)
                }
                .padding(16)
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )

                Spacer()
            }
            .padding(24)
        }
        .background(Theme.contentBackground)
        .sheet(isPresented: $showOnboardingSheet) {
            OnboardingView(checker: DependencyChecker.shared) {
                showOnboardingSheet = false
            }
            .frame(minWidth: 900, minHeight: 600)
        }
        .onAppear {
            autopilot.start()
            containerDomainSuffix = LocalDomainDefaults.suffix
            applyDomainSuffix(LocalDomainDefaults.suffix, triggerCheck: enableContainerDomains)
            if enableContainerDomains {
                Task { await autopilot.reconcileNow() }
            }
        }
        .onChange(of: enableContainerDomains) { _, enabled in
            if enabled {
                applyDomainSuffix(LocalDomainDefaults.suffix, triggerCheck: true)
                Task { await autopilot.reconcileNow() }
            } else {
                setupChecks = []
                showTechnicalChecks = false
                showAdvancedTools = false
                setupTask?.cancel()
                setupStatusLabel = "Pending"
            }
        }
        .onDisappear {
            setupTask?.cancel()
        }
    }

    private func normalizedDomainSuffix(_ value: String) -> String {
        _ = value
        return LocalDomainDefaults.suffix
    }

    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }

    private func applyDomainSuffix(_ rawValue: String, triggerCheck: Bool) {
        _ = rawValue
        let normalized = LocalDomainDefaults.suffix

        let changed = normalized != containerDomainSuffix
        containerDomainSuffix = normalized

        guard enableContainerDomains, triggerCheck else { return }
        if changed {
            ToastManager.shared.show("Using .\(normalized) for local domains", type: .success)
            if hasLocalDomainSystemInstalled {
                setupStatusLabel = "Suffix changed. Reconfiguring..."
                runAutomaticSetupAndCheck(for: normalized)
                return
            }
        }
        runSetupCheckOnly(for: normalized)
    }

    private func runAutomaticSetupAndCheck(for suffix: String) {
        guard !suffix.isEmpty else { return }
        setupTask?.cancel()
        isAutoSetupRunning = true
        setupStatusLabel = "Running one-click setup..."

        setupTask = Task {
            do {
                let checks = try await LocalDomainService.shared.setupAndCheck(suffix: suffix)
                if !Task.isCancelled {
                    setupChecks = checks
                    setupStatusLabel = checks.allSatisfy(\.isPassing) ? "Healthy" : "Needs attention"
                }
                isAutoSetupRunning = false
            } catch is CancellationError {
                isAutoSetupRunning = false
                setupStatusLabel = "Cancelled"
            } catch {
                let checks = await LocalDomainService.shared.checkSetup(suffix: suffix)
                if !Task.isCancelled {
                    setupChecks = checks
                    setupStatusLabel = "Needs attention"
                }
                isAutoSetupRunning = false
                ToastManager.shared.show("Auto setup failed: \(error.localizedDescription)", type: .error)
            }
        }
    }

    private func runSetupCheckOnly(for suffix: String) {
        guard !suffix.isEmpty else { return }
        setupTask?.cancel()
        isAutoSetupRunning = true
        setupStatusLabel = "Checking..."

        setupTask = Task {
            let checks = await LocalDomainService.shared.checkSetup(suffix: suffix)
            if !Task.isCancelled {
                setupChecks = checks
                setupStatusLabel = checks.allSatisfy(\.isPassing) ? "Healthy" : "Needs attention"
            }
            isAutoSetupRunning = false
        }
    }

    private func runAutomaticUnsetup(for suffix: String) {
        guard !suffix.isEmpty else { return }
        setupTask?.cancel()
        isAutoSetupRunning = true
        setupStatusLabel = "Removing..."

        setupTask = Task {
            do {
                let checks = try await LocalDomainService.shared.unsetup(suffix: suffix)
                if !Task.isCancelled {
                    setupChecks = checks
                    setupStatusLabel = "Removed"
                    ToastManager.shared.show("Local-domain setup removed for .\(suffix)", type: .success)
                }
                isAutoSetupRunning = false
            } catch is CancellationError {
                isAutoSetupRunning = false
                setupStatusLabel = "Cancelled"
            } catch {
                isAutoSetupRunning = false
                setupStatusLabel = "Needs attention"
                ToastManager.shared.show("Unsetup failed: \(error.localizedDescription)", type: .error)
            }
        }
    }

    private func runTrustTLS(for suffix: String) {
        guard !suffix.isEmpty else { return }
        setupTask?.cancel()
        isAutoSetupRunning = true
        setupStatusLabel = "Trusting TLS..."

        setupTask = Task {
            do {
                let checks = try await LocalDomainService.shared.trustTLS(suffix: suffix)
                if !Task.isCancelled {
                    setupChecks = checks
                    setupStatusLabel = checks.allSatisfy(\.isPassing) ? "Healthy" : "Needs attention"
                    ToastManager.shared.show("TLS trust refreshed for .\(suffix)", type: .success)
                }
                isAutoSetupRunning = false
            } catch is CancellationError {
                isAutoSetupRunning = false
                setupStatusLabel = "Cancelled"
            } catch {
                isAutoSetupRunning = false
                setupStatusLabel = "Needs attention"
                ToastManager.shared.show("TLS trust failed: \(error.localizedDescription)", type: .error)
            }
        }
    }

    private func openDomainIndex() {
        let normalized = normalizedDomainSuffix(containerDomainSuffix)
        guard !normalized.isEmpty else { return }

        let scheme = preferHTTPSDomains ? "https" : "http"
        if let url = URL(string: "\(scheme)://index.\(normalized)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func copyDomainIndex() {
        let normalized = normalizedDomainSuffix(containerDomainSuffix)
        guard !normalized.isEmpty else { return }

        let scheme = preferHTTPSDomains ? "https" : "http"
        let url = "\(scheme)://index.\(normalized)"
        copyToClipboard(url, message: "Copied \(url)")
    }

    private func copyAgentContext() {
        let suffix = normalizedDomainSuffix(containerDomainSuffix)
        guard !suffix.isEmpty else { return }

        let scheme = preferHTTPSDomains ? "https" : "http"
        let context = """
        ## ColimaUI Local Domains Context
        ColimaUI is a macOS app for managing Colima VMs and Docker containers. Colima runs the containers; ColimaUI provides stable local routing on `.\(suffix)` so multi-service projects behave like deployed environments without localhost port collisions.

        ### Non-negotiables
        - Domain suffix is fixed to `.\(suffix)`.
        - Keep Local Domains Autopilot enabled in ColimaUI settings.
        - Use domain URLs instead of localhost ports for web services.
        - Index URL: `\(scheme)://index.\(suffix)`

        ### Startup Checks
        1. Ensure Colima and Docker are reachable: `colima status && docker info`
        2. Ensure local-domain stack is healthy: `colimaui domains check`

        ### Standard Agent Workflow
        1. Start services from project root: `docker compose up -d`
        2. Force route sync: `colimaui domains sync`
        3. Poll for routes until expected services appear: `colimaui domains urls --json`
        4. Use discovered URLs for integration tests, API calls, browser checks, and agent outputs.
        5. Continue only when `colimaui domains check` is all PASS.

        ### Domain Patterns
        - Compose service: `<service>.<project>.\(suffix)`
        - Container fallback: `<container-name>.\(suffix)`
        - Optional explicit domains label: `dev.colimaui.domains=foo.\(suffix),bar.\(suffix)`
        - Optional HTTP port label: `dev.colimaui.http-port=8080`

        ### Recovery
        - If routes are missing: `colimaui domains sync && colimaui domains urls --json`
        - If health fails: `colimaui domains check`
        - If TLS trust fails: `colimaui domains trust && colimaui domains check`
        - If setup is broken: `colimaui domains setup && colimaui domains check`
        - Full teardown: `colimaui domains unsetup`
        - macOS prompts can appear for DNS/resolver and certificate trust operations.

        ### Placement
        - Paste into `AGENTS.md` or `CLAUDE.md` (Claude Code).
        """

        copyToClipboard(context, message: "Copied agent context")
    }

    private func copyToClipboard(_ text: String, message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ToastManager.shared.show(message, type: .success)
    }

    private var isLocalDomainSetupHealthy: Bool {
        !setupChecks.isEmpty && setupChecks.allSatisfy(\.isPassing)
    }

    private var hasLocalDomainSystemInstalled: Bool {
        let nonBaselineChecks = setupChecks.filter { check in
            check.id != "brew" && check.id != "colima" && check.id != "docker"
        }
        return nonBaselineChecks.contains(where: { $0.isPassing })
    }

    private var localDomainSummaryChecks: [LocalDomainCheck] {
        guard !setupChecks.isEmpty else { return [] }

        return [
            summaryCheck(
                id: "summary-runtime",
                title: "Runtime",
                detailWhenPassing: "Colima, Docker, and required tools are available",
                checkIDs: ["brew", "colima", "docker"]
            ),
            summaryCheck(
                id: "summary-routing",
                title: "Domain routing",
                detailWhenPassing: "Domain routing is configured for .\(LocalDomainDefaults.suffix)",
                checkIDs: ["dnsmasq-binary", "dnsmasq-service", "dnsmasq-wildcard", "resolver", "resolution", "proxy"]
            ),
            summaryCheck(
                id: "summary-https",
                title: "HTTPS",
                detailWhenPassing: "Trusted TLS is working for \(LocalDomainDefaults.indexHost)",
                checkIDs: ["mkcert", "cert", "index", "tls-trust"]
            )
        ]
    }

    private func summaryCheck(id: String, title: String, detailWhenPassing: String, checkIDs: Set<String>) -> LocalDomainCheck {
        let subset = setupChecks.filter { checkIDs.contains($0.id) }
        if subset.isEmpty {
            return LocalDomainCheck(id: id, title: title, isPassing: false, detail: "Not checked yet")
        }

        let failures = subset.filter { !$0.isPassing }
        if failures.isEmpty {
            return LocalDomainCheck(id: id, title: title, isPassing: true, detail: detailWhenPassing)
        }

        let headline = failures.first?.title ?? "Needs attention"
        return LocalDomainCheck(id: id, title: title, isPassing: false, detail: "Needs attention: \(headline)")
    }

    private var autopilotControls: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                Text(autopilot.status)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(autopilot.isHealthy ? Theme.statusRunning : Theme.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background((autopilot.isHealthy ? Theme.statusRunning : Theme.textSecondary).opacity(0.12))
                    .cornerRadius(6)

                setupActionButton(title: "Repair now") {
                    Task {
                        await autopilot.reconcileNow()
                        runSetupCheckOnly(for: normalizedDomainSuffix(containerDomainSuffix))
                    }
                }
            }

            Text(autopilot.detail)
                .font(.system(size: 11))
                .foregroundColor(Theme.textMuted)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .frame(width: 320, alignment: .trailing)

            if let lastReconciledAt = autopilot.lastReconciledAt {
                Text("Last check \(lastReconciledAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textMuted.opacity(0.75))
            }
        }
    }

    private var automaticSetupControls: some View {
        HStack(spacing: 10) {
            let suffix = normalizedDomainSuffix(containerDomainSuffix)

            setupPrimaryActionButton(title: isLocalDomainSetupHealthy ? "Re-run Setup" : "One-Click Setup") {
                runAutomaticSetupAndCheck(for: suffix)
            }

            setupActionButton(title: "Check") {
                runSetupCheckOnly(for: suffix)
            }

            setupActionButton(title: "Trust TLS") {
                runTrustTLS(for: suffix)
            }

            if hasLocalDomainSystemInstalled {
                setupActionButton(title: "Unsetup") {
                    runAutomaticUnsetup(for: suffix)
                }
            }

            if isAutoSetupRunning {
                ProgressView()
                    .controlSize(.small)
            }

            Text(setupStatusLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textMuted)
        }
    }

    private var setupPermissionNote: some View {
        Text("Autopilot runs non-privileged checks/sync. Admin prompts appear only when you run setup/unsetup, and TLS trust can prompt separately in Keychain.")
            .font(.system(size: 11))
            .foregroundColor(Theme.textMuted)
    }

    private var devWorkflowCopyPack: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Agent Context")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                setupActionButton(title: "Copy Context", action: copyAgentContext)
            }

            Text("Copy once and paste into `AGENTS.md` or `CLAUDE.md` (Claude Code) so assistants follow the same local-domain workflow.")
                .font(.system(size: 11))
                .foregroundColor(Theme.textMuted)
        }
        .padding(.horizontal, 2)
    }

    private var domainIndexControls: some View {
        HStack(spacing: 8) {
            Button("Open", action: openDomainIndex)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.07))
                .cornerRadius(6)
                .disabled(!enableContainerDomains)

            Button {
                copyDomainIndex()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
                    .padding(7)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .tooltip("Copy index URL")
            .disabled(!enableContainerDomains)
        }
    }

    private func setupActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.07))
            .cornerRadius(6)
            .disabled(!enableContainerDomains || isAutoSetupRunning)
    }

    private func setupPrimaryActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                LinearGradient(
                    colors: [Theme.accent.opacity(0.95), Theme.accent.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(7)
            .disabled(!enableContainerDomains || isAutoSetupRunning)
            .opacity((!enableContainerDomains || isAutoSetupRunning) ? 0.5 : 1.0)
    }
}

struct SettingsRow<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let control: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
            }

            Spacer()

            control()
                .frame(maxWidth: 420, alignment: .trailing)
        }
    }
}

private struct LocalDomainCheckRow: View {
    let check: LocalDomainCheck

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: check.isPassing ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(check.isPassing ? Theme.statusRunning : Theme.statusWarning)

            VStack(alignment: .leading, spacing: 1) {
                Text(check.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textPrimary)

                Text(check.detail)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }
}

#Preview {
    SettingsView()
}
