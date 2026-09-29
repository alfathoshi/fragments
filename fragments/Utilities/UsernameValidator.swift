//
 //  UsernameValidator.swift
//  fragments
//

import Foundation

/// Validation failure reasons for usernames.
public enum UsernameValidationError: LocalizedError, Equatable, Sendable {
    case empty
    case tooShort(min: Int)
    case tooLong(max: Int)
    case invalidCharacters

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Enter a username."
        case .tooShort(let min):
            return "Username must be at least \(min) characters."
        case .tooLong(let max):
            return "Username must be at most \(max) characters."
        case .invalidCharacters:
            return "Use only lowercase letters, numbers, and underscores."
        }
    }
}

/// Pure username rules shared by the setup UI, availability checks, and
/// persistence. Normalization (trim + lowercase) is applied consistently at
/// every layer so checking, saving, and display always agree.
///
/// Rule: 3–20 characters, [a-z0-9_], no spaces. Mirrors the
/// `profiles_username_format` database CHECK constraint.
public enum UsernameValidator {
    public static let minLength = 3
    public static let maxLength = 20

    private static let allowed: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "^[a-z0-9_]+$")
    }()

    /// Normalizes raw input: trims whitespace/newlines and lowercases.
    /// No other silent modification is performed.
    public static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Validates an already-normalized username. Returns nil when valid.
    public static func failure(for normalized: String) -> UsernameValidationError? {
        if normalized.isEmpty { return .empty }
        if normalized.count < minLength { return .tooShort(min: minLength) }
        if normalized.count > maxLength { return .tooLong(max: maxLength) }
        let range = NSRange(normalized.startIndex..., in: normalized)
        if allowed.firstMatch(in: normalized, range: range) == nil {
            return .invalidCharacters
        }
        return nil
    }

    public static func isValid(_ normalized: String) -> Bool {
        failure(for: normalized) == nil
    }

    /// Validates raw input (normalizes first) and returns a friendly message.
    public static func friendlyMessage(for raw: String) -> String {
        failure(for: normalize(raw))?.errorDescription ?? "Invalid username."
    }
}

/// Per-user local cache of the claimed username. Used ONLY as an offline
/// fallback for setup gating — the backend row is the source of truth and is
/// re-verified whenever network is available.
public enum CachedUsernameStore {
    private static func key(for userID: String) -> String {
        "fragments_cached_username_\(userID)"
    }

    public static func save(_ username: String, for userID: String) {
        UserDefaults.standard.set(username, forKey: key(for: userID))
    }

    public static func load(for userID: String?) -> String? {
        guard let userID, !userID.isEmpty else { return nil }
        let value = UserDefaults.standard.string(forKey: key(for: userID))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    public static func clear(for userID: String?) {
        guard let userID, !userID.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: key(for: userID))
    }
}
