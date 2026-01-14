import SwiftUI

/// Sheet for creating a new VM profile
struct CreateProfileSheet: View {
    @Bindable var viewModel: AppViewModel
    @Binding var isPresented: Bool

    @State private var profileName = ""
    @State private var cpuCount = 2
    @State private var memoryGB = 2
    @State private var diskGB = 60
    @State private var isCreating = false

    private var isValid: Bool {
        !profileName.isEmpty &&
        !profileName.contains(" ") &&
        profileName.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil &&
        !viewModel.colima.vms.contains { $0.name == profileName }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New VM Profile")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color.black.opacity(0.3))

            // Form
            VStack(alignment: .leading, spacing: 20) {
                // Profile name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Profile Name")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)

                    TextField("e.g., work, testing", text: $profileName)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.cardBorder, lineWidth: 1)
                        )
                        .disabled(isCreating)

                    Text("Letters, numbers, hyphens, underscores only")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                }

                // CPU
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("CPU Cores")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)

                        Spacer()

                        Text("\(cpuCount)")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.textPrimary)
                    }

                    Slider(value: Binding(
                        get: { Double(cpuCount) },
                        set: { cpuCount = Int($0) }
                    ), in: 1...8, step: 1)
                    .tint(Theme.accent)
                    .disabled(isCreating)
                }

                // Memory
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Memory")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)

                        Spacer()

                        Text("\(memoryGB) GB")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.textPrimary)
                    }

                    Slider(value: Binding(
                        get: { Double(memoryGB) },
                        set: { memoryGB = Int($0) }
                    ), in: 2...16, step: 1)
                    .tint(Theme.accent)
                    .disabled(isCreating)
                }

                // Disk
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Disk Size")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)

                        Spacer()

                        Text("\(diskGB) GB")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.textPrimary)
                    }

                    Slider(value: Binding(
                        get: { Double(diskGB) },
                        set: { diskGB = Int($0) }
                    ), in: 20...200, step: 10)
                    .tint(Theme.accent)
                    .disabled(isCreating)
                }

                Spacer()

                // Create button
                Button {
                    Task {
                        isCreating = true
                        await viewModel.createProfile(
                            name: profileName,
                            cpus: cpuCount,
                            memory: memoryGB,
                            disk: diskGB
                        )
                        isCreating = false
                        isPresented = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isCreating {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                            Text("Creating...")
                        } else {
                            Text("Create Profile")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(isCreating ? Theme.accent : (isValid ? Theme.accent : Theme.accent.opacity(0.3)))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!isValid || isCreating)

                if isCreating {
                    Text("This may take a few minutes...")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
            }
            .padding(20)
        }
        .frame(width: 400, height: 480)
        .background(Theme.contentBackground)
    }
}

#Preview {
    CreateProfileSheet(viewModel: AppViewModel(), isPresented: .constant(true))
}
