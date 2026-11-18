import Foundation
import PrompterCore

// Самопроверка логики PrompterCore: `swift run CoreChecks` (или ./build.sh check).

var failures = 0
var passed = 0
func check(_ cond: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    if cond { passed += 1 } else { failures += 1; print("✗ \(name) \(detail())") }
}

// MARK: Нормализация
let k = TextNormalizer.self
check(k.normalize("Ёжик,") == "ежик", "ё и пунктуация")
check(k.similarity(k.phoneticKey("parmesan"), k.phoneticKey("пармезан")) >= 0.72, "parmesan≈пармезан",
      "\(k.phoneticKey("parmesan")) / \(k.phoneticKey("пармезан"))")
check(k.similarity(k.phoneticKey("burger"), k.phoneticKey("бургер")) >= 0.9, "burger≈бургер")
check(k.similarity(k.phoneticKey("cheese"), k.phoneticKey("чиз")) >= 0.72, "cheese≈чиз",
      "\(k.phoneticKey("cheese")) / \(k.phoneticKey("чиз"))")
check(k.phoneticKey("три") == k.phoneticKey("3"), "три = 3")
check(k.similarity(k.phoneticKey("соль"), k.phoneticKey("солью")) >= 0.72, "соль≈солью")
check(k.similarity(k.phoneticKey("сковорода"), k.phoneticKey("кастрюля")) < 0.5, "разные слова")

// MARK: Документ
let src = """
# Шаг 1. Тесто
МАША: Берём три яйца [показать миску] и муку.
Перемешиваем до однородности.

# Шаг 2
Жарим на сливочном масле.
"""
let doc = PrompterDocument(src)
check(doc.sections.count == 2, "два раздела", "\(doc.sections.map(\.title))")
check(doc.words.first?.text == "Берём", "метка говорящего не слово", doc.words.first?.text ?? "nil")
check(!doc.words.contains { $0.text == "показать" }, "ремарка не слово")
check(doc.sections[1].firstWord == doc.words.firstIndex { $0.text == "Жарим" }, "начало раздела 2")
let ns = doc.displayText as NSString
check(doc.words.allSatisfy { ns.substring(with: $0.range) == $0.text }, "диапазоны слов верны")
check(doc.wordIndex(atCharacter: doc.words[4].range.location + 1) == 4, "слово по символу", "\(String(describing: doc.wordIndex(atCharacter: doc.words[3].range.location + 1))) \(doc.words.map { "\($0.text)@\($0.range.location)" })")

// MARK: Сопоставление
let script = PrompterDocument("""
Сегодня мы готовим настоящий бургер с сыром чеддер и карамелизированным луком. \
Сначала разогреваем сковороду и кладём котлету. Через три минуты переворачиваем. \
Пока котлета жарится, нарезаем помидоры и огурцы тонкими кольцами.
""")
let matcher = ScriptMatcher()
func keys(_ s: String) -> [String] { TextNormalizer.keys(from: s) }

var r = matcher.match(tail: keys("сегодня мы готовим"), pointer: 0, words: script.words)
check(r?.nextWord == 3, "чтение с начала", "\(String(describing: r))")

r = matcher.match(tail: keys("готовим настоящий бургер с сыром"), pointer: 3, words: script.words)
check(r?.nextWord == 7, "продолжение", "\(String(describing: r))")

// Ошибка распознавания и латиница/кириллица.
r = matcher.match(tail: keys("сыром чедар и карамелизированым луком"), pointer: 6, words: script.words)
check(r?.nextWord == 11, "ошибки распознавания", "\(String(describing: r))")

// Собеседник говорит своё — указатель не двигается.
r = matcher.match(tail: keys("слушай а где у нас соль вообще лежит"), pointer: 11, words: script.words)
check(r == nil, "реплика собеседника игнорируется", "\(String(describing: r))")

// Пропуск слова читающим.
r = matcher.match(tail: keys("разогреваем сковороду кладём котлету"), pointer: 11, words: script.words)
check(r?.nextWord == 17, "пропущенное слово", "\(String(describing: r))")

// Слово-паразит в середине.
r = matcher.match(tail: keys("через ну три минуты переворачиваем"), pointer: 17, words: script.words)
check(r?.nextWord == 21, "слово-паразит", "\(String(describing: r))")

// Одно короткое слово не двигает указатель.
r = matcher.match(tail: keys("и"), pointer: 11, words: script.words)
check(r == nil, "одно служебное слово не считается", "\(String(describing: r))")

// Старый хвост после того, как указатель уже ушёл вперёд, не тянет назад.
r = matcher.match(tail: keys("мы готовим"), pointer: 9, words: script.words)
check(r == nil || r!.nextWord >= 9, "нет отката от короткого хвоста", "\(String(describing: r))")

// MARK: Темп
var pace = PaceTracker()
var t = 0.0
for _ in 0..<40 { t += 0.5; pace.record(advance: 1, at: t) }  // 2 слова/с = 120
check(abs((pace.smoothedWPM ?? 0) - 120) < 8, "темп 120", "\(pace.smoothedWPM ?? -1)")
t += 6  // пауза
pace.record(advance: 1, at: t)
check((pace.smoothedWPM ?? 0) > 100, "пауза не обнуляет темп", "\(pace.smoothedWPM ?? -1)")
for _ in 0..<60 { t += 0.333; pace.record(advance: 1, at: t) }  // ~180
check((pace.smoothedWPM ?? 0) > 160, "ускорение заметно", "\(pace.smoothedWPM ?? -1)")

// MARK: Пружина
var spring = SpringFollower(position: 0)
for _ in 0..<600 { spring.step(target: 10, targetVelocity: 0, dt: 1.0 / 60) }
check(abs(spring.position - 10) < 0.01, "пружина приходит к цели")
var overshoot = false
spring = SpringFollower(position: 0)
for _ in 0..<300 { spring.step(target: 10, targetVelocity: 0, dt: 1.0 / 60); if spring.position > 10.05 { overshoot = true } }
check(!overshoot, "без перелёта")

// MARK: ETA
check(TimeEstimator.secondsRemaining(wordsRemaining: 130, wpm: 130) == 60, "ETA минута")
check(TimeEstimator.format(65) == "1:05", "формат")
check(TimeEstimator.formatDelta(-8) == "−0:08", "формат дельты")

// MARK: Анализ дубля
var samples: [TakeSample] = []
var pos = 0.0
for i in 0..<240 {
    let tt = Double(i) * 0.25
    let speed = (tt > 20 && tt < 30) ? 1.0 : 2.0  // проседание 20–30 с
    pos += speed * 0.25
    samples.append(TakeSample(t: tt, position: pos, wpm: speed * 60))
}
let take = TakeRecord(number: 1, startedAt: Date(), duration: 60, startPosition: 0, endPosition: pos,
                      totalWords: Int(pos), voiceMode: true, targetDuration: 45, samples: samples)
let analysis = TakeAnalysis(take: take)
check(analysis.spots.contains { $0.kind == .slow }, "найдено проседание", "\(analysis.bins.map { Int($0.wpm) })")
check(!analysis.spots.contains { $0.kind == .fast }, "ложных ускорений нет")


// MARK: Симуляция: чтение всего скрипта с помехами
// Моделируем поток распознавания: ошибки в словах, паразиты, пропуски,
// болтовня собеседника между разделами, перезапуски распознавателя.
// Логика указателя повторяет PlaybackEngine.handleHeard.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum ScriptText { static let sample = """
# Вступление
МАША: Привет! Сегодня готовим самый быстрый завтрак на свете — шакшуку за десять минут.
ПАША: И да, без всяких сложных штук. [показать сковородку]
# Шаг 1. Овощи
МАША: Режем лук и сладкий перец, отправляем на сковороду с оливковым маслом.
Жарим пару минут, пока лук не станет прозрачным.
# Шаг 2. Томаты
ПАША: Добавляем томаты в собственном соку, соль, перец и щепотку паприки.
Тушим ещё пять минут. [крупный план]
# Шаг 3. Яйца
МАША: Делаем ложкой лунки и аккуратно разбиваем туда яйца.
Накрываем крышкой — и через три минуты всё готово.
# Финал
ПАША: Посыпаем зеленью, берём хлеб и пробуем. Подписывайтесь, будет вкусно!
"""
}
let simScript = PrompterDocument(ScriptText.sample)
let chatter = ["слушай", "а", "где", "у", "нас", "камера", "пишет", "вообще", "погоди", "свет",
               "поправь", "нормально", "давай", "ещё", "раз", "окей", "смешно", "получилось"]
let fillers = ["ну", "эээ", "вот", "типа", "короче"]

func garble(_ w: String, _ rng: inout SplitMix) -> String {
    var chars = Array(w.lowercased())
    guard chars.count > 3 else { return w }
    switch Int.random(in: 0..<3, using: &rng) {
    case 0: chars.removeLast()                               // окончание
    case 1: if let i = chars.firstIndex(of: "о") { chars[i] = "а" } // аканье
    default: chars.insert(chars[chars.count / 2], at: chars.count / 2) // удвоение
    }
    return String(chars)
}

struct SimResult { var avgLag = 0.0, worstLag = 0, unfinished = 0, ahead = 0, chatterMoves = 0, overshoot = 0, runs = 0, words = 0 }

func simulate(_ doc: PrompterDocument, seeds: ClosedRange<Int>, garbleRate: Int, skipRate: Int,
              fillerRate: Int, chatterPool: [String], restartEvery: Int, endSlack: Int = 2) -> SimResult {
    let words = doc.words
    let n = words.count
    var r = SimResult(); r.words = n
    var lagSum = 0, lagCount = 0
    for seed in seeds {
        var rng = SplitMix(state: UInt64(seed) &* 7919)
        var anchor = 0, truth = 0
        var transcript: [String] = []
        r.runs += 1
        func feed(_ token: String, isChatter: Bool) {
            transcript.append(token)
            if Int.random(in: 0..<restartEvery, using: &rng) == 0 { transcript.removeAll() }
            let keys = transcript.suffix(12).flatMap { TextNormalizer.keys(from: $0) }
            let before = anchor
            if let m = matcher.match(tail: keys, pointer: anchor, words: words) {
                if m.nextWord > anchor { anchor = m.nextWord }
                else if Double(m.nextWord) < Double(anchor) - 2.5 { anchor = m.nextWord }
            }
            // Сдвиг от болтовни считаем, только если он увёл текст дальше
            // реально прочитанного (догнать отстающий указатель — не вред).
            if isChatter && anchor != before && anchor > truth { r.chatterMoves += 1 }
            if anchor > truth + 1 { r.ahead += 1 }
            r.overshoot = max(r.overshoot, anchor - truth)
            if ProcessInfo.processInfo.environment["SIMDEBUG"] != nil, anchor != before, isChatter || anchor > truth + 1 {
                print("    seed \(seed) «\(token)» \(before)→\(anchor) truth=\(truth) tail=\(transcript.suffix(6).joined(separator: " "))")
            }
        }
        var lastSection = words.first?.section
        for (i, w) in words.enumerated() {
            if w.section != lastSection {
                lastSection = w.section
                for _ in 0..<Int.random(in: 3...8, using: &rng) {
                    feed(chatterPool.randomElement(using: &rng)!, isChatter: true)
                }
            }
            truth = i + 1
            let roll = Int.random(in: 0..<100, using: &rng)
            if roll < skipRate { continue }
            if Int.random(in: 0..<100, using: &rng) < fillerRate { feed(fillers.randomElement(using: &rng)!, isChatter: false) }
            let spoken = Int.random(in: 0..<100, using: &rng) < garbleRate ? garble(w.text, &rng) : w.text
            feed(spoken, isChatter: false)
            let lag = truth - anchor
            if ProcessInfo.processInfo.environment["LAGDEBUG"] != nil, lag >= 6 {
                print("    LAG \(lag) seed \(seed) truth=\(truth) anchor=\(anchor) tail=\(transcript.suffix(10).joined(separator: " ")) | ждали: \(words[anchor..<min(truth, n)].map(\.text).joined(separator: " "))")
            }
            r.worstLag = max(r.worstLag, lag)
            lagSum += lag; lagCount += 1
        }
        if anchor < n - endSlack {
            r.unfinished += 1
            if ProcessInfo.processInfo.environment["SIMDEBUG"] != nil {
                print("    UNFINISHED seed \(seed) anchor=\(anchor)/\(n) tail=\(transcript.suffix(8).joined(separator: " "))")
            }
        }
    }
    r.avgLag = Double(lagSum) / Double(max(lagCount, 1))
    return r
}

func report(_ name: String, _ r: SimResult, maxAvg: Double, maxWorst: Int, maxOvershoot: Int = 1, maxChatter: Int = 0) {
    print("  \(name): \(r.runs) прогонов × \(r.words) слов; отставание ср. \(String(format: "%.2f", r.avgLag)), худшее \(r.worstLag); не дошли: \(r.unfinished); обгон читающего макс. \(r.overshoot) сл.; вредных сдвигов от болтовни: \(r.chatterMoves)")
    check(r.unfinished == 0, "\(name): дочитали до конца", "\(r.unfinished)")
    check(r.overshoot <= maxOvershoot, "\(name): обгон читающего ≤ \(maxOvershoot)", "\(r.overshoot)")
    check(r.chatterMoves <= maxChatter, "\(name): вредных сдвигов от болтовни ≤ \(maxChatter)", "\(r.chatterMoves)")
    check(r.avgLag < maxAvg, "\(name): среднее отставание < \(maxAvg)", "\(r.avgLag)")
    check(r.worstLag <= maxWorst, "\(name): худшее отставание ≤ \(maxWorst)", "\(r.worstLag)")
}

let simWords = simScript.words
report("обычная запись", simulate(simScript, seeds: 1...50, garbleRate: 15, skipRate: 5, fillerRate: 5,
                                  chatterPool: chatter, restartEvery: 45), maxAvg: 0.5, maxWorst: 8)

// Тяжёлый случай: каждое 4-е слово искажено, 10% проглочено, паразиты,
// собеседник говорит словами из того же скрипта (из уже прочитанных
// и будущих разделов), а скрипт длинный и с повторами.
// Пороги здесь мягче: если собеседник произносит ровно следующие слова
// скрипта по порядку, по содержанию это не отличить от чтения — для
// этого есть выбор микрофона/канала читающего.
let longText = Array(repeating: ScriptText.sample, count: 3).joined(separator: "\n")
let longScript = PrompterDocument(longText)
let scriptyChatter = chatter + ["лук", "соль", "перец", "яйца", "сковороду", "минут", "томаты", "крышкой", "хлеб", "зеленью"]
report("тяжёлый случай", simulate(longScript, seeds: 1...50, garbleRate: 25, skipRate: 10, fillerRate: 12,
                                  chatterPool: scriptyChatter, restartEvery: 30, endSlack: 5),
       maxAvg: 0.6, maxWorst: 12, maxOvershoot: 5, maxChatter: 40)

// MARK: Дубль с перемоткой назад: средний темп по реально прочитанному
do {
    var smp: [TakeSample] = []
    var t = 0.0, pos = 37.0
    for _ in 0..<20 { smp.append(TakeSample(t: t, position: pos, wpm: nil)); t += 0.25; pos += 0.5 } // 120 сл/мин
    pos = 18  // перемотка назад
    for _ in 0..<100 { smp.append(TakeSample(t: t, position: pos, wpm: nil)); t += 0.25; pos += 0.5 }
    let tk = TakeRecord(number: 1, startedAt: Date(), duration: t, startPosition: 37, endPosition: pos,
                        totalWords: 76, voiceMode: false, targetDuration: nil, samples: smp)
    check(abs((tk.averageWPM ?? 0) - 120) < 8, "темп дубля не портится перемоткой", "\(tk.averageWPM ?? -1)")
    let an = TakeAnalysis(take: tk)
    check(an.bins.first?.firstWord == 18 && an.bins.allSatisfy { abs($0.wpm - 120) < 10 },
          "разбор после перемотки — по последнему прочтению", "\(an.bins.map { ($0.firstWord, Int($0.wpm)) })")
}

// MARK: Перемотка назад и чтение заново
do {
    var anchor = 30
    // Оператор вернул на слово 10; распознаватель перезапущен, читают с 10-го.
    anchor = 10
    var transcript: [String] = []
    for w in simWords[10..<20] {
        transcript.append(w.text)
        if let m = matcher.match(tail: transcript.suffix(12).flatMap { TextNormalizer.keys(from: $0) },
                                 pointer: anchor, words: simWords), m.nextWord > anchor { anchor = m.nextWord }
    }
    check(anchor == 20, "после перемотки назад трекинг подхватывает", "\(anchor)")
    // Без перезапуска: старый хвост (слова 25–29) при указателе 22 —
    // это тот случай, который движок отсекает сбросом распознавания.
    let stale = simWords[25..<30].flatMap { TextNormalizer.keys(from: $0.text) }
    let r2 = matcher.match(tail: stale, pointer: 22, words: simWords)
    if ProcessInfo.processInfo.environment["SIMDEBUG"] != nil {
    let t = TextNormalizer.keys(from: "лук не станет прозрачным ещё камера")
    print("    tail keys", t, "→", String(describing: matcher.match(tail: t, pointer: 37, words: simWords)))
    print("    script keys", simWords[30..<50].map { "\($0.key)" })
}
print("  (справка) старый хвост без сброса сдвинул бы указатель на \(r2.map { String($0.nextWord) } ?? "—")")
}

print(failures == 0 ? "✓ CoreChecks: все \(passed) проверок пройдены" : "✗ CoreChecks: \(failures) из \(passed + failures) не прошли")
exit(failures == 0 ? 0 : 1)
