import Foundation

/// Нормализация слов для сопоставления распознанной речи со скриптом.
///
/// Две ступени:
/// - `normalize` — нижний регистр, ё→е, только буквы/цифры;
/// - `phoneticKey` — грубый «звуковой» ключ в латинице. Нужен потому, что
///   русская модель распознавания пишет иностранные слова кириллицей
///   («пармезан»), а в скрипте они могут быть латиницей («parmesan»),
///   и наоборот.
public enum TextNormalizer {

    public static func normalize<S: StringProtocol>(_ word: S) -> String {
        var out = ""
        out.reserveCapacity(word.count)
        for ch in word.lowercased() {
            if ch == "ё" { out.append("е"); continue }
            if ch.isLetter || ch.isNumber { out.append(ch) }
        }
        return out
    }

    /// Числительные → цифры: распознавание обычно пишет «3», а в скрипте
    /// может стоять «три» (и наоборот).
    private static let numberWords: [String: String] = [
        "ноль": "0", "один": "1", "одна": "1", "одно": "1", "два": "2", "две": "2",
        "три": "3", "четыре": "4", "пять": "5", "шесть": "6", "семь": "7",
        "восемь": "8", "девять": "9", "десять": "10", "одиннадцать": "11",
        "двенадцать": "12", "тринадцать": "13", "четырнадцать": "14",
        "пятнадцать": "15", "шестнадцать": "16", "семнадцать": "17",
        "восемнадцать": "18", "девятнадцать": "19", "двадцать": "20",
        "тридцать": "30", "сорок": "40", "пятьдесят": "50", "шестьдесят": "60",
        "семьдесят": "70", "восемьдесят": "80", "девяносто": "90", "сто": "100",
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
        "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10",
        "eleven": "11", "twelve": "12", "twenty": "20", "hundred": "100"
    ]

    private static let cyrToLat: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ж": "zh",
        "з": "z", "и": "i", "й": "i", "к": "k", "л": "l", "м": "m", "н": "n",
        "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f",
        "х": "h", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sh", "ъ": "", "ы": "i",
        "ь": "", "э": "e", "ю": "yu", "я": "ya", "і": "i", "ї": "i", "є": "e"
    ]

    /// Грубый фонетический ключ. Не претендует на точность — задача
    /// только сблизить «бургер»/«burger», «чиз»/«cheese», «соус»/«sous».
    public static func phoneticKey(_ normalized: String) -> String {
        if let digit = numberWords[normalized] { return digit }
        var s = ""
        for ch in normalized {
            if let lat = cyrToLat[ch] { s += lat } else { s.append(ch) }
        }
        // Латинские сочетания → как их пишет русская модель.
        let rules: [(String, String)] = [
            ("sch", "sh"), ("tch", "ch"), ("ph", "f"), ("ck", "k"), ("th", "t"),
            ("ee", "i"), ("ea", "i"), ("oo", "u"), ("ou", "u"), ("dzh", "j"),
            ("ce", "se"), ("ci", "si"), ("cy", "si"), ("ch", "\u{1}"),
            ("c", "k"), ("q", "k"), ("x", "ks"), ("w", "v"), ("y", "i"),
            ("z", "s"), ("\u{1}", "ch")
        ]
        for (from, to) in rules { s = s.replacingOccurrences(of: from, with: to) }
        // Схлопываем удвоения и немую конечную «e» (cheese → chis).
        var collapsed = ""
        var last: Character?
        for ch in s where ch != last {
            collapsed.append(ch)
            last = ch
        }
        if collapsed.count > 3, collapsed.hasSuffix("e"),
           normalized.unicodeScalars.first.map({ $0.value < 0x0400 }) == true {
            collapsed.removeLast()
        }
        return collapsed
    }

    /// Похожесть двух ключей 0...1.
    public static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return a.isEmpty ? 0 : 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        let aa = Array(a), bb = Array(b)
        // Окончания в русском часто «плывут» (соль/соли/солью):
        // общий корень от 4 символов считаем почти совпадением.
        let common = zip(aa, bb).prefix { $0 == $1 }.count
        let minLen = min(aa.count, bb.count)
        if common >= 4 && common >= minLen - 1 { return 0.86 }
        if common >= 3 && common == minLen && max(aa.count, bb.count) - minLen <= 2 { return 0.78 }
        let dist = levenshtein(aa, bb)
        return max(0, 1 - Double(dist) / Double(max(aa.count, bb.count)))
    }

    /// Вес слова для сопоставления: служебные короткие слова почти ничего
    /// не доказывают, длинные — доказывают.
    public static func weight(of key: String) -> Double {
        switch key.count {
        case 0: return 0
        case 1...2: return 0.35
        case 3: return 0.7
        default: return 1.0
        }
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    /// Разбивает произвольную фразу на ключи (для распознанного текста).
    public static func keys(from text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { normalize($0) }
            .filter { !$0.isEmpty }
            .map { phoneticKey($0) }
    }
}
