import Foundation

/// Pure capacity math for 482's sample-rate conversion: frames produced when resampling
/// `sourceFrames` from `sourceRate` to `targetRate`, rounded up. Side-effect-free so the
/// frame math is unit-testable without audio.
enum ReadAloudResampling {
    static func outputFrameCount(sourceFrames: Int, sourceRate: Double, targetRate: Double) -> Int {
        guard sourceFrames > 0, sourceRate > 0, targetRate > 0 else { return 0 }
        return Int((Double(sourceFrames) * targetRate / sourceRate).rounded(.up))
    }
}
