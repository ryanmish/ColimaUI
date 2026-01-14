import SwiftUI

/// Onboarding screen shown when dependencies are missing
struct OnboardingView: View {
    @Bindable var checker: DependencyChecker
    let onComplete: () -> Void

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
                        isInstalled: checker.hasHomebrew,
                        isRequired: !checker.hasHomebrew && !checker.hasColima
                    )

                    DependencyRow(
                        name: "Colima",
                        description: "Container runtime for macOS",
                        isInstalled: checker.hasColima,
                        isRequired: true
                    )

                    DependencyRow(
                        name: "Docker CLI",
                        description: "Command-line interface for Docker",
                        isInstalled: checker.hasDocker,
                        isRequired: true
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
                    }
                    .padding()
                } else if checker.allDependenciesMet {
                    Button {
                        onComplete()
                    } label: {
                        HStack {
                            Text("Get Started")
                            Image(systemName: "arrow.right")
                        }
                        .frame(maxWidth: 200)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else if !checker.hasHomebrew {
                    VStack(spacing: 12) {
                        Text("Homebrew is required to install Colima")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)

                        HStack(spacing: 12) {
                            Button("Install Homebrew") {
                                Task { await checker.installHomebrew() }
                            }
                            .buttonStyle(PrimaryButtonStyle())

                            Button("Open brew.sh") {
                                checker.openHomebrewWebsite()
                            }
                            .buttonStyle(GlassButtonStyle())
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Button("Install Colima & Docker") {
                            Task {
                                if await checker.installColima() {
                                    // Small delay then continue
                                    try? await Task.sleep(for: .seconds(1))
                                    onComplete()
                                }
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button("Learn more about Colima") {
                            checker.openColimaWebsite()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundColor(Theme.accent)
                    }
                }

                // Manual refresh
                if !checker.isInstalling && !checker.allDependenciesMet {
                    Button("I've already installed them") {
                        Task { await checker.checkAll() }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
                    .padding(.top, 8)
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
}

struct DependencyRow: View {
    let name: String
    let description: String
    let isInstalled: Bool
    let isRequired: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isInstalled ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isInstalled ? Theme.statusRunning : Theme.textMuted)
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.textPrimary)

                    if isRequired && !isInstalled {
                        Text("Required")
                            .font(.caption2)
                            .foregroundColor(Theme.statusWarning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.statusWarning.opacity(0.15))
                            .cornerRadius(4)
                    }
                }

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
