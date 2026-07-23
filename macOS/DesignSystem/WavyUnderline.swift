import SwiftUI

/// A horizontal squiggle, used to mark flagged spans in the 表达纠正 coach
/// popup (`text-decoration: wavy underline` from the Claude design `coach`).
struct WavyUnderline: Shape {
    var wavelength: CGFloat = 5
    var amplitude: CGFloat = 1.3

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: midY))
        var x = rect.minX
        var up = true
        while x < rect.maxX {
            let nextX = min(x + wavelength / 2, rect.maxX)
            let controlY = midY + (up ? -amplitude : amplitude)
            path.addQuadCurve(
                to: CGPoint(x: nextX, y: midY),
                control: CGPoint(x: (x + nextX) / 2, y: controlY)
            )
            x = nextX
            up.toggle()
        }
        return path
    }
}

extension View {
    /// Draw a wavy underline just below the view (e.g. a flagged word token).
    /// Respects Reduce Motion implicitly (it is static — no animation).
    func wavyUnderline(_ color: Color, height: CGFloat = 4, lineWidth: CGFloat = 1.2) -> some View {
        overlay(alignment: .bottom) {
            WavyUnderline()
                .stroke(color, lineWidth: lineWidth)
                .frame(height: height)
                .offset(y: height)
                .allowsHitTesting(false)
        }
    }
}
