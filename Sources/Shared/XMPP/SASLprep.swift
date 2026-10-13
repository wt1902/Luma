import Foundation

/// RFC 4013 (SASLprep) profile of stringprep for XMPP passwords.
///
/// Martin's SCRAM implementation feeds the password into the PBKDF as raw
/// UTF-8 (ScramMechanism.normalize), while SASLprep-compliant servers
/// (Prosody, ejabberd) normalize it first. Passwords containing characters
/// the profile changes (non-ASCII spaces, soft hyphen, zero-width marks,
/// fullwidth forms, decomposed accents, ...) therefore fail with
/// 'not-authorized' even when the password is correct. Luma prepares the
/// password itself before handing it to SCRAM so both sides agree.
///
/// The profile is: mapping (RFC 3454 B.1 + RFC 4013 C.1.2), NFKC
/// normalization, prohibition checks. The RFC 3454 section 6 bidi rules are
/// intentionally not enforced: they only affect pathological passwords and
/// the server enforces them on its side anyway.
enum SASLprep {
    enum PreparationError: Error, Equatable {
        case prohibitedCharacter(Character)
    }

    /// RFC 4013 C.1.2: non-ASCII space characters mapped to U+0020 SPACE.
    private static let mappedToSpace: Set<Character> = [
        "\u{00A0}", "\u{1680}", "\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}",
        "\u{2004}", "\u{2005}", "\u{2006}", "\u{2007}", "\u{2008}", "\u{2009}",
        "\u{200A}", "\u{200B}", "\u{202F}", "\u{205F}", "\u{3000}",
    ]

    /// RFC 3454 B.1: characters mapped to nothing. U+200B is deliberately
    /// absent: RFC 4013 C.1.2 maps it to SPACE instead.
    private static func isMappedToNothing(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if value == 0x00AD || value == 0x034F || value == 0x1806 { return true }
        if value >= 0x180B && value <= 0x180D { return true }
        if value == 0x200C || value == 0x200D { return true }
        if value == 0x2060 || value == 0xFEFF { return true }
        if value >= 0xFE00 && value <= 0xFE0F { return true }
        return false
    }

    /// RFC 3454 C.2.1, C.2.2, C.2.3, C.3, C.4 and C.8: prohibited output.
    private static func isProhibited(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        // C.2.1 ASCII control characters.
        if value <= 0x1F || value == 0x7F { return true }
        // C.2.2 non-ASCII control characters.
        if value >= 0x80 && value <= 0x9F { return true }
        // C.2.3 private use.
        if value >= 0xE000 && value <= 0xF8FF { return true }
        if value >= 0xF0000 && value <= 0xFFFFD { return true }
        if value >= 0x100000 && value <= 0x10FFFD { return true }
        // C.3 non-character code points.
        if value >= 0xFDD0 && value <= 0xFDEF { return true }
        if value & 0xFFFF == 0xFFFE || value & 0xFFFF == 0xFFFF { return true }
        // C.4 surrogates cannot appear in a Swift string.
        // C.8 change display properties / deprecated.
        if value == 0x0340 || value == 0x0341 { return true }
        if value == 0x200E || value == 0x200F { return true }
        if value == 0x202A || value == 0x202B || value == 0x202C || value == 0x202D
            || value == 0x202E
        {
            return true
        }
        if value == 0x206A || value == 0x206B || value == 0x206C || value == 0x206D
            || value == 0x206E || value == 0x206F
        {
            return true
        }
        return false
    }

    /// Returns the prepared password, or throws PreparationError when the
    /// input contains characters RFC 4013 prohibits.
    static func prepare(_ input: String) throws -> String {
        // 1. Map.
        var mapped = String.UnicodeScalarView()
        for scalar in input.unicodeScalars {
            let character = Character(String(scalar))
            if isMappedToNothing(scalar) { continue }
            if mappedToSpace.contains(character) {
                mapped.append(contentsOf: " ".unicodeScalars)
                continue
            }
            mapped.append(scalar)
        }

        // 2. Normalize (NFKC also composes decomposed accents).
        let normalized = String(mapped).applyingTransform(
            StringTransform("NFKC"),
            reverse: false
        ) ?? String(mapped).precomposedStringWithCanonicalMapping

        // 3. Prohibit.
        for scalar in normalized.unicodeScalars where isProhibited(scalar) {
            throw PreparationError.prohibitedCharacter(Character(String(scalar)))
        }

        return normalized
    }
}

