import Foundation

/// Сглаженный темп чтения (слов скрипта в минуту) по продвижениям
/// указателя. Паузы (собеседник говорит, читающий молчит) не роняют темп
/// до нуля: длинные промежутки обрезаются, поэтому меряется именно
/// скорость чтения, а не «слова за время дубля».
public struct PaceTracker {
    public private(set) var smoothedWPM: Double?
    public var window: Double = 12
    public var gapCap: Double = 0.9
    public var tau: Double = 4

    private var events: [(t: Double, words: Double)] = []
    private var lastUpdate: Double?

    public init() {}

    public mutating func reset() {
        events.removeAll()
        smoothedWPM = nil
        lastUpdate = nil
    }

    /// Указатель продвинулся на `words` слов в момент `t` (секунды).
    public mutating func record(advance words: Double, at t: Double) {
        guard words > 0 else { return }
        // Большие скачки — ручная перемотка или пропуск, не чтение.
        if words > 6 {
            events.removeAll()
            events.append((t, 0))
            return
        }
        events.append((t, words))
        events.removeAll { t - $0.t > window }
        guard let inst = instantaneous() else { return }
        if let prev = smoothedWPM, let lu = lastUpdate {
            let alpha = 1 - exp(-max(t - lu, 0.05) / tau)
            smoothedWPM = prev + (inst - prev) * alpha
        } else {
            smoothedWPM = inst
        }
        smoothedWPM = min(max(smoothedWPM!, 40), 320)
        lastUpdate = t
    }

    func instantaneous() -> Double? {
        guard events.count >= 2 else { return nil }
        var active = 0.0, total = 0.0
        for k in 1..<events.count {
            active += min(events[k].t - events[k - 1].t, gapCap)
            total += events[k].words
        }
        guard active >= 1.5, total >= 3 else { return nil }
        return total / active * 60
    }
}

/// Критически демпфированная пружина с прямой подачей скорости цели:
/// при равномерно движущейся цели отставания нет, а скачки цели
/// сглаживаются без перелёта и рывков.
public struct SpringFollower {
    public var position: Double
    public var velocity: Double = 0
    /// Жёсткость: больше — быстрее догоняет.
    public var omega: Double = 5

    public init(position: Double = 0) { self.position = position }

    public mutating func step(target: Double, targetVelocity: Double, dt: Double) {
        var remaining = min(dt, 0.25)
        while remaining > 0 {
            let h = min(remaining, 1.0 / 120)
            let x = position - target
            let a = -omega * omega * x - 2 * omega * (velocity - targetVelocity)
            velocity += a * h
            position += velocity * h
            remaining -= h
        }
    }

    public mutating func snap(to p: Double) {
        position = p
        velocity = 0
    }
}

public enum TimeEstimator {
    public static func secondsRemaining(wordsRemaining: Double, wpm: Double) -> Double {
        guard wpm > 1 else { return 0 }
        return max(wordsRemaining, 0) / wpm * 60
    }

    /// «1:05»
    public static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "—" }
        let s = Int(max(seconds, 0).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// «+0:15» / «−0:08»
    public static func formatDelta(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "—" }
        let sign = seconds >= 0 ? "+" : "−"
        return sign + format(abs(seconds))
    }
}
