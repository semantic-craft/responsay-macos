import Foundation

/// Pure percentile math for the latency readout (issue 507). Nearest-rank method
/// (no interpolation → deterministic, well-defined on tiny samples).
public enum LatencyStats {
    /// `p` in 0...100 (clamped). Returns nil for empty input.
    public static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let clamped = min(max(p, 0), 100)
        let rank = Int((clamped / 100 * Double(sorted.count)).rounded(.up))
        let index = min(max(rank - 1, 0), sorted.count - 1)
        return sorted[index]
    }
}
