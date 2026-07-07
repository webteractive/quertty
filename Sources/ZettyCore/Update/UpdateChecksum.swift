import Foundation
import CryptoKit

/// SHA-256 helpers for verifying a downloaded update. Pure — the caller reads
/// the file and passes the bytes; this never touches disk.
public enum UpdateChecksum {
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// True when `data`'s digest equals the published hex (case/whitespace
    /// tolerant). An empty published value never matches.
    public static func matches(data: Data, publishedHex: String) -> Bool {
        let expected = publishedHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !expected.isEmpty else { return false }
        return sha256Hex(data) == expected
    }
}
