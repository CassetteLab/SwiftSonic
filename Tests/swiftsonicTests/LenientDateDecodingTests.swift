// LenientDateDecodingTests.swift — SwiftSonicTests
//
// Freezes the contract of the internal `KeyedDecodingContainer.decodeIfPresent(Date.self, …)`
// overload (see LenientDateDecoding.swift):
//   - optional Date: absent / null / "" → nil, valid ISO 8601 → Date, anything else → throws
//   - non-optional Date: "" → throws
//
// Regression for https://github.com/CassetteLab/SwiftSonic/issues/4
// (Nextcloud Music sends `"played": ""` for never-played tracks).

import Testing
import Foundation
@testable import SwiftSonic

// MARK: - Helpers

/// Builds a `getSong` response whose song carries the given raw JSON
/// fragment for `played` (or no `played` key at all when `nil`).
private func songResponse(playedFragment: String?) -> Data {
    let played = playedFragment.map { #", "played": \#($0)"# } ?? ""
    let json = """
    {
        "subsonic-response": {
            "status": "ok",
            "version": "1.16.1",
            "song": {"id": "1", "title": "Track"\(played)}
        }
    }
    """
    return Data(json.utf8)
}

/// Builds a `getShares` response with a single share using the given raw
/// JSON fragments for `created` (non-optional) and `expires` (optional).
private func sharesResponse(createdFragment: String, expiresFragment: String) -> Data {
    let json = """
    {
        "subsonic-response": {
            "status": "ok",
            "version": "1.16.1",
            "shares": {
                "share": [{
                    "id": "sh-1",
                    "url": "https://music.example.com/share/sh-1",
                    "username": "alice",
                    "created": \(createdFragment),
                    "expires": \(expiresFragment),
                    "visitCount": 0,
                    "entry": []
                }]
            }
        }
    }
    """
    return Data(json.utf8)
}

private func decodeSong(playedFragment: String?) async throws -> Song {
    let mock = MockHTTPTransport()
    mock.enqueue(songResponse(playedFragment: playedFragment))
    let client = SwiftSonicClient(configuration: .test, transport: mock)
    return try await client.getSong(id: "1")
}

/// Asserts that `operation` throws `SwiftSonicError.decoding`.
private func expectDecodingError(_ operation: () async throws -> Void) async {
    do {
        try await operation()
        Issue.record("Expected SwiftSonicError.decoding, but decoding succeeded")
    } catch let error as SwiftSonicError {
        guard case .decoding = error else {
            Issue.record("Expected SwiftSonicError.decoding, got \(error)")
            return
        }
    } catch {
        Issue.record("Expected SwiftSonicError.decoding, got \(error)")
    }
}

// MARK: - Optional Date

@Suite("Optional Date decoding")
struct OptionalDateDecodingTests {

    @Test("empty string decodes as nil")
    func emptyStringIsNil() async throws {
        let song = try await decodeSong(playedFragment: #""""#)
        #expect(song.played == nil)
    }

    @Test("null decodes as nil")
    func nullIsNil() async throws {
        let song = try await decodeSong(playedFragment: "null")
        #expect(song.played == nil)
    }

    @Test("absent key decodes as nil")
    func absentKeyIsNil() async throws {
        let song = try await decodeSong(playedFragment: nil)
        #expect(song.played == nil)
    }

    @Test("ISO 8601 date without fractional seconds decodes")
    func basicISO8601() async throws {
        let song = try await decodeSong(playedFragment: #""2026-10-01T12:34:56Z""#)
        let played = try #require(song.played)
        #expect(played == Date(timeIntervalSince1970: 1_790_858_096))
    }

    @Test("ISO 8601 date with fractional seconds decodes")
    func fractionalISO8601() async throws {
        let song = try await decodeSong(playedFragment: #""2026-10-01T12:34:56.789Z""#)
        let played = try #require(song.played)
        #expect(abs(played.timeIntervalSince1970 - 1_790_858_096.789) < 0.001)
    }

    @Test("malformed date string still throws")
    func garbageThrows() async {
        await expectDecodingError {
            _ = try await decodeSong(playedFragment: #""not-a-date""#)
        }
    }

    @Test("whitespace-only string still throws")
    func whitespaceThrows() async {
        await expectDecodingError {
            _ = try await decodeSong(playedFragment: #"" ""#)
        }
    }

    @Test("empty optional date in a hand-written init(from:) decodes as nil")
    func handWrittenInitEmptyIsNil() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(sharesResponse(
            createdFragment: #""2026-01-15T10:00:00.000Z""#,
            expiresFragment: #""""#
        ))
        let client = SwiftSonicClient(configuration: .test, transport: mock)
        let shares = try await client.getShares()
        let share = try #require(shares.first)
        #expect(share.expires == nil)
    }
}

// MARK: - Non-optional Date

@Suite("Non-optional Date decoding")
struct NonOptionalDateDecodingTests {

    @Test("empty string on a required Date still throws")
    func emptyStringThrows() async {
        let mock = MockHTTPTransport()
        mock.enqueue(sharesResponse(createdFragment: #""""#, expiresFragment: "null"))
        let client = SwiftSonicClient(configuration: .test, transport: mock)
        await expectDecodingError {
            _ = try await client.getShares()
        }
    }
}

// MARK: - Issue #4 regression

@Suite("Nextcloud Music empty `played` (issue #4)")
struct EmptyPlayedRegressionTests {

    @Test("album and its songs decode when `played` is an empty string")
    func albumWithEmptyPlayedDecodes() async throws {
        let json = """
        {
            "subsonic-response": {
                "status": "ok",
                "version": "1.16.1",
                "album": {
                    "id": "album-1",
                    "name": "Album",
                    "songCount": 2,
                    "duration": 400,
                    "played": "",
                    "song": [
                        {"id": "track-28", "title": "Never Played", "played": ""},
                        {"id": "track-29", "title": "Played", "played": "2026-10-01T12:34:56Z"}
                    ]
                }
            }
        }
        """
        let mock = MockHTTPTransport()
        mock.enqueue(Data(json.utf8))
        let client = SwiftSonicClient(configuration: .test, transport: mock)

        let album = try await client.getAlbum(id: "album-1")
        let songs = try #require(album.song)

        #expect(album.played == nil)
        #expect(songs.count == 2)
        #expect(songs[0].played == nil)
        #expect(songs[1].played == Date(timeIntervalSince1970: 1_790_858_096))
    }
}
