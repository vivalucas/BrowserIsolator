import SwiftUI

// Shared desktop proportions. Native toolbars and system alerts retain their
// platform behavior; content actions use this single surface and state model.
enum DesktopControlMetrics {
    static let regularHeight: CGFloat = 32
    static let compactHeight: CGFloat = 28
    static let minimumActionWidth: CGFloat = 88
    static let actionColumnWidth: CGFloat = 156
    static let cornerRadius: CGFloat = 6
    static let horizontalInset: CGFloat = 12
    static let fontSize: CGFloat = 12
}

struct AppActionButtonStyle: ButtonStyle {
    enum Width { case content, column }
    enum Emphasis { case standard, primary }

    var width: Width = .content
    var emphasis: Emphasis = .standard
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: DesktopControlMetrics.fontSize, weight: .medium))
            .lineLimit(nil)
            .multilineTextAlignment(.center)
            .frame(width: width == .column ? DesktopControlMetrics.actionColumnWidth - 2 * DesktopControlMetrics.horizontalInset : nil)
            .fixedSize(horizontal: width == .content, vertical: true)
            .padding(.horizontal, DesktopControlMetrics.horizontalInset)
            .padding(.vertical, 6)
            .frame(minWidth: DesktopControlMetrics.minimumActionWidth, minHeight: DesktopControlMetrics.regularHeight)
            .foregroundStyle(emphasis == .primary ? Color.white : (configuration.role == .destructive ? Color.red : Color.primary))
            .background {
                RoundedRectangle(cornerRadius: DesktopControlMetrics.cornerRadius)
                    .fill(emphasis == .primary ? Color(red: 37 / 255, green: 99 / 255, blue: 196 / 255) : Color(nsColor: .controlColor))
                RoundedRectangle(cornerRadius: DesktopControlMetrics.cornerRadius)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0))
                RoundedRectangle(cornerRadius: DesktopControlMetrics.cornerRadius)
                    .strokeBorder(isFocused ? Color.accentColor : Color.primary.opacity(contrast == .increased ? 0.6 : 0.18), lineWidth: isFocused ? 2 : 1)
            }
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: DesktopControlMetrics.cornerRadius))
    }
}
