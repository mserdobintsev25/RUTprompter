import AVFoundation
import AudioToolbox
import Foundation
import PrompterCore
import Speech

/// Микрофон + on-device распознавание речи.
///
/// Отдаёт наружу только «что услышано» (фонетические ключи последних
/// слов). Никаких команд из речи не извлекается — это жёсткое
/// требование проекта: голос используется только для трекинга темпа.
///
/// Можно запустить две модели параллельно (например ru-RU + en-US) —
/// обе получают один и тот же звук, сопоставление берёт лучшее.
final class SpeechInput {

    enum Status: Equatable {
        case idle
        case starting
        case listening(locales: [String])
        case unavailable(String)
    }

    struct Config: Equatable {
        var locales: [String]
        var deviceUID: String?
        var channel: Int
        var hints: [String]
    }

    /// Все колбэки — на главном потоке.
    var onTokens: ((_ keys: [String], _ heard: String, _ channel: Int) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onStatus: ((Status) -> Void)?

    private final class Channel {
        let index: Int
        let recognizer: SFSpeechRecognizer
        var request: SFSpeechAudioBufferRecognitionRequest?
        var task: SFSpeechRecognitionTask?
        var generation = 0
        var startedAt = Date()
        var quickFailures = 0
        init(index: Int, recognizer: SFSpeechRecognizer) { self.index = index; self.recognizer = recognizer }
    }

    private var engine: AVAudioEngine?
    private var channels: [Channel] = []
    private let lock = NSLock()
    private var config: Config?
    private(set) var isRunning = false
    private var lastLevelSent = Date.distantPast

    static var isRunningFromAppBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    // MARK: Запуск / остановка

    func start(_ config: Config) {
        stop()
        self.config = config
        isRunning = true
        onStatus?(.starting)

        guard Self.isRunningFromAppBundle else {
            fail("Распознавание работает только в собранном RUTprompter.app (./build.sh run)")
            return
        }
        requestPermissions { [weak self] error in
            guard let self, self.isRunning else { return }
            if let error { self.fail(error); return }
            self.startAudio(config)
        }
    }

    func stop() {
        isRunning = false
        lock.lock()
        let old = channels
        channels = []
        lock.unlock()
        for ch in old {
            ch.generation += 1
            ch.request?.endAudio()
            ch.task?.cancel()
        }
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        onStatus?(.idle)
    }

    /// Начать распознавание «с чистого листа» — после ручной перемотки,
    /// чтобы старый хвост фразы не тянул указатель обратно.
    /// Вызывается часто (прокрутка трекпадом), поэтому сбрасываем один раз
    /// после того, как перемотка утихла.
    func resetRecognition() {
        guard isRunning else { return }
        pendingReset?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            self.lock.lock()
            let list = self.channels
            self.lock.unlock()
            for ch in list { self.beginTask(ch) }
        }
        pendingReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    private var pendingReset: DispatchWorkItem?

    func updateHints(_ hints: [String]) {
        config?.hints = hints
    }

    // MARK: Внутреннее

    private func fail(_ message: String) {
        stop()
        onStatus?(.unavailable(message))
    }

    private func requestPermissions(_ done: @escaping (String?) -> Void) {
        func speech() {
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: done(nil)
            case .notDetermined:
                SFSpeechRecognizer.requestAuthorization { st in
                    DispatchQueue.main.async { done(st == .authorized ? nil : "Нет доступа к распознаванию речи (Настройки → Конфиденциальность → Распознавание речи)") }
                }
            default: done("Нет доступа к распознаванию речи (Настройки → Конфиденциальность → Распознавание речи)")
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: speech()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async { ok ? speech() : done("Нет доступа к микрофону (Настройки → Конфиденциальность → Микрофон)") }
            }
        default: done("Нет доступа к микрофону (Настройки → Конфиденциальность → Микрофон)")
        }
    }

    private func startAudio(_ config: Config) {
        // Модели — строго на устройстве: звук никуда не отправляется.
        var list: [Channel] = []
        var problems: [String] = []
        for (i, id) in config.locales.enumerated() {
            guard let r = SFSpeechRecognizer(locale: Locale(identifier: id)) else {
                problems.append("\(id): язык не поддерживается"); continue
            }
            guard r.supportsOnDeviceRecognition else {
                problems.append("\(id): нет офлайн-модели (Настройки → Клавиатура → Диктовка, добавьте язык)"); continue
            }
            list.append(Channel(index: i, recognizer: r))
        }
        guard !list.isEmpty else {
            fail(problems.first ?? "Распознавание недоступно")
            return
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let dev = AudioDevices.device(uid: config.deviceUID), let unit = input.audioUnit {
            var devID = dev.id
            let st = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0, &devID,
                                          UInt32(MemoryLayout<AudioDeviceID>.size))
            if st != noErr { problems.append("не удалось выбрать микрофон «\(dev.name)», использую системный") }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("Микрофон не найден")
            return
        }
        guard let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate,
                                       channels: 1, interleaved: false) else {
            fail("Не удалось настроить аудиоформат")
            return
        }
        let pick = config.channel  // 0 — смешать, n — канал n
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            guard let out = Self.makeMono(buffer, format: mono, channel: pick) else { return }
            self.reportLevel(out)
            self.lock.lock()
            let list = self.channels
            self.lock.unlock()
            for ch in list { ch.request?.append(out) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            fail("Микрофон не запустился: \(error.localizedDescription)")
            return
        }
        self.engine = engine
        lock.lock()
        channels = list
        lock.unlock()
        for ch in list { beginTask(ch) }
        onStatus?(.listening(locales: list.map { $0.recognizer.locale.identifier }))
        if !problems.isEmpty { NSLog("RUTprompter speech: %@", problems.joined(separator: "; ")) }
    }

    private func beginTask(_ ch: Channel) {
        ch.generation += 1
        let gen = ch.generation
        ch.request?.endAudio()
        ch.task?.cancel()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        if #available(macOS 13, *) { req.addsPunctuation = false }
        req.contextualStrings = config?.hints ?? []
        ch.request = req
        ch.startedAt = Date()

        ch.task = ch.recognizer.recognitionTask(with: req) { [weak self, weak ch] result, error in
            guard let self, let ch else { return }
            DispatchQueue.main.async {
                guard self.isRunning, ch.generation == gen else { return }
                if let result {
                    let segs = result.bestTranscription.segments
                    let tail = segs.suffix(12).map(\.substring)
                    let keys = tail.flatMap { TextNormalizer.keys(from: $0) }
                    self.onTokens?(keys, tail.suffix(8).joined(separator: " "), ch.index)
                    if result.isFinal || segs.count > 300 {
                        ch.quickFailures = 0
                        self.beginTask(ch)
                        return
                    }
                }
                if let error {
                    let lived = Date().timeIntervalSince(ch.startedAt)
                    ch.quickFailures = lived < 2 ? ch.quickFailures + 1 : 0
                    if ch.quickFailures >= 4 {
                        self.fail("Распознавание остановилось: \(error.localizedDescription)")
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + (lived < 2 ? 0.6 : 0.05)) {
                        guard self.isRunning, ch.generation == gen else { return }
                        self.beginTask(ch)
                    }
                }
            }
        }
    }

    private func reportLevel(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(n))
        let db = 20 * log10(max(rms, 1e-6))
        let level = max(0, min(1, (db + 55) / 50))
        let now = Date()
        guard now.timeIntervalSince(lastLevelSent) > 0.06 else { return }
        lastLevelSent = now
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
    }

    private static func makeMono(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat, channel: Int) -> AVAudioPCMBuffer? {
        guard let src = buffer.floatChannelData,
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
              let dst = out.floatChannelData?[0] else { return nil }
        let n = Int(buffer.frameLength)
        let chCount = Int(buffer.format.channelCount)
        out.frameLength = buffer.frameLength
        if channel > 0 && channel <= chCount {
            let s = src[channel - 1]
            for i in 0..<n { dst[i] = s[i] }
        } else {
            let k = 1 / Float(chCount)
            for i in 0..<n {
                var v: Float = 0
                for c in 0..<chCount { v += src[c][i] }
                dst[i] = v * k
            }
        }
        return out
    }
}
