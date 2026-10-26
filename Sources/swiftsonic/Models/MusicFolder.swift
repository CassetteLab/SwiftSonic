// MusicFolder.swift — SwiftSonic
//
// Data model for a server-side music library folder, returned by getMusicFolders.

import Foundation

/// A top-level music library folder on the server.
///
/// Returned by ``SwiftSonicClient/getMusicFolders()``.
public struct MusicFolder: Codable, Sendable, Identifiable {
    /// The unique identifier for this music folder.
    public let id: String

    /// The display name of the music folder.
    public let name: String?

    private enum CodingKeys: String, CodingKey { case id, name }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let textID = try? container.decode(String.self, forKey: .id) {
            id = textID
        } else {
            id = String(try container.decode(Int.self, forKey: .id))
        }
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}
