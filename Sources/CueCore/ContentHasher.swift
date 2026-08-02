import CryptoKit
import Foundation

public enum ContentHasher {
    public static func normalized(_ body: String) -> String {
        body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    public static func hash(_ body: String) -> String {
        let digest = SHA256.hash(data: Data(normalized(body).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
