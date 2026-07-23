import CoreGraphics

/// macOS spacing / radius scale — good-ui "Systematize Everything". One constrained set of
/// steps so padding and gaps stay consistent across views instead of ad-hoc magic numbers.
/// Parallels `MacPalette` (color tokens). Use these instead of literal CGFloats in layout.
enum MacMetrics {
    /// Tight in-group gap / accent-stripe width.
    static let hairline: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24

    /// Continuous corner radii — aliases of the adjudicated SkinMetrics values
    /// (issue 309: 13/9 won over the old 12/8; MacMetrics keeps only its 4-pt
    /// spacing scale as an independent contribution).
    static let radiusSmall: CGFloat = SkinMetrics.radiusSmall
    static let radiusCard: CGFloat = SkinMetrics.radiusCard
}
