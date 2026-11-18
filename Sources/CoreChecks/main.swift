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

print(failures == 0 ? "✓ CoreChecks: все \(passed) проверок пройдены" : "✗ CoreChecks: \(failures) из \(passed + failures) не прошли")
exit(failures == 0 ? 0 : 1)
