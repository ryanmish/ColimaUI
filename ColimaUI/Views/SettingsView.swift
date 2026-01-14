import SwiftUI

/// App settings view
struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 2.0
    @AppStorage("showStoppedContainers") private var showStoppedContainers: Bool = true
    @State private var isColimaHovered = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                Text("Settings")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Theme.textPrimary)

                // Settings sections
                VStack(alignment: .leading, spacing: 24) {
                    // Refresh interval
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

                    Divider()
                        .background(Theme.cardBorder)

                    // Show stopped containers
                    SettingsRow(
                        icon: "eye",
                        title: "Show Stopped Containers",
                        subtitle: "Display exited containers in lists"
                    ) {
                        Toggle("", isOn: $showStoppedContainers)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )

                // About section
                VStack(alignment: .leading, spacing: 16) {
                    // App info
                    HStack(spacing: 12) {
                        Image(systemName: "cube.transparent.fill")
                            .font(.system(size: 32))
                            .foregroundColor(Theme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("ColimaUI")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)

                            Text("Version 1.0.0")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textMuted)
                        }
                    }

                    Text("A native macOS GUI for managing Colima virtual machines and Docker containers.")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSecondary)
                        .lineSpacing(2)

                    // Colima attribution
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

                    // ColimaUI copyright
                    Text("© 2025 Ryan Mish")
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
    }
}

struct SettingsRow<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let control: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 24)

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
        }
    }
}

#Preview {
    SettingsView()
}
