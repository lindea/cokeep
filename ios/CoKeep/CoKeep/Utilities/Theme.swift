import SwiftUI

enum Theme {
    static let ink = Color(red: 0.09, green: 0.16, blue: 0.14)
    static let muted = Color(red: 0.35, green: 0.42, blue: 0.39)
    static let accent = Color(red: 0.12, green: 0.42, blue: 0.36) // deep fjord teal
    static let accentSoft = Color(red: 0.78, green: 0.90, blue: 0.86)
    static let warm = Color(red: 0.72, green: 0.45, blue: 0.18) // amber CTA
    static let danger = Color(red: 0.70, green: 0.22, blue: 0.18)
    static let cardFill = Color.white.opacity(0.72)

    static var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.93, green: 0.96, blue: 0.94),
                Color(red: 0.86, green: 0.91, blue: 0.89),
                Color(red: 0.90, green: 0.93, blue: 0.95),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func brandFont(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(filled ? Color.white : Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(filled ? Theme.accent : Theme.accentSoft.opacity(0.5))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Toolbar confirm button that shows a spinner and blocks repeat taps while busy.
struct BusyToolbarButton: View {
    let title: String
    var enabled: Bool = true
    let loading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if loading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(title)
            }
        }
        .disabled(!enabled || loading)
    }
}
