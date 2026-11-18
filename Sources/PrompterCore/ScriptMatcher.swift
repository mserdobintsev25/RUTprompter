import Foundation

/// Сопоставляет «хвост» распознанной речи (последние несколько слов) с
/// текстом скрипта рядом с текущей позицией и решает, куда сдвинуть
/// указатель.
///
/// Это и есть базовая «диаризация по содержанию»: реплики собеседника,
/// которых нет в скрипте, ни с чем не совпадают и указатель не двигают.
/// Голос никогда не интерпретируется как команда.
public struct ScriptMatcher {

    public struct Match: Equatable {
        /// Индекс следующего слова, которое предстоит прочитать.
        public let nextWord: Int
        public let matchedWords: Int
        public let score: Double
    }

    public var tailLength = 8
    public var lookBehind = 12
    public var lookAhead = 40
    public var similarityThreshold = 0.72

    public init() {}

    /// - Parameters:
    ///   - tail: фонетические ключи последних распознанных слов.
    ///   - pointer: текущий индекс следующего слова.
    public func match(tail fullTail: [String], pointer: Int, words: [PrompterDocument.Word]) -> Match? {
        let n = words.count
        guard n > 0 else { return nil }
        let tail = Array(fullTail.suffix(tailLength)).filter { !$0.isEmpty }
        let m = tail.count
        guard m > 0 else { return nil }
        let p = min(max(pointer, 0), n)
        let lo = max(0, p - lookBehind)
        let hi = min(n - 1, p + lookAhead)
        guard lo <= hi else { return nil }
        let L = hi - lo + 1

        // Smith–Waterman: H[i][j] — лучшая локальная выравнивающая цепочка,
        // заканчивающаяся на tail[i-1] и words[lo+j-1].
        var H = [[Double]](repeating: [Double](repeating: 0, count: L + 1), count: m + 1)
        var C = [[Int]](repeating: [Int](repeating: 0, count: L + 1), count: m + 1)
        // «Вес доказательства» текущей цепочки: сумма весов совпавших слов.
        var E = [[Double]](repeating: [Double](repeating: 0, count: L + 1), count: m + 1)
        var endsWithMatch = [[Bool]](repeating: [Bool](repeating: false, count: L + 1), count: m + 1)
        // Сколько слов скрипта подряд пропущено перед этой клеткой. После
        // разрыва > maxGap совпадения считаются заново: иначе старые
        // совпавшие слова «перетягивают» одно случайное слово далеко вперёд.
        var G = [[Int]](repeating: [Int](repeating: 0, count: L + 1), count: m + 1)
        // Сколько распознанных слов подряд не совпало (чужая речь). После
        // 2+ таких слов нужно свежее подтверждение: одно слово из скрипта,
        // сказанное собеседником, не должно цепляться к старым совпадениям.
        var T = [[Int]](repeating: [Int](repeating: 0, count: L + 1), count: m + 1)
        let maxGap = 2
        let maxForeign = 2

        for i in 1...m {
            for j in 1...L {
                let w = words[lo + j - 1]
                let sim = TextNormalizer.similarity(tail[i - 1], w.key)
                var best = 0.0, cnt = 0, ev = 0.0, gap = 0, foreign = 0, isMatch = false
                if sim >= similarityThreshold {
                    let v = H[i - 1][j - 1] + w.weight * sim
                    if v > best {
                        best = v
                        let fresh = T[i - 1][j - 1] >= maxForeign
                        cnt = (fresh ? 0 : C[i - 1][j - 1]) + (w.weight >= 0.7 ? 1 : 0)
                        ev = (fresh ? 0 : E[i - 1][j - 1]) + w.weight
                        if fresh { best = w.weight * sim }  // цепочка начинается заново
                        gap = 0; foreign = 0; isMatch = true
                    }
                } else {
                    // Замена: слово скрипта не прочитано, распознанное — чужое.
                    let v = H[i - 1][j - 1] - 0.5
                    if v > best {
                        best = v
                        gap = G[i - 1][j - 1] + 1
                        foreign = T[i - 1][j - 1] + 1
                        cnt = gap > maxGap ? 0 : C[i - 1][j - 1]
                        ev = gap > maxGap ? 0 : E[i - 1][j - 1]
                    }
                }
                // Лишнее распознанное слово (вода, оговорка, слово собеседника).
                let skipTail = H[i - 1][j] - 0.35
                if skipTail > best {
                    best = skipTail; cnt = C[i - 1][j]; ev = E[i - 1][j]; gap = G[i - 1][j]
                    foreign = T[i - 1][j] + 1; isMatch = false
                }
                // Пропущенное в речи слово скрипта.
                let skipWord = H[i][j - 1] - 0.3
                if skipWord > best {
                    best = skipWord
                    gap = G[i][j - 1] + 1
                    foreign = T[i][j - 1]
                    cnt = gap > maxGap ? 0 : C[i][j - 1]
                    ev = gap > maxGap ? 0 : E[i][j - 1]
                    isMatch = false
                }
                H[i][j] = best
                C[i][j] = cnt
                E[i][j] = ev
                G[i][j] = gap
                T[i][j] = foreign
                endsWithMatch[i][j] = isMatch
            }
        }

        var bestMatch: Match?
        var bestAdjusted = -Double.infinity
        for i in max(1, m - 1)...m {
            for j in 1...L where endsWithMatch[i][j] {
                var score = H[i][j]
                if i < m { score -= 0.25 }       // последнее слово не совпало
                let next = lo + j               // слово после совпавшего
                let delta = next - p
                let matched = C[i][j]
                let lastWeight = words[lo + j - 1].weight

                // Правила принятия.
                if delta < 0 {
                    // Назад — только уверенно (перечитали фразу заново).
                    guard matched >= 3, score >= 2.4 else { continue }
                    score -= 0.12 * Double(-delta)
                } else if delta > 4 {
                    // Дальний прыжок (читающий пропустил кусок) — только по
                    // весомой цепочке (сумма весов ≥ 2.6, из них 2+ длинных слова): двух слов из рецепта в разговоре
                    // («перец… сковороду») недостаточно.
                    guard matched >= 2, E[i][j] >= 2.6, score >= 2.0 else { continue }
                    score -= 0.04 * Double(delta - 3)
                } else {
                    let single = matched <= 1
                    if single {
                        // Одно слово — только если оно длинное и прямо следующее
                        // (или через одно): случайное слово собеседника из
                        // скрипта не должно утаскивать текст.
                        guard delta == 1, lastWeight >= 1.0, score >= 0.8 else { continue }
                    } else {
                        guard score >= 1.2 else { continue }
                    }
                    score -= 0.04 * Double(max(0, delta - 3))
                }
                if score > bestAdjusted {
                    bestAdjusted = score
                    bestMatch = Match(nextWord: next, matchedWords: matched, score: score)
                }
            }
        }
        return bestMatch
    }
}
