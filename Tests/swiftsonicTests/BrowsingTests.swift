// BrowsingTests.swift — SwiftSonicTests
//
// Tests for all browsing endpoints: getMusicFolders, getArtists, getArtist,
// getAlbum, getSong, getGenres, getArtistInfo2, getAlbumInfo2.

import Testing
import Foundation
@testable import SwiftSonic

// MARK: - getMusicFolders

@Suite("getMusicFolders")
struct GetMusicFoldersTests {

    @Test("getMusicFolders accepts numeric and text folder IDs")
    func decodesMixedFolderIDs() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(Data("""
        {"subsonic-response":{"status":"ok","version":"1.16.1","musicFolders":{
          "musicFolder":[{"id":1,"name":"Western"},{"id":"bollywood","name":"Bollywood"}]
        }}}
        """.utf8))

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        let folders = try await client.getMusicFolders()

        #expect(folders.map(\.id) == ["1", "bollywood"])
        #expect(folders.map(\.name) == ["Western", "Bollywood"])
    }

    @Test("folder IDs encode as strings and optional names round-trip")
    func roundTripsFolder() throws {
        let folder = try JSONDecoder().decode(MusicFolder.self, from: Data(#"{"id":42}"#.utf8))
        let encoded = try JSONEncoder().encode(folder)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let decoded = try JSONDecoder().decode(MusicFolder.self, from: encoded)

        #expect(object["id"] as? String == "42")
        #expect(decoded.id == "42")
        #expect(decoded.name == nil)
    }

    @Test("invalid folder IDs are rejected", arguments: ["null", "true", "1.5", "{}", "[]"])
    func rejectsInvalidFolderID(_ value: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(MusicFolder.self, from: Data("{\"id\":\(value)}".utf8))
        }
    }

    @Test("getMusicFolders decodes folder list")
    func decodesFolders() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "getMusicFolders")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        let folders = try await client.getMusicFolders()

        #expect(folders.count == 2)
        #expect(folders[0].id == "1")
        #expect(folders[0].name == "Music")

        let req = try #require(mock.lastRequest)
        #expect(req.url?.path.hasSuffix("/rest/getMusicFolders.view") == true)
    }
}

// MARK: - getArtists

@Suite("getArtists")
struct GetArtistsTests {

    @Test("getArtists decodes index buckets and artists")
    func decodesArtists() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "getArtists")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        let indexes = try await client.getArtists()

        #expect(indexes.count == 2)
        let aIndex = try #require(indexes.first(where: { $0.name == "A" }))
        #expect(aIndex.artist[0].name == "ABBA")
        #expect(aIndex.artist[0].albumCount == 5)
        #expect(aIndex.artist[0].starred != nil)
    }

    @Test("getArtists sends correct request path")
    func sendsCorrectRequest() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "getArtists")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        _ = try await client.getArtists()

        let req = try #require(mock.lastRequest)
        #expect(req.url?.path.hasSuffix("/rest/getArtists.view") == true)
        #expect(mock.queryItem(named: "musicFolderId") == nil)
    }

    @Test("getArtists sends musicFolderId when provided")
    func sendsMusicFolderId() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "getArtists")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        _ = try await client.getArtists(musicFolderId: "42")

        #expect(mock.queryItem(named: "musicFolderId") == "42")
    }

    @Test("getArtists returns empty array on empty index")
    func returnsEmptyOnEmptyIndex() async throws {
        let emptyFixture = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","artists":{"ignoredArticles":"The","index":[]}}}
        """.data(using: .utf8)!

        let mock = MockHTTPTransport()
        mock.enqueue(emptyFixture)

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        let indexes = try await client.getArtists()
        #expect(indexes.isEmpty)
    }
}

// MARK: - getArtist

@Suite("getArtist")
struct GetArtistTests {

    @Test("getArtist decodes artist with albums")
    func decodesArtistWithAlbums() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "getArtist")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        let artist = try await client.getArtist(id: "1")

        #expect(artist.id == "1")
        #expect(artist.name == "ABBA")
        #expect(artist.albumCount == 2)
        #expect(artist.album?.count == 2)
        #expect(artist.album?[0].name == "Ring Ring")
        #expect(artist.album?[1].name == "Waterloo")

        let req = try #require(mock.lastRequest)
        #expect(req.url?.path.hasSuffix("/rest/getArtist.view") == true)
        #expect(mock.queryItem(named: "id") == "1")
    }
}

// MARK: - getAlbum

@Suite("getAlbum")
struct GetAlbumTests {

    @Test("getAlbum decodes album with songs and OpenSubsonic genres")
    func decodesAlbumWithSongs() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "getAlbum")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        let album = try await client.getAlbum(id: "10")

        #expect(album.id == "10")
        #expect(album.name == "Ring Ring")
        #expect(album.songCount == 3)
        #expect(album.song?.count == 3)
        #expect(album.song?[0].title == "Ring Ring")
        #expect(album.genres?.count == 2)
        #expect(album.genres?[0].name == "Pop")

        let req = try #require(mock.lastRequest)
        #expect(req.url?.path.hasSuffix("/rest/getAlbum.view") == true)
        #expect(mock.queryItem(named: "id") == "10")
    }
}

// MARK: - getSong

@Suite("getSong")
struct GetSongTests {

    @Test("getSong decodes song with OpenSubsonic fields")
    func decodesSong() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "getSong")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        let song = try await client.getSong(id: "101")

        #expect(song.id == "101")
        #expect(song.title == "Ring Ring")
        #expect(song.duration == 190)
        #expect(song.bpm == 128)
        #expect(song.replayGain?.trackGain == -7.2)
        #expect(song.genres?.count == 1)

        let req = try #require(mock.lastRequest)
        #expect(req.url?.path.hasSuffix("/rest/getSong.view") == true)
        #expect(mock.queryItem(named: "id") == "101")
    }
}

// MARK: - getGenres

@Suite("getGenres")
struct GetGenresTests {

    @Test("getGenres decodes genre list with counts")
    func decodesGenres() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "getGenres")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        let genres = try await client.getGenres()

        #expect(genres.count == 4)
        let pop = try #require(genres.first(where: { $0.value == "Pop" }))
        #expect(pop.songCount == 150)
        #expect(pop.albumCount == 12)
    }
}

// MARK: - getArtistInfo2

@Suite("getArtistInfo2")
struct GetArtistInfo2Tests {

    @Test("getArtistInfo2 decodes biography and similar artists")
    func decodesArtistInfo() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "getArtistInfo2")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        let info = try await client.getArtistInfo2(id: "1")

        #expect(info.biography?.isEmpty == false)
        #expect(info.musicBrainzId == "d87e52c5-bb8d-4da8-b941-9f4928627dc8")
        #expect(info.similarArtist?.count == 1)
        #expect(info.similarArtist?[0].name == "Boney M.")
    }

    @Test("getArtistInfo2 sends optional params")
    func sendsOptionalParams() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "getArtistInfo2")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        _ = try await client.getArtistInfo2(id: "1", count: 5, includeNotPresent: true)

        #expect(mock.queryItem(named: "count") == "5")
        #expect(mock.queryItem(named: "includeNotPresent") == "true")
    }
}

// MARK: - getAlbumInfo2

@Suite("getAlbumInfo2")
struct GetAlbumInfo2Tests {

    @Test("getAlbumInfo2 decodes album biography")
    func decodesAlbumInfo() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "getAlbumInfo2")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        let info = try await client.getAlbumInfo2(id: "10")

        #expect(info.notes?.isEmpty == false)
        #expect(info.musicBrainzId == "b8e42a9c-8291-4899-94a9-5602e0b22ff5")
        #expect(info.largeImageUrl != nil)
    }
}

// MARK: - RequestBuilder

@Suite("RequestBuilder")
struct RequestBuilderTests {

    @Test("token auth params are all present")
    func tokenAuthParams() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "ping_ok")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        try await client.ping()

        #expect(mock.queryItem(named: "u") == "testuser")
        #expect(mock.queryItem(named: "t") != nil)
        #expect(mock.queryItem(named: "s") != nil)
        #expect(mock.queryItem(named: "apiKey") == nil)
    }

    @Test("apiKey auth sends apiKey param, no u/t/s")
    func apiKeyAuth() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "ping_ok")

        let config = ServerConfiguration(
            serverURL: URL(string: "https://test.example.com")!,
            auth: .apiKey("my-secret-key")
        )
        let client = SwiftSonicClient(configuration: config, transport: mock)
        try await client.ping()

        #expect(mock.queryItem(named: "apiKey") == "my-secret-key")
        #expect(mock.queryItem(named: "u") == nil)
        #expect(mock.queryItem(named: "t") == nil)
    }

    @Test("reusesSalt uses same salt across requests")
    func reusesSaltIsConsistent() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "ping_ok")
        mock.enqueue(fixture: "ping_ok")

        let config = ServerConfiguration(
            serverURL: URL(string: "https://test.example.com")!,
            username: "user",
            password: "pass",
            reusesSalt: true
        )
        let client = SwiftSonicClient(configuration: config, transport: mock)
        try await client.ping()
        try await client.ping()

        let salt1 = mock.queryItem(named: "s", in: mock.capturedRequests[0])
        let salt2 = mock.queryItem(named: "s", in: mock.capturedRequests[1])
        #expect(salt1 == salt2)
    }
}
