import SwiftUI

/// Onboarding screen shown when dependencies are missing
struct OnboardingView: View {
    @Bindable var checker: DependencyChecker
    let onComplete: () -> Void
    @AppStorage("enableContainerDomains") private var enableContainerDomains: Bool = true
    @AppStorage("containerDomainSuffix") private var containerDomainSuffix: String = LocalDomainDefaults.suffix

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo/Title
            VStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)

                Text("ColimaUI")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                Text("A native macOS app for managing\nColima VMs and Docker containers")
                    .font(.body)
                    .foregroundColor(Theme.textMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 48)

            // Dependency checklist
            VStack(alignment: .leading, spacing: 16) {
                Text("Requirements")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)

                VStack(spacing: 12) {
                    DependencyRow(
                        name: "Homebrew",
                        description: "Package manager for macOS",
                        isInstalled: checker.hasHomebrew
                    )

                    DependencyRow(
                        name: "Colima",
                        description: "Container runtime for macOS",
                        isInstalled: checker.hasColima
                    )

                    DependencyRow(
                        name: "Docker CLI",
                        description: "Command-line interface for Docker",
                        isInstalled: checker.hasDocker
                    )

                    DependencyRow(
                        name: "colimaui CLI",
                        description: "Local domain helper (installed automatically)",
                        isInstalled: checker.hasColimaUICLI
                    )

                    DependencyRow(
                        name: "Local domains",
                        description: "DNS + resolver + proxy + TLS health checks",
                        isInstalled: checker.domainSetupHealthy
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: 400)
            .cardStyle()

            Spacer()

            // Actions
            VStack(spacing: 16) {
                if checker.isInstalling {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        Text(checker.installProgress)
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)

                        if !checker.lastFailedStep.isEmpty {
                            Text("Failed at: \(checker.lastFailedStep)")
                                .font(.caption2)
                                .foregroundColor(Theme.statusWarning)
                        }
                    }
                    .padding()
                } else if checker.isFullyReady {
                    Button {
                        onComplete()
                    } label: {
                        HStack {
                            Text("Get Started")
                            Image(systemName: "arrow.right")
                        }
                        .frame(maxWidth: 220)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button {
                        Task { await runInstallAndConfigure() }
                    } label: {
                        HStack {
                            Text(checker.lastFailedStep.isEmpty ? "Install and Configure Everything" : "Retry Setup")
                            Image(systemName: "wrench.and.screwdriver")
                        }
                        .frame(maxWidth: 300)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    if !checker.lastFailedStep.isEmpty {
                        Text("Failed at: \(checker.lastFailedStep)")
                            .font(.caption2)
                            .foregroundColor(Theme.statusWarning)
                    }

                    if !checker.lastFailureDetail.isEmpty {
                        Text(checker.lastFailureDetail)
                            .font(.caption)
                            .foregroundColor(Theme.statusWarning)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 520)
                    }

                }

                if !checker.isInstalling {
                    Button("Learn more about ColimaUI") {
                        checker.openColimaUIWebsite()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(Theme.accent)
                }
            }
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.contentBackground)
        .task {
            await checker.checkAll()
        }
    }

    private func runInstallAndConfigure() async {
        let suffix = LocalDomainDefaults.suffix
        containerDomainSuffix = suffix

        if await checker.installAndConfigureAll(domainSuffix: suffix) {
            enableContainerDomains = true
            onComplete()
        }
    }
}

struct DependencyRow: View {
    let name: String
    let description: String
    let isInstalled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isInstalled ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isInstalled ? Theme.statusRunning : Theme.textMuted)
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textPrimary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
            }

            Spacer()

            if isInstalled {
                Text("Installed")
                    .font(.caption)
                    .foregroundColor(Theme.statusRunning)
            }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                configuration.isPressed
                    ? Color.blue.opacity(0.6)
                    : Color.blue.opacity(0.8)
            )
            .foregroundColor(.white)
            .cornerRadius(8)
            .fontWeight(.medium)
    }
}

#Preview {
    OnboardingView(checker: DependencyChecker.shared) {
        print("Complete!")
    }
}
