import Foundation

public struct LyricWord: Codable, Sendable, Equatable {
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public init(text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.text = text; self.startTime = startTime; self.endTime = max(startTime, endTime)
    }
}

public struct LyricLine: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let words: [LyricWord]
    public init(id: UUID = UUID(), text: String, startTime: TimeInterval, endTime: TimeInterval, words: [LyricWord] = []) {
        self.id = id; self.text = text; self.startTime = max(0, startTime); self.endTime = max(startTime, endTime); self.words = words
    }
}

public struct LyricsDocument: Codable, Sendable, Equatable {
    public let lines: [LyricLine]
    public let metadata: [String: String]
    public let source: String
    public init(lines: [LyricLine], metadata: [String: String] = [:], source: String = "local") {
        self.lines = lines; self.metadata = metadata; self.source = source
    }
}

public enum LRCParser {
    private static let tag = try! NSRegularExpression(pattern: #"\[([^\]]+)\]"#)
    private static let wordTag = try! NSRegularExpression(pattern: #"<([0-9]{1,3}):([0-9]{2})(?:[.:]([0-9]{1,3}))?>"#)

    public static func parse(_ raw: String, source: String = "local") -> LyricsDocument {
        var entries: [(time: Double, text: String, words: [LyricWord], order: Int)] = []
        var metadata: [String: String] = [:]
        var offset = 0.0
        let rows = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        for (order, row) in rows.enumerated() {
            let ns = row as NSString
            let matches = tag.matches(in: row, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }
            var times: [Double] = []
            for match in matches {
                let content = ns.substring(with: match.range(at: 1))
                if let t = timestamp(content) { times.append(t) }
                else if let colon = content.firstIndex(of: ":") {
                    let key = String(content[..<colon]).lowercased()
                    let value = String(content[content.index(after: colon)...])
                    if key == "offset" { offset = (Double(value) ?? 0) / 1000 }
                    else { metadata[key] = value }
                }
            }
            guard let last = matches.last, !times.isEmpty else { continue }
            let tail = ns.substring(from: last.range.location + last.range.length)
            let words = parseWords(tail)
            let clean = wordTag.stringByReplacingMatches(in: tail, range: NSRange(location: 0, length: (tail as NSString).length), withTemplate: "")
            for time in times { entries.append((time, clean.trimmingCharacters(in: .whitespaces), words, order)) }
        }
        entries = entries.map { (max(0, $0.time + offset), $0.text, $0.words.map { LyricWord(text: $0.text, startTime: max(0, $0.startTime + offset), endTime: max(0, $0.endTime + offset)) }, $0.order) }
        entries.sort { $0.time == $1.time ? $0.order < $1.order : $0.time < $1.time }
        let lines = entries.enumerated().map { index, e -> LyricLine in
            let next = index + 1 < entries.count ? entries[index + 1].time : e.time + 6
            return LyricLine(text: e.text, startTime: e.time, endTime: max(e.time, next), words: e.words.isEmpty ? WordTiming.estimate(e.text, start: e.time, end: max(e.time, next)) : e.words)
        }
        return LyricsDocument(lines: lines, metadata: metadata, source: source)
    }

    private static func timestamp(_ s: String) -> Double? {
        let p = s.split(separator: ":", omittingEmptySubsequences: false)
        guard p.count == 2, let minutes = Int(p[0]), minutes >= 0 else { return nil }
        let seconds = p[1].split(whereSeparator: { $0 == "." || $0 == "," })
        guard let sec = seconds.first.flatMap({ Int($0) }), sec < 60, sec >= 0 else { return nil }
        let fraction = seconds.count > 1 ? Double("0." + seconds[1]) ?? 0 : 0
        return Double(minutes * 60 + sec) + fraction
    }

    private static func parseWords(_ s: String) -> [LyricWord] {
        let ns = s as NSString
        let marks = wordTag.matches(in: s, range: NSRange(location: 0, length: ns.length))
        return marks.enumerated().compactMap { i, m in
            let minute = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let second = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let frac = m.range(at: 3).location != NSNotFound ? Double("0." + ns.substring(with: m.range(at: 3))) ?? 0 : 0
            let start = Double(minute * 60 + second) + frac
            let textStart = m.range.location + m.range.length
            let textEnd = i + 1 < marks.count ? marks[i + 1].range.location : ns.length
            let word = ns.substring(with: NSRange(location: textStart, length: max(0, textEnd - textStart))).trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else { return nil }
            let nextMark = i + 1 < marks.count ? ns.substring(with: marks[i + 1].range(at: 0)) : ""
            let end = i + 1 < marks.count ? timestamp(String(nextMark.dropFirst().dropLast())) ?? start + 1 : start + 1
            return LyricWord(text: word, startTime: start, endTime: max(start, end))
        }
    }
}

public struct TimelineState: Sendable {
    public let index: Int?
    public let active: LyricLine?
    public let previous: LyricLine?
    public let next: LyricLine?
    public let wordIndex: Int?
    public let lineProgress: Double
    public let wordProgress: Double
}

public enum LyricsTimeline {
    public static func state(document: LyricsDocument, time: TimeInterval, offset: TimeInterval = 0) -> TimelineState {
        let lines = document.lines
        let t = time + offset
        var low = 0, high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].startTime <= t { low = mid + 1 } else { high = mid }
        }
        let candidate = low - 1
        let index = candidate >= 0 && t < lines[candidate].endTime ? candidate : nil
        let active = index.map { lines[$0] }
        let prev = index.flatMap { $0 > 0 ? lines[$0 - 1] : nil }
        let next = index.flatMap { $0 + 1 < lines.count ? lines[$0 + 1] : nil }
        let words = active?.words ?? []
        let wordIndex = words.lastIndex(where: { $0.startTime <= t && t < $0.endTime })
        let duration = max(0.001, (active?.endTime ?? 0) - (active?.startTime ?? 0))
        let progress = active.map { min(1, max(0, (t - $0.startTime) / duration)) } ?? 0
        let wd = wordIndex.map { max(0.001, words[$0].endTime - words[$0].startTime) } ?? 1
        let wp = wordIndex.map { min(1, max(0, (t - words[$0].startTime) / wd)) } ?? 0
        return TimelineState(index: index, active: active, previous: prev, next: next, wordIndex: wordIndex, lineProgress: progress, wordProgress: wp)
    }
}

public enum WordTiming {
    public static func estimate(_ text: String, start: Double, end: Double) -> [LyricWord] {
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard end > start, !tokens.isEmpty else { return [] }
        let weights = tokens.enumerated().map { index, word in
            Double(max(1, word.count)) + (word.last.map { ",.!?;:".contains($0) } == true ? 2 : 0) + (index == tokens.count - 1 ? 2 : 0)
        }
        let total = weights.reduce(0, +)
        var cursor = start
        return tokens.enumerated().map { index, word in
            let finish = index == tokens.count - 1 ? end : cursor + (end - start) * weights[index] / total
            defer { cursor = finish }
            return LyricWord(text: word, startTime: cursor, endTime: finish)
        }
    }
}
