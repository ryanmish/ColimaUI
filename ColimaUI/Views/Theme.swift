import SwiftUI

/// App-wide theme constants (Conductor-inspired dark glass design)
enum Theme {
    // MARK: - Colors

    static let contentBackground = Color(hex: "0f0f0f")
    static let cardBackground = Color.white.opacity(0.05)
    static let cardBackgroundSolid = Color(hex: "1a1a1a")
    static let cardBorder = Color.white.opacity(0.08)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textMuted = Color.white.opacity(0.4)

    static let statusRunning = Color.green.opacity(0.9)
    static let statusStopped = Color.white.opacity(0.3)
    static let statusWarning = Color.orange.opacity(0.9)

    static let accent = Color.blue.opacity(0.8)

    // MARK: - Dimensions

    static let cornerRadius: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let spacing: CGFloat = 12
    static let sidebarWidth: CGFloat = 280

    // MARK: - Animation

    static let animationFast: Animation = .easeOut(duration: 0.15)
    static let animationDefault: Animation = .easeInOut(duration: 0.25)
    static let animationSlow: Animation = .easeInOut(duration: 0.4)
    static let animationSpring: Animation = .spring(response: 0.35, dampingFraction: 0.7)
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    var useGlass: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(Theme.cardPadding)
            .background {
                if useGlass {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                .fill(Color.white.opacity(0.03))
                        )
                } else {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .fill(Theme.cardBackgroundSolid)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
    }
}

struct AppearAnimation: ViewModifier {
    @State private var hasAppeared = false
    var delay: Double = 0

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
            .onAppear {
                withAnimation(Theme.animationDefault.delay(delay)) {
                    hasAppeared = true
                }
            }
    }
}

extension View {
    func cardStyle(glass: Bool = true) -> some View {
        modifier(CardStyle(useGlass: glass))
    }

    func appearAnimation(delay: Double = 0) -> some View {
        modifier(AppearAnimation(delay: delay))
    }
}

// MARK: - Button Styles

struct GlassButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .background(
                configuration.isPressed
                    ? Color.white.opacity(0.12)
                    : Color.white.opacity(0.05)
            )
            .foregroundColor(isDestructive ? .red.opacity(0.9) : Theme.textPrimary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Theme.animationFast, value: configuration.isPressed)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(8)
            .background(
                configuration.isPressed
                    ? Color.white.opacity(0.15)
                    : Color.white.opacity(0.05)
            )
            .cornerRadius(6)
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(Theme.animationFast, value: configuration.isPressed)
    }
}

// MARK: - Animated Components

/// Progress bar for stats (no animation for performance)
struct AnimatedProgressBar: View {
    let value: Double // 0-100
    var color: Color = Theme.accent

    private var clampedValue: Double {
        min(max(value, 0), 100) / 100
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.1))

            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .scaleEffect(x: clampedValue, y: 1, anchor: .leading)
        }
        .frame(height: 4)
        .accessibilityValue("\(Int(value))%")
    }
}

/// Status dot (static for performance)
struct PulsingDot: View {
    var isActive: Bool
    var color: Color = Theme.statusRunning

    var body: some View {
        Circle()
            .fill(isActive ? color : Theme.statusStopped)
            .frame(width: 8, height: 8)
            .accessibilityLabel(isActive ? "Running" : "Stopped")
    }
}

/// Checkmark animation for success feedback
struct AnimatedCheckmark: View {
    @State private var isAnimating = false

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 48))
            .foregroundColor(Theme.statusRunning)
            .scaleEffect(isAnimating ? 1.0 : 0.5)
            .opacity(isAnimating ? 1.0 : 0)
            .onAppear {
                withAnimation(Theme.animationSpring) {
                    isAnimating = true
                }
            }
    }
}

/// Hover scale effect modifier
struct HoverEffect: ViewModifier {
    @State private var isHovered = false
    var scale: CGFloat = 1.02

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .animation(Theme.animationFast, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    func hoverEffect(scale: CGFloat = 1.02) -> some View {
        modifier(HoverEffect(scale: scale))
    }

    func tooltip(_ text: String) -> some View {
        modifier(TooltipModifier(text: text))
    }
}

// MARK: - Custom Tooltip

struct TooltipModifier: ViewModifier {
    let text: String
    @State private var isHovered = false
    @State private var showTooltip = false
    @State private var tooltipTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovered = hovering
                tooltipTask?.cancel()
                if hovering {
                    tooltipTask = Task {
                        do {
                            try await Task.sleep(for: .milliseconds(500))
                        } catch {
                            return
                        }
                        if isHovered && !Task.isCancelled {
                            withAnimation(.easeOut(duration: 0.15)) {
                                showTooltip = true
                            }
                        }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.1)) {
                        showTooltip = false
                    }
                }
            }
            .onDisappear {
                tooltipTask?.cancel()
            }
            .overlay(alignment: .top) {
                if showTooltip {
                    TooltipView(text: text)
                        .offset(y: -32)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                }
            }
    }
}

struct TooltipView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(hex: "2a2a2a"))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .fixedSize()
    }
}
