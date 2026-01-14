import SwiftUI
import Observation

/// Toast notification type
enum ToastType {
    case success
    case error
    case info

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: return Theme.statusRunning
        case .error: return .red.opacity(0.9)
        case .info: return Theme.accent
        }
    }
}

/// Toast notification manager
@MainActor
@Observable
class ToastManager {
    static let shared = ToastManager()

    var currentToast: Toast?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let type: ToastType
    }

    func show(_ message: String, type: ToastType = .info) {
        dismissTask?.cancel()

        currentToast = Toast(message: message, type: type)

        dismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                currentToast = nil
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        currentToast = nil
    }
}

/// Toast notification view
struct ToastView: View {
    let toast: ToastManager.Toast
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.type.icon)
                .foregroundColor(toast.type.color)

            Text(toast.message)
                .font(.system(size: 13))
                .foregroundColor(Theme.textPrimary)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.3))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(toast.type.color.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
    }
}

/// View modifier to show toasts
struct ToastModifier: ViewModifier {
    @State private var toastManager = ToastManager.shared

    func body(content: Content) -> some View {
        ZStack {
            content

            VStack {
                if let toast = toastManager.currentToast {
                    ToastView(toast: toast) {
                        toastManager.dismiss()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: toastManager.currentToast)
        }
    }
}

extension View {
    func withToasts() -> some View {
        modifier(ToastModifier())
    }
}
