import Foundation
import HTTPTypes

/// Logging-friendly conversions from `HTTPFields` to plain Swift values.
///
/// ## Overview
///
/// HTTP allows the same header name to appear multiple times (`Cookie`,
/// `Set-Cookie`, `Via`, `Vary`, etc.). The conversions here collapse
/// duplicates so the result fits naturally into `Logger.Metadata` without
/// trapping on duplicate keys. The trade-off is intentional: when duplicates
/// occur, the **last** value wins. Use these helpers in log paths only — for
/// real header processing, iterate `HTTPFields` directly.
///
/// ## Topics
///
/// ### Converting to log-friendly forms
/// - ``toArrayString()``
/// - ``toDictionary()``
/// - ``toJSONString()``
public extension HTTPFields {

    /// Render the fields as a flat `name=value, name=value, …` string.
    ///
    /// On duplicate names, the last seen value wins.
    ///
    /// - Returns: A single line suitable for one-shot logging.
    func toArrayString() -> String {
        var uniqueHeaders: [String: String] = [:]
        self.forEach { field in
            uniqueHeaders[field.name.rawName] = field.value
        }
        let result = uniqueHeaders.map { "\($0.key)=\($0.value)" }
        return result.joined(separator: ", ")
    }

    /// Render the fields as a `[String: String]` dictionary.
    ///
    /// - Important: HTTP allows duplicate header names. This helper uses
    ///   `Dictionary(_:uniquingKeysWith:)` with a "last wins" rule rather
    ///   than the trap-on-duplicate-key initializer, so a request with two
    ///   `Cookie` headers cannot abort the host process. Losing precision on
    ///   duplicate-named headers is an intentional trade-off for use in
    ///   logging only.
    ///
    /// - Returns: A dictionary of header names to their last-seen values.
    func toDictionary() -> [String: String] {
        let pairs = self.map { ($0.name.rawName, $0.value.description) }
        return Dictionary(pairs, uniquingKeysWith: { _, last in last })
    }

    /// Render the fields as a JSON object string (pretty-printed).
    ///
    /// - Returns: A JSON string, or `nil` if serialisation fails (e.g. a
    ///   header value that is not valid UTF-8).
    func toJSONString() -> String? {
        let dictionary = self.toDictionary()
        return String.convertDictionaryToJSONString(dictionary)
    }
}
