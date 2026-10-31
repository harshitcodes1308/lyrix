import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct TrackIdentity: Codable, Hashable, Sendable {
    public let title: String
    public let artist: String
    public let album: String?
    public let duration: TimeInterval?
    public init(title: String, artist: String, album: String? = nil, duration: TimeInterval? = nil) {
        self.title = title; self.artist = artist; self.album = album; self.duration = duration
    }
}

public struct LyricsCandidate: Sendable, Identifiable {
    public let id: String
    public let track: TrackIdentity
    public let document: LyricsDocument
    public let provider: String
    public init(id: String, track: TrackIdentity, document: LyricsDocument, provider: String) {
        self.id = id; self.track = track; self.document = document; self.provider = provider
    }
}

public protocol LyricsProvider: Sendable {
    func search(track: TrackIdentity) async throws -> [LyricsCandidate]
}

public enum LyricsMatcher {
    public static func score(_ candidate: LyricsCandidate, for track: TrackIdentity) -> Double {
        let title = similarity(candidate.track.title, track.title)
        let artist = similarity(candidate.track.artist, track.artist)
        let album = similarity(candidate.track.album ?? "", track.album ?? "")
        let duration: Double
        if let a = candidate.track.duration, let b = track.duration { duration = max(0, 1 - abs(a-b) / 30) }
        else { duration = 0.5 }
        let hasArtist = !track.artist.isEmpty
        let hasAlbum = !(track.album ?? "").isEmpty
        let base = title * 0.5 + (hasArtist ? artist * 0.3 : 0) + (hasAlbum ? album * 0.08 : 0) + duration * 0.07 + (candidate.document.lines.isEmpty ? 0 : 0.05)
        let possible = 0.5 + (hasArtist ? 0.3 : 0) + (hasAlbum ? 0.08 : 0) + 0.07 + 0.05
        return min(1, base / possible)
    }
    private static func similarity(_ a: String, _ b: String) -> Double {
        let aa = normalize(a), bb = normalize(b)
        if aa == bb { return 1 }
        if aa.isEmpty || bb.isEmpty { return 0 }
        let x = Set(aa.split(separator: " ")), y = Set(bb.split(separator: " "))
        return Double(x.intersection(y).count) / Double(x.union(y).count)
    }
    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
          .replacingOccurrences(of: #"\([^)]*(remaster|version)[^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
          .lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

public struct LocalLyricsProvider: LyricsProvider {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func search(track: TrackIdentity) async throws -> [LyricsCandidate] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "lrc" }.compactMap { url in
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let doc = LRCParser.parse(raw, source: "Imported")
            let identity = TrackIdentity(title: doc.metadata["ti"] ?? url.deletingPathExtension().lastPathComponent, artist: doc.metadata["ar"] ?? "", album: doc.metadata["al"])
            return LyricsCandidate(id: url.lastPathComponent, track: identity, document: doc, provider: "Local")
        }.sorted { LyricsMatcher.score($0, for: track) > LyricsMatcher.score($1, for: track) }
    }
}

public enum LyricsNetworkError: Error, LocalizedError {
    case unavailable(Int), malformed
    public var errorDescription: String? {
        switch self { case .unavailable(let status): return "Lyrics service returned HTTP \(status)."; case .malformed: return "Lyrics service returned invalid data." }
    }
}

public struct LRCLIBProvider: LyricsProvider {
    public init() {}
    public func search(track: TrackIdentity) async throws -> [LyricsCandidate] {
        var records: [Record] = []
        if !track.artist.isEmpty, let album = track.album, let duration = track.duration {
            var exact = URLComponents(string: "https://lrclib.net/api/get")!
            exact.queryItems = [
                URLQueryItem(name: "track_name", value: track.title),
                URLQueryItem(name: "artist_name", value: track.artist),
                URLQueryItem(name: "album_name", value: album),
                URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
            ]
            if let data = try await fetch(exact.url!) {
                records = [try JSONDecoder().decode(Record.self, from: data)]
            }
        }
        if records.isEmpty {
            var query = URLComponents(string: "https://lrclib.net/api/search")!
            query.queryItems = [URLQueryItem(name: "track_name", value: track.title)]
            if !track.artist.isEmpty { query.queryItems?.append(URLQueryItem(name: "artist_name", value: track.artist)) }
            if let data = try await fetch(query.url!) { records = try JSONDecoder().decode([Record].self, from: data) }
        }
        return records.compactMap { record in
            guard let raw = record.syncedLyrics, !raw.isEmpty else { return nil }
            return LyricsCandidate(id: String(record.id), track: TrackIdentity(title: record.trackName, artist: record.artistName, album: record.albumName, duration: record.duration), document: LRCParser.parse(raw, source: "LRCLIB"), provider: "LRCLIB")
        }.sorted { LyricsMatcher.score($0, for: track) > LyricsMatcher.score($1, for: track) }
    }
    private func fetch(_ url: URL) async throws -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Lyrix/0.1 (local macOS lyrics viewer)", forHTTPHeaderField: "User-Agent")
        var last: Error = LyricsNetworkError.unavailable(503)
        for attempt in 0..<2 {
            try Task.checkCancellation()
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let status = (response as? HTTPURLResponse)?.statusCode else { throw LyricsNetworkError.malformed }
                if status == 404 { return nil }
                guard status == 200 else { throw LyricsNetworkError.unavailable(status) }
                return data
            } catch {
                last = error
                if case LyricsNetworkError.unavailable(let status) = error, status != 429 && status != 503 { break }
                if attempt == 0 { try await Task.sleep(nanoseconds: 500_000_000) }
            }
        }
        throw last
    }
    private struct Record: Decodable {
        let id: Int; let trackName: String; let artistName: String; let albumName: String?; let duration: Double?; let syncedLyrics: String?
    }
}

public final class LyricsCache {
    public let directory: URL
    public init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.directory = directory ?? base.appendingPathComponent("Lyrix/Cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }
    private func file(for track: TrackIdentity) -> URL {
        let key = "\(track.title.lowercased())|\(track.artist.lowercased())"
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json")
    }
    public func load(_ track: TrackIdentity) -> LyricsDocument? {
        guard let data = try? Data(contentsOf: file(for: track)) else { return nil }
        return try? JSONDecoder().decode(LyricsDocument.self, from: data)
    }
    public func save(_ document: LyricsDocument, for track: TrackIdentity) throws {
        let data = try JSONEncoder().encode(document)
        try data.write(to: file(for: track), options: .atomic)
    }
    public func clear() throws {
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where file.pathExtension == "json" { try FileManager.default.removeItem(at: file) }
    }
}
