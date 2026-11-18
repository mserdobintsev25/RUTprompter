import Foundation

/// Модель скрипта: текст для показа + список слов, которые реально
/// произносятся (по ним идёт трекинг), + разделы (маркеры).
///
/// Разметка (всё необязательно):
/// - `# Заголовок` в начале строки — раздел/маркер (например, шаг рецепта);
///   показывается мелко, не произносится.
/// - `[ремарка]` — подсказка для себя («[показать сковородку]»), не
///   произносится и не учитывается в темпе.
/// - `МАША:` — метка говорящего в начале строки (заглавными), не произносится.
public struct PrompterDocument: Equatable {

    public enum RunKind: Equatable { case header, remark, speakerLabel }

    public struct StyleRun: Equatable {
        public let range: NSRange
        public let kind: RunKind
    }

    public struct Word: Equatable {
        /// Диапазон в `displayText` (UTF-16, как у NSString).
        public let range: NSRange
        public let text: String
        public let key: String
        public let weight: Double
        public let section: Int?
    }

    public struct Section: Equatable {
        public let title: String
        public let firstWord: Int
        public let headerRange: NSRange
    }

    public let source: String
    public let displayText: String
    public let words: [Word]
    public let runs: [StyleRun]
    public let sections: [Section]

    public init(_ source: String) {
        self.source = source
        var display = ""
        var length = 0  // UTF-16 длина display
        var words: [Word] = []
        var runs: [StyleRun] = []
        var sections: [Section] = []

        func append(_ s: String) -> NSRange {
            let r = NSRange(location: length, length: (s as NSString).length)
            display += s
            length += r.length
            return r
        }

        let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        for (lineIndex, rawLine) in lines.enumerated() {
            if lineIndex > 0 { _ = append("\n") }
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("#") {
                let title = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                let r = append(title.isEmpty ? "•" : title)
                runs.append(StyleRun(range: r, kind: .header))
                sections.append(Section(title: title.isEmpty ? "Раздел \(sections.count + 1)" : title,
                                        firstWord: words.count, headerRange: r))
                continue
            }

            var rest = Substring(rawLine)
            // Метка говорящего: «МАША:» / «ОН:» в начале строки.
            if let colon = rest.firstIndex(of: ":") {
                let label = rest[..<colon].trimmingCharacters(in: .whitespaces)
                let letters = label.filter { $0.isLetter }
                if !letters.isEmpty, letters.count <= 20, label.count <= 24,
                   letters.count >= 2, label == label.uppercased(),
                   label.allSatisfy({ $0.isLetter || $0 == " " || $0 == "-" || $0 == "." }) {
                    let labelText = String(rest[...colon])
                    let r = append(labelText)
                    runs.append(StyleRun(range: r, kind: .speakerLabel))
                    rest = rest[rest.index(after: colon)...]
                }
            }

            // Разбиваем строку на обычный текст и [ремарки].
            var plain = ""
            func flushPlain() {
                guard !plain.isEmpty else { return }
                let base = length
                _ = append(plain)
                let ns = plain as NSString
                for m in Self.wordRegex.matches(in: plain, range: NSRange(location: 0, length: ns.length)) {
                    let text = ns.substring(with: m.range)
                    let norm = TextNormalizer.normalize(text)
                    guard !norm.isEmpty else { continue }
                    let key = TextNormalizer.phoneticKey(norm)
                    words.append(Word(range: NSRange(location: base + m.range.location, length: m.range.length),
                                      text: text, key: key, weight: TextNormalizer.weight(of: key),
                                      section: sections.isEmpty ? nil : sections.count - 1))
                }
                plain = ""
            }
            var i = rest.startIndex
            while i < rest.endIndex {
                let ch = rest[i]
                if ch == "[" {
                    let close = rest[i...].firstIndex(of: "]") ?? rest.index(before: rest.endIndex)
                    flushPlain()
                    let r = append(String(rest[i...close]))
                    runs.append(StyleRun(range: r, kind: .remark))
                    i = rest.index(after: close)
                } else {
                    plain.append(ch)
                    i = rest.index(after: i)
                }
            }
            flushPlain()
        }

        self.displayText = display
        self.words = words
        self.runs = runs
        self.sections = sections
    }

    private static let wordRegex = try! NSRegularExpression(
        pattern: "[\\p{L}\\p{N}]+(?:[-'’][\\p{L}\\p{N}]+)*")

    public var wordCount: Int { words.count }

    /// Раздел, в котором находится позиция (индекс следующего слова).
    public func sectionIndex(at position: Double) -> Int? {
        let p = Int(position.rounded(.down))
        return sections.lastIndex { $0.firstWord <= p }
    }

    /// Первое слово следующего раздела (или конец текста).
    public func sectionEnd(_ index: Int) -> Int {
        index + 1 < sections.count ? sections[index + 1].firstWord : words.count
    }

    /// Ближайшее слово к символьной позиции в displayText.
    public func wordIndex(atCharacter location: Int) -> Int? {
        guard !words.isEmpty else { return nil }
        var lo = 0, hi = words.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if words[mid].range.location <= location { lo = mid } else { hi = mid - 1 }
        }
        // Если клик до первого слова, или после конца слова — берём следующее.
        if words[lo].range.location > location { return lo }
        if NSMaxRange(words[lo].range) <= location, lo + 1 < words.count { return lo + 1 }
        return lo
    }

    /// Длинные редкие слова — подсказка распознаванию
    /// (SFSpeechRecognitionRequest.contextualStrings).
    public func contextualHints(limit: Int = 100) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for w in words where w.text.count >= 6 || w.text.unicodeScalars.contains(where: { $0.value < 0x0400 && CharacterSet.letters.contains($0) }) {
            let lower = w.text.lowercased()
            if seen.insert(lower).inserted { out.append(w.text) }
            if out.count >= limit { break }
        }
        return out
    }

    /// Лёгкая очистка Markdown при импорте: убираем выделения и ссылки,
    /// сохраняя абзацы и заголовки `#`.
    public static func cleanImportedMarkdown(_ text: String) -> String {
        var s = text
        let patterns: [(String, String)] = [
            ("\\*\\*(.+?)\\*\\*", "$1"), ("__(.+?)__", "$1"),
            ("(?<![\\w*])\\*(?!\\s)(.+?)(?<!\\s)\\*(?![\\w*])", "$1"),
            ("\\[([^\\]]+)\\]\\([^)]*\\)", "$1"),
            ("(?m)^>\\s?", ""), ("`([^`]+)`", "$1")
        ]
        for (p, r) in patterns {
            s = s.replacingOccurrences(of: p, with: r, options: .regularExpression)
        }
        return s
    }
}
