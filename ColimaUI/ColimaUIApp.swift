import SwiftUI

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
    }
}

/// Root view that shows onboarding or main app based on dependency status
struct RootView: View {
    @State private var checker = DependencyChecker.shared
    @State private var hasCompletedOnboarding = false
    @State private var isChecking = true

    private var currentView: ViewState {
        if isChecking {
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
