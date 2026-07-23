import Foundation

public enum AppSchemaVersion {
    /// v2 (#557) made `source_text` nullable; v3 (#565) adds the Intent-aware `intent_route` /
    /// `intent_outcome` columns so approved intent finals persist their route + coarse outcome.
    public static let current = 3
}
