import SwiftUI

/// Centralized design tokens for the Aurora Glow theme. All views should pull
/// colors / spacing / typography / motion from here so the look stays
/// coherent and is changeable in one place.
enum Theme {
    // MARK: - Palette (dark-first)

    static let canvas        = Color(red: 0.043, green: 0.051, blue: 0.078) // #0B0D14
    static let elevated1     = Color(red: 0.078, green: 0.090, blue: 0.122) // #14171F
    static let elevated2     = Color(red: 0.106, green: 0.122, blue: 0.165) // #1B1F2A
    static let strokeSubtle  = Color.white.opacity(0.06)
    static let strokeBright  = Color.white.opacity(0.14)
    static let textPrimary   = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.60)
    static let textTertiary  = Color.white.opacity(0.38)

    // Aurora background blob colors
    static let auroraA = Color(red: 0.45, green: 0.20, blue: 0.85) // violet
    static let auroraB = Color(red: 0.15, green: 0.55, blue: 0.90) // ocean
    static let auroraC = Color(red: 0.95, green: 0.30, blue: 0.55) // magenta

    // MARK: - Radii

    static let r6:  CGFloat = 6
    static let r10: CGFloat = 10
    static let r14: CGFloat = 14
    static let r22: CGFloat = 22

    // MARK: - Spacing

    static let s4:  CGFloat = 4
    static let s8:  CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32

    // MARK: - Motion

    static let springQuick:  Animation = .spring(response: 0.28, dampingFraction: 0.78)
    static let springSettle: Animation = .spring(response: 0.42, dampingFraction: 0.82)
    static let springLively: Animation = .spring(response: 0.38, dampingFraction: 0.66)
    static let easeMedium:   Animation = .easeInOut(duration: 0.32)
    static let easeSlow:     Animation = .easeInOut(duration: 0.6)

    // MARK: - Typography (SF Pro Rounded for headlines, default elsewhere)

    static func title(_ size: CGFloat = 28)    -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func headline(_ size: CGFloat = 16) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func body(_ size: CGFloat = 13)     -> Font { .system(size: size, weight: .medium) }
    static func caption(_ size: CGFloat = 11)  -> Font { .system(size: size, weight: .regular) }
    static func mono(_ size: CGFloat = 12)     -> Font { .system(size: size, weight: .regular, design: .monospaced) }
}

extension View {
    /// Apply a neon-style glow tinted by the service's accent color.
    func accentGlow(_ color: Color, radius: CGFloat = 14, intensity: CGFloat = 0.55) -> some View {
        self.shadow(color: color.opacity(intensity), radius: radius, y: 0)
    }

    /// Theme-aware glass-card background: ultraThinMaterial over an accent tint.
    func glassCard(accent: Color = .white, cornerRadius: CGFloat = Theme.r14, accentOpacity: Double = 0.06) -> some View {
        background(
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(accent.opacity(accentOpacity))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.strokeSubtle, lineWidth: 0.5)
        )
    }
}
