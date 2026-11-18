import AppKit
import Combine
import PrompterCore

/// Редко меняющиеся показатели для интерфейса (обновляются ~5 раз/с,
/// чтобы SwiftUI не перерисовывался 60 раз в секунду).
struct PlaybackStats: Equatable {
    var position: Double = 0
    var totalWords: Int = 0
    var measuredWPM: Double?
    var effectiveWPM: Double = 130
    var secondsRemaining: Double = 0
    var elapsed: Double = 0
    var projectedTotal: Double = 0
    var targetDelta: Double?
    var sectionTitle: String?
    var sectionSecondsRemaining: Double?
    var sectionProgress: Double = 0
    var isTracking = false
    var secondsSinceHeard: Double?

    var progress: Double { totalWords > 0 ? min(1, position / Double(totalWords)) : 0 }
    /// Скоро конец раздела — показать плашку.
    var sectionEnding: Bool { (sectionSecondsRemaining ?? .infinity) < 6 && sectionTitle != nil }
}

enum VoiceStatus: Equatable {
    case off
    case starting
    case listening(String)
    case unavailable(String)

    var text: String {
        switch self {
        case .off: return "Распознавание выключено"
        case .starting: return "Запуск распознавания…"
        case .listening(let l): return "Слушаю (\(l), на устройстве)"
        case .unavailable(let m): return m
        }
    }
}

/// Сердце приложения: позиция в скрипте, воспроизведение, связь
/// распознавания с прокруткой, ETA, запись дублей.
///
/// Позиция хранится в словах (Double): 12.5 — середина между 12-м и
/// 13-м словом. Окна вывода сами превращают её в пиксели.
@MainActor
final class PlaybackEngine: ObservableObject {

    @Published private(set) var document: PrompterDocument
    @Published private(set) var isPlaying = false
    @Published private(set) var stats = PlaybackStats()
    @Published private(set) var voiceStatus: VoiceStatus = .off
    @Published private(set) var micLevel: Float = 0
    @Published private(set) var heardText = ""
    @Published private(set) var takes: [TakeRecord] = []
    @Published var lastFinishedTake: TakeRecord?

    let settings: SettingsStore

    /// Текущая отображаемая позиция (читают окна при каждой отрисовке).
    var displayPosition: Double { follower.position }

    /// Вид, по раскладке которого считаются «строки» для ручной перемотки.
    weak var lineLayout: PrompterCanvasView?

    private var follower = SpringFollower()
    private var target: Double = 0
    private var anchor: Double = 0
    private var anchorTime: Double = 0
    private var lastHeardMatch: Double?
    private var pace = PaceTracker()
    private let matcher = ScriptMatcher()
    private let speech = SpeechInput()
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var lastStatsUpdate = 0.0
    private var canvases = NSHashTable<PrompterCanvasView>.weakObjects()
    private var cancellables = Set<AnyCancellable>()
    private var atEndSince: Double?
    private var activity: NSObjectProtocol?

    // Дубль
    private var takeActive = false
    private var takeStartedAt = Date()
    private var takeElapsed = 0.0
    private var takeStartPosition = 0.0
    private var takeSamples: [TakeSample] = []
    private var lastSampleAt = -1.0

    init(settings: SettingsStore, text: String) {
        self.settings = settings
        self.document = PrompterDocument(text)
        speech.onTokens = { [weak self] keys, heard, _ in self?.handleHeard(keys: keys, heard: heard) }
        speech.onLevel = { [weak self] level in self?.micLevel = level }
        speech.onStatus = { [weak self] st in self?.handleSpeechStatus(st) }

        timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        refreshStats(now: CACurrentMediaTime())

        settings.$pacing
            .map(\.mode)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.modeChanged() }
            }
            .store(in: &cancellables)
    }

    // MARK: Окна

    func register(_ canvas: PrompterCanvasView) {
        canvases.add(canvas)
        canvas.setDocument(document)
    }

    func unregister(_ canvas: PrompterCanvasView) { canvases.remove(canvas) }

    // MARK: Текст

    /// Текст изменился (в т.ч. на ходу) — позиция сохраняется по индексу слова.
    func setText(_ text: String) {
        guard text != document.source else { return }
        document = PrompterDocument(text)
        let n = Double(document.wordCount)
        if follower.position > n { follower.snap(to: n) }
        target = min(target, n); anchor = min(anchor, n)
        for c in canvases.allObjects { c.setDocument(document) }
        speech.updateHints(document.contextualHints())
        refreshStats(now: CACurrentMediaTime())
    }

    // MARK: Управление

    var effectiveMode: PacingMode {
        if settings.pacing.mode == .voice, case .unavailable = voiceStatus { return .fixed }
        return settings.pacing.mode
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        guard !isPlaying, document.wordCount > 0 else { return }
        if follower.position >= Double(document.wordCount) - 0.5 { jump(to: 0, animated: false) }
        isPlaying = true
        atEndSince = nil
        // Не даём macOS (App Nap) притормаживать таймер, пока идёт дубль.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleDisplaySleepDisabled],
            reason: "Прокрутка суфлёра")
        if !takeActive { beginTake() }
        anchor = follower.position
        target = follower.position
        anchorTime = CACurrentMediaTime()
        if settings.pacing.mode == .voice { startSpeech() }
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        speech.stop()
        if case .listening = voiceStatus { voiceStatus = .off }
        if case .starting = voiceStatus { voiceStatus = .off }
        target = follower.position
        follower.velocity = 0
    }

    /// Стоп: завершить дубль и вернуться в начало — для пересъёмки.
    func stop() {
        pause()
        finishTake()
        jump(to: 0, animated: true)
    }

    func rewind() { jump(to: 0, animated: true) }

    /// Ручная перемотка. Трекинг речи «отпускает» и подхватывает заново
    /// с новой позиции, а не тянет обратно.
    func jump(to position: Double, animated: Bool) {
        let p = min(max(position, 0), Double(document.wordCount))
        target = p
        anchor = p
        anchorTime = CACurrentMediaTime()
        if !animated { follower.snap(to: p) }
        lastHeardMatch = nil
        speech.resetRecognition()
        atEndSince = nil
        redraw()
    }

    /// Плавная прокрутка колёсиком/трекпадом — без пружины.
    func scrub(to position: Double) {
        let p = min(max(position, 0), Double(document.wordCount))
        follower.snap(to: p)
        target = p
        anchor = p
        anchorTime = CACurrentMediaTime()
        speech.resetRecognition()
        redraw()
    }

    func moveLines(_ delta: Int) {
        let from = target
        let to = lineLayout?.position(byMovingLines: delta, from: from) ?? (from + Double(delta * 8))
        jump(to: to, animated: true)
    }

    func jumpToSection(offset: Int) {
        let secs = document.sections
        guard !secs.isEmpty else { return }
        let cur = document.sectionIndex(at: target + 0.01)
        var idx: Int
        if offset > 0 {
            idx = (cur.map { $0 + 1 }) ?? 0
        } else {
            idx = cur ?? 0
            // Если уже стоим в начале раздела — на предыдущий.
            if let c = cur, target - Double(secs[c].firstWord) < 1.5 { idx = c - 1 }
        }
        idx = min(max(idx, 0), secs.count - 1)
        jump(to: Double(secs[idx].firstWord), animated: true)
    }

    func adjustSpeed(_ delta: Double) {
        settings.pacing.fixedWPM = min(max(settings.pacing.fixedWPM + delta, 40), 300)
    }

    func restartSpeechIfNeeded() {
        if isPlaying && settings.pacing.mode == .voice { startSpeech() }
    }

    private func modeChanged() {
        if isPlaying {
            if settings.pacing.mode == .voice { startSpeech() } else { speech.stop(); voiceStatus = .off }
        } else if settings.pacing.mode == .fixed {
            voiceStatus = .off
        }
        anchor = follower.position
        anchorTime = CACurrentMediaTime()
    }

    // MARK: Речь

    private func startSpeech() {
        var locales = [settings.pacing.primaryLocale]
        if let s = settings.pacing.secondaryLocale, s != settings.pacing.primaryLocale { locales.append(s) }
        speech.start(.init(locales: locales, deviceUID: settings.pacing.inputDeviceUID,
                           channel: settings.pacing.inputChannel, hints: document.contextualHints()))
    }

    private func handleSpeechStatus(_ st: SpeechInput.Status) {
        switch st {
        case .idle:
            if case .unavailable = voiceStatus {} else { voiceStatus = .off }
        case .starting: voiceStatus = .starting
        case .listening(let l): voiceStatus = .listening(l.joined(separator: " + "))
        case .unavailable(let m): voiceStatus = .unavailable(m)
        }
        if case .unavailable = voiceStatus, isPlaying {
            // Запасной режим: дальше едем по фиксированной скорости.
            anchor = follower.position
            target = follower.position
            anchorTime = CACurrentMediaTime()
        }
    }

    private func handleHeard(keys: [String], heard: String) {
        heardText = heard
        guard isPlaying, effectiveMode == .voice else { return }
        let pointer = Int(anchor.rounded())
        guard let m = matcher.match(tail: keys, pointer: pointer, words: document.words) else { return }
        let now = CACurrentMediaTime()
        let p = Double(m.nextWord)
        lastHeardMatch = now
        if p > anchor + 0.01 {
            pace.record(advance: p - anchor, at: now)
            let wps = effectiveWPM / 60
            let shown = follower.position
            anchor = p
            // Экран уже уехал чуть вперёд за счёт экстраполяции — не
            // откатываем его, а продолжаем плавно с текущего места.
            if shown > p, shown - p < maxLead, wps > 0 {
                anchorTime = now - (shown - p) / wps
            } else {
                anchorTime = now
            }
        } else if p < anchor - 2.5 {
            // Уверенный откат назад: перечитывают фразу.
            anchor = p
            anchorTime = now
        }
    }

    private let maxLead = 2.0

    var effectiveWPM: Double {
        if effectiveMode == .fixed { return settings.pacing.fixedWPM }
        return pace.smoothedWPM ?? settings.pacing.baseWPM
    }

    // MARK: Такт

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        let n = Double(document.wordCount)

        var targetVelocity = 0.0
        if isPlaying {
            switch effectiveMode {
            case .fixed:
                let v = settings.pacing.fixedWPM / 60
                anchor = min(anchor + v * dt, n)
                target = anchor
                targetVelocity = anchor < n ? v : 0
            case .voice:
                // Между результатами распознавания (они приходят рывками
                // с задержкой ~0.5 с) экран немного «доезжает» вперёд в
                // текущем темпе, но не дальше чем на maxLead слов от
                // последнего услышанного места: если читающий замолчал
                // или говорит собеседник — прокрутка мягко встаёт.
                let wps = effectiveWPM / 60
                let lead = min(wps * (now - anchorTime), maxLead)
                target = min(anchor + max(lead, 0), n)
                targetVelocity = lead < maxLead && target < n ? wps : 0
            }
            takeElapsed += dt
            if takeElapsed - lastSampleAt >= 0.25 {
                lastSampleAt = takeElapsed
                takeSamples.append(TakeSample(t: takeElapsed, position: follower.position,
                                              wpm: effectiveMode == .voice ? pace.smoothedWPM : settings.pacing.fixedWPM))
            }
            if follower.position >= n - 0.05 {
                if atEndSince == nil { atEndSince = now }
                if let s = atEndSince, now - s > 1.5 {
                    pause()
                    finishTake()
                }
            }
        }

        let before = follower.position
        follower.step(target: target, targetVelocity: targetVelocity, dt: dt)
        follower.position = min(max(follower.position, 0), max(n, 0))
        if abs(follower.position - before) > 1e-5 { redraw() }

        if now - lastStatsUpdate > 0.2 { refreshStats(now: now) }
    }

    private func redraw() {
        for c in canvases.allObjects { c.positionDidChange() }
    }

    private func refreshStats(now: Double) {
        lastStatsUpdate = now
        var s = PlaybackStats()
        let n = document.wordCount
        let pos = follower.position
        s.position = pos
        s.totalWords = n
        s.measuredWPM = effectiveMode == .voice ? pace.smoothedWPM : nil
        s.effectiveWPM = effectiveWPM
        s.secondsRemaining = TimeEstimator.secondsRemaining(wordsRemaining: Double(n) - pos, wpm: s.effectiveWPM)
        s.elapsed = takeActive ? takeElapsed : 0
        s.projectedTotal = s.elapsed + s.secondsRemaining
        if settings.pacing.targetDuration > 0 {
            s.targetDelta = s.projectedTotal - settings.pacing.targetDuration
        }
        if let si = document.sectionIndex(at: pos) {
            let sec = document.sections[si]
            let end = document.sectionEnd(si)
            s.sectionTitle = sec.title
            let len = Double(max(end - sec.firstWord, 1))
            s.sectionProgress = min(1, max(0, (pos - Double(sec.firstWord)) / len))
            s.sectionSecondsRemaining = TimeEstimator.secondsRemaining(wordsRemaining: Double(end) - pos, wpm: s.effectiveWPM)
        }
        if let h = lastHeardMatch {
            s.secondsSinceHeard = now - h
            s.isTracking = now - h < 2.5
        }
        if s != stats { stats = s }
        for c in canvases.allObjects { c.statsDidChange(s) }
    }

    // MARK: Дубли

    private func beginTake() {
        takeActive = true
        takeStartedAt = Date()
        takeElapsed = 0
        takeStartPosition = follower.position
        takeSamples = [TakeSample(t: 0, position: follower.position, wpm: nil)]
        lastSampleAt = 0
    }

    private func finishTake() {
        guard takeActive else { return }
        takeActive = false
        takeSamples.append(TakeSample(t: takeElapsed, position: follower.position, wpm: pace.smoothedWPM))
        guard takeElapsed > 2 else { return }
        let rec = TakeRecord(
            number: (takes.last?.number ?? 0) + 1, startedAt: takeStartedAt, duration: takeElapsed,
            startPosition: takeStartPosition, endPosition: follower.position,
            totalWords: document.wordCount, voiceMode: settings.pacing.mode == .voice,
            targetDuration: settings.pacing.targetDuration > 0 ? settings.pacing.targetDuration : nil,
            samples: takeSamples)
        takes.append(rec)
        lastFinishedTake = rec
    }

    /// Текст отрывка для пост-анализа.
    func excerpt(from first: Int, to last: Int, maxWords: Int = 8) -> String {
        guard first < document.words.count else { return "" }
        let end = min(last, first + maxWords - 1, document.words.count - 1)
        let words = document.words[first...end].map(\.text).joined(separator: " ")
        return end < last ? words + "…" : words
    }
}
