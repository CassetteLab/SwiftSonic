// LenientDateDecoding.swift — SwiftSonic (Internal)
//
// Treats an empty string as "absent" for *optional* `Date` fields.
//
// Some Subsonic implementations (e.g. Nextcloud Music) send `"played": ""`
// for a track that has never been played, instead of omitting the key or
// sending `null`. An optional `Date` is decoded through
// `decodeIfPresent(_:forKey:)`, which only short-circuits on a missing key or
// `null`: the empty string reaches the ISO 8601 date strategy, throws, and the
// whole response fails to decode.
//
// This concrete overload is statically preferred by the compiler over the
// generic `decodeIfPresent<T: Decodable>(_:forKey:)` for every `Date?` decoded
// inside this module — synthesized conformances and hand-written
// `init(from:)` alike.
//
// Contract (frozen by LenientDateDecodingTests):
//   - key absent          → nil
//   - null                → nil
//   - ""                  → nil
//   - valid ISO 8601      → Date
//   - any other value     → throws (malformed dates are never swallowed)
//   - non-optional `Date` → unaffected, "" still throws
//
// ⚠️ This extension MUST stay `internal`. Making it `public` would silently
// change how every consumer of SwiftSonic decodes its own `Date?` fields.

import Foundation

extension KeyedDecodingContainer {

    /// Decodes an optional `Date`, treating an empty string like a missing value.
    ///
    /// Any other non-ISO 8601 value still throws via the decoder's
    /// `dateDecodingStrategy`.
    func decodeIfPresent(_ type: Date.Type, forKey key: Key) throws -> Date? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let raw = try? decode(String.self, forKey: key), raw.isEmpty {
            return nil
        }
        return try decode(Date.self, forKey: key)
    }
}
