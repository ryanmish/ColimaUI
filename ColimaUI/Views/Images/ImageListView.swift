import SwiftUI

/// List of Docker images
struct ImageListView: View {
    @Bindable var viewModel: AppViewModel

    @State private var searchText = ""
    @State private var isLoading = false
    @State private var showRemoveAlert = false
    @State private var imageToRemove: DockerImage?
    @FocusState private var isSearchFocused: Bool

    private var filteredImages: [DockerImage] {
        if searchText.isEmpty {
            return viewModel.docker.images
        }
        return viewModel.docker.images.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var totalSize: String {
        let bytes = viewModel.docker.images.reduce(0) { $0 + $1.sizeBytes }
        if bytes > 1_073_741_824 {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
        } else {
            return String(format: "%.0f MB", Double(bytes) / 1_048_576)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Images")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.textPrimary)

                    Spacer()

                    Button {
                        Task {
                            isLoading = true
                            await viewModel.refreshImagesAndDisk()
                            isLoading = false
                        }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(GlassButtonStyle())
                }

                HStack(spacing: 12) {
                    Text("\(viewModel.docker.images.count) images")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)

                    Text("·")
                        .foregroundColor(Theme.textMuted)

                    Text(totalSize)
                        .font(.subheadline)
                        .foregroundColor(Theme.textMuted)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.textMuted)
                    .font(.system(size: 12))

                TextField("Search images...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.textMuted)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Image list
            if filteredImages.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredImages) { image in
                            ImageRowView(
                                image: image,
                                onRemove: {
                                    imageToRemove = image
                                    showRemoveAlert = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(Theme.contentBackground)
        .task {
            await viewModel.refreshImagesAndDisk()
        }
        .alert("Remove Image", isPresented: $showRemoveAlert, presenting: imageToRemove) { image in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task { await viewModel.docker.removeImage(image.imageID, force: true) }
            }
        } message: { image in
            Text("Are you sure you want to remove \"\(image.fullName)\"? This action cannot be undone.")
        }
        .background {
            Button("") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: searchText.isEmpty ? "square.stack.3d.up" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(Theme.textMuted)

            if searchText.isEmpty {
                Text("No images")
                    .font(.headline)
                    .foregroundColor(Theme.textSecondary)

                Text("Docker images will appear here")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
            } else {
                Text("No results")
                    .font(.headline)
                    .foregroundColor(Theme.textSecondary)

                Text("No images match \"\(searchText)\"")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)

                Button("Clear search") {
                    searchText = ""
                }
                .buttonStyle(GlassButtonStyle())
                .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ImageRowView: View {
    let image: DockerImage
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: image.isNone ? "square.dashed" : "square.stack.3d.up")
                .foregroundColor(image.isNone ? Theme.textMuted : Theme.textSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(image.fullName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(image.isNone ? Theme.textMuted : Theme.textPrimary)
                    .lineLimit(1)

                Text(image.imageID.prefix(12))
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
                    .fontDesign(.monospaced)
            }

            Spacer()

            Text(image.Size)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Theme.textSecondary)

            Button {
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.8))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .tooltip("Remove image")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.white.opacity(0.05) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    ImageListView(viewModel: AppViewModel())
}
