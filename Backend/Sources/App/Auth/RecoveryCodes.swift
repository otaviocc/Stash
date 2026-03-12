import Foundation

/// Generation and normalisation of single-use 2FA recovery codes. PRD §8.3 / §7.4.
///
/// Format: 8 uppercase alphanumeric characters, presented in two groups for readability
/// (`ABCD-EFGH`). Eight codes are generated at enrolment.
enum RecoveryCodes {
    static let count = 8
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    /// Generate `count` formatted codes (e.g. `ABCD-EFGH`), shown to the user exactly once.
    static func generate() -> [String] {
        (0..<count).map { _ in formatted(rawCode()) }
    }

    /// Strip formatting so display form and stored/compared form always match.
    /// `ABCD-EFGH` -> `ABCDEFGH`.
    static func normalize(_ code: String) -> String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func rawCode() -> String {
        String((0..<8).map { _ in alphabet.randomElement()! })
    }

    private static func formatted(_ raw: String) -> String {
        let mid = raw.index(raw.startIndex, offsetBy: 4)
        return "\(raw[raw.startIndex..<mid])-\(raw[mid...])"
    }
}
