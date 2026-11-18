import Foundation

public struct TakeSample: Equatable, Codable {
    /// Активное время дубля (без пауз), сек.
    public let t: Double
    /// Позиция в словах.
    public let position: Double
    public let wpm: Double?

    public init(t: Double, position: Double, wpm: Double?) {
        self.t = t; self.position = position; self.wpm = wpm
    }
}

public struct TakeRecord: Identifiable, Equatable {
    public let id = UUID()
    public let number: Int
    public let startedAt: Date
    public let duration: Double
    public let startPosition: Double
    public let endPosition: Double
    public let totalWords: Int
    public let voiceMode: Bool
    public let targetDuration: Double?
    public let samples: [TakeSample]

    public init(number: Int, startedAt: Date, duration: Double, startPosition: Double,
                endPosition: Double, totalWords: Int, voiceMode: Bool,
                targetDuration: Double?, samples: [TakeSample]) {
        self.number = number; self.startedAt = startedAt; self.duration = duration
        self.startPosition = startPosition; self.endPosition = endPosition
        self.totalWords = totalWords; self.voiceMode = voiceMode
        self.targetDuration = targetDuration; self.samples = samples
    }

    public var wordsRead: Double { max(0, endPosition - startPosition) }
    public var averageWPM: Double? { duration > 3 && wordsRead > 3 ? wordsRead / duration * 60 : nil }
    public var completed: Bool { endPosition >= Double(totalWords) - 0.5 }
}

/// Пост-анализ дубля: темп по кускам текста и места, где он заметно
/// проседал или разгонялся.
public struct TakeAnalysis {
    public struct Bin: Equatable, Identifiable {
        public var id: Int { firstWord }
        public let firstWord: Int
        public let lastWord: Int
        public let seconds: Double
        public var wpm: Double { seconds > 0.2 ? Double(lastWord - firstWord + 1) / seconds * 60 : 0 }
    }

    public enum SpotKind { case slow, fast }

    public struct Spot: Identifiable {
        public var id: Int { bin.firstWord }
        public let bin: Bin
        public let kind: SpotKind
        public let deviation: Double  // доля от медианы, например −0.3
    }

    public let bins: [Bin]
    public let medianWPM: Double?
    public let spots: [Spot]

    public init(take: TakeRecord, binSize: Int = 15, threshold: Double = 0.25) {
        var bins: [Bin] = []
        let s = take.samples
        let start = Int(take.startPosition.rounded(.down))
        let end = Int(take.endPosition.rounded(.down))
        if s.count >= 2, end > start {
            var first = start
            while first < end {
                let last = min(first + binSize - 1, end - 1)
                if let t0 = Self.time(at: Double(first), in: s),
                   let t1 = Self.time(at: Double(last + 1), in: s) {
                    bins.append(Bin(firstWord: first, lastWord: last, seconds: t1 - t0))
                }
                first = last + 1
            }
        }
        // Последний короткий кусок плохо показателен.
        let usable = bins.filter { $0.lastWord - $0.firstWord >= binSize / 2 && $0.wpm > 0 }
        let sorted = usable.map(\.wpm).sorted()
        let median = sorted.isEmpty ? nil : sorted[sorted.count / 2]
        var spots: [Spot] = []
        if let median, median > 0 {
            for b in usable {
                let dev = b.wpm / median - 1
                if dev <= -threshold { spots.append(Spot(bin: b, kind: .slow, deviation: dev)) }
                if dev >= threshold { spots.append(Spot(bin: b, kind: .fast, deviation: dev)) }
            }
        }
        self.bins = bins
        self.medianWPM = median
        self.spots = spots
    }

    /// Момент, когда позиция впервые достигла `position`.
    static func time(at position: Double, in s: [TakeSample]) -> Double? {
        guard let k = s.firstIndex(where: { $0.position >= position }) else { return nil }
        if k == 0 { return s[0].t }
        let a = s[k - 1], b = s[k]
        let span = b.position - a.position
        guard span > 0 else { return b.t }
        return a.t + (b.t - a.t) * (position - a.position) / span
    }
}
