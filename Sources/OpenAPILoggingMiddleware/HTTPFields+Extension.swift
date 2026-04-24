
import Foundation
import HTTPTypes

/// Converts HTTPFields to a string, ensuring unique header names.
public extension HTTPFields {
    /// Converts HTTPFields to a string, ensuring unique header names.
    ///
    /// - Parameter headerFields: The HTTPFields collection to convert.
    /// - Returns: A string representing the header fields in `name=value` format.
    func toArrayString() -> String {
        // Use a dictionary to store unique header fields (name-value pairs)
        var uniqueHeaders: [String: String] = [:]

        // Iterate over header fields and add them to the dictionary (overwriting duplicates)
        self.forEach { field in
            uniqueHeaders[field.name.rawName] = field.value
        }

        // Convert the unique dictionary to an array of "name=value" strings
        let result = uniqueHeaders.map { "\($0.key)=\($0.value)" }

        // Join the array elements into a single string, separated by commas
        return result.joined(separator: ", ")
    }

    /// Converts HTTPFields to a `[String: String]`. When the same header name
    /// appears more than once (which HTTP allows — `Cookie`, `Set-Cookie`,
    /// `Via`, `Vary`, etc.), the **last** value wins. This is a logging
    /// helper; losing precision on duplicate values in the log output is an
    /// intentional trade-off for not trapping the host process.
    ///
    /// Previously used `Dictionary(uniqueKeysWithValues:)` which traps on any
    /// duplicate key, so a request with two `Cookie` headers would abort the
    /// server before it could reach the actual handler.
    func toDictionary() -> [String: String] {
        let pairs = self.map { ($0.name.rawName, $0.value.description) }
        return Dictionary(pairs, uniquingKeysWith: { _, last in last })
    }

    func toJSONString() -> String? {
        let dictionary = self.toDictionary()
        let headersString = String.convertDictionaryToJSONString(dictionary)
        return headersString
    }
}
