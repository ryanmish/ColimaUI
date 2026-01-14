import SwiftUI

/// Container logs viewer with live streaming
struct ContainerLogsView: View {
    let container: Container
    let docker: DockerService

    @State private var logs: String = "Loading logs..."
    @State private var isStreaming = false
    @State private var logProcess: Process?
    @State private var searchText = ""
    @State private var tailLines = 200
    @Environment(\.dismiss) private var dismiss

    private var filteredLogs: String {
        if searchText.isEmpty {
            return logs
        }
        let lines = logs.components(separatedBy: "\n")
        let filtered = lines.filter { $0.localizedCaseInsensitiveContains(searchText) }
        return filtered.isEmpty ? "No matching logs" : filtered.joined(separator: "\n")
    }

    private var matchCount: Int {
        if searchText.isEmpty { return 0 }
        let lines = logs.components(separatedBy: "\n")
        return lines.filter { $0.localizedCaseInsensitiveContains(searchText) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Logs")
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                    Text(container.name)
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                }

                Spacer()

                // Search
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Theme.textMuted)
                        .font(.system(size: 11))

                    TextField("Filter logs...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textPrimary)
                        .frame(width: 120)

                    if !searchText.isEmpty {
                        Text("\(matchCount)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.textMuted)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(3)

                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Theme.textMuted)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)

                Toggle(isOn: $isStreaming) {
                    Text("Live")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: isStreaming) { _, newValue in
                    if newValue {
                        startStreaming()
                    } else {
                        stopStreaming()
                    }
                }

                Button {
                    Task { await loadLogs() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(GlassButtonStyle())

                Button("Close") {
                    stopStreaming()
                    dismiss()
                }
                .buttonStyle(GlassButtonStyle())
            }
            .padding()
            .background(Theme.cardBackground)

            // Log content
            ScrollView {
                ScrollViewReader { proxy in
                    Text(filteredLogs)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("logs")
                        .onChange(of: logs) {
                            if isStreaming && searchText.isEmpty {
                                proxy.scrollTo("logs", anchor: .bottom)
                            }
                        }
                }
            }
            .background(Theme.contentBackground)

            // Footer with stats
            HStack {
                Text("\(logs.components(separatedBy: "\n").count) lines")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)

                Spacer()

                if isStreaming {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Theme.statusRunning)
                            .frame(width: 6, height: 6)
                        Text("Streaming")
                            .font(.caption)
                            .foregroundColor(Theme.statusRunning)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.cardBackground)
        }
        .frame(minWidth: 700, minHeight: 500)
        .task {
            await loadLogs()
        }
        .onDisappear {
            stopStreaming()
        }
    }

    private func loadLogs() async {
        logs = await docker.getLogs(container.containerID, tail: 200)
    }

    private func startStreaming() {
        Task {
            logProcess = await docker.streamLogs(container.containerID) { output in
                logs += output
            }
        }
    }

    private func stopStreaming() {
        logProcess?.terminate()
        logProcess = nil
    }
}

#Preview {
    ContainerLogsView(
        container: Container(
            containerID: "abc123",
            Names: "test-container",
            Image: "test",
            State: "running",
            Status: "Up",
            Ports: "",
            Labels: "",
            CreatedAt: ""
        ),
        docker: DockerService.shared
    )
}
