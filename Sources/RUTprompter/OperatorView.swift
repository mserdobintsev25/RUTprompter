import PrompterCore
import SwiftUI

/// Окно оператора — всегда на основном экране, в нормальной ориентации.
/// Слева — редактор скрипта, справа — живое превью и показатели,
/// снизу — управление.
struct OperatorView: View {
    @ObservedObject var engine: PlaybackEngine
    @ObservedObject var settings: SettingsStore
    @ObservedObject var display: DisplayManager
    @ObservedObject var script: ScriptModel
    @ObservedObject var ui: UIState
    var openFile: () -> Void
    var saveFile: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                EditorPane(engine: engine, script: script, ui: ui, openFile: openFile, saveFile: saveFile)
                    .frame(minWidth: 320, idealWidth: 460)
                VStack(spacing: 0) {
                    PreviewPane(engine: engine, settings: settings)
                        .frame(minHeight: 260)
                    Divider()
                    StatsPanel(engine: engine, settings: settings, ui: ui)
                }
                .frame(minWidth: 460)
            }
            Divider()
            TransportBar(engine: engine, settings: settings, display: display, ui: ui)
        }
        .padding(.top, 28) // прозрачный заголовок окна
        .sheet(isPresented: $ui.showSettings) {
            SettingsView(settings: settings, engine: engine, display: display) { ui.showSettings = false }
        }
        .sheet(isPresented: $ui.showTakes) {
            TakesView(engine: engine) { ui.showTakes = false }
        }
    }
}

// MARK: - Редактор

private struct EditorPane: View {
    @ObservedObject var engine: PlaybackEngine
    @ObservedObject var script: ScriptModel
    @ObservedObject var ui: UIState
    var openFile: () -> Void
    var saveFile: () -> Void

    private var locked: Bool { engine.isPlaying && !ui.editUnlocked }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Скрипт").font(.title3.weight(.semibold))
                Text("\(engine.document.wordCount) сл. · \(engine.document.sections.count) разд.")
                    .foregroundStyle(.secondary).font(.callout)
                Spacer()
                Button(action: openFile) { Image(systemName: "folder") }.help("Открыть .txt / .md (⌘O)")
                Button(action: saveFile) { Image(systemName: "square.and.arrow.down") }.help("Сохранить как… (⌘S)")
            }
            .buttonStyle(.borderless)

            ZStack(alignment: .top) {
                TextEditor(text: $script.text)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                    .disabled(locked)
                    .opacity(locked ? 0.55 : 1)
                if locked {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("Идёт дубль — текст защищён от случайной правки")
                        Spacer()
                        Button("Править") { ui.editUnlocked = true }
                    }
                    .font(.callout)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(8)
                } else if engine.isPlaying && ui.editUnlocked {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Правка на ходу — вывод обновляется сразу")
                        Spacer()
                        Button("Готово") { ui.editUnlocked = false }
                    }
                    .font(.callout)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(8)
                }
            }

            Text("# Раздел   ·   [ремарка — не читается]   ·   ИМЯ: метка говорящего")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .onChange(of: engine.isPlaying) { playing in if !playing { ui.editUnlocked = false } }
    }
}

// MARK: - Превью

private struct PreviewPane: View {
    @ObservedObject var engine: PlaybackEngine
    @ObservedObject var settings: SettingsStore

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PrompterPreview(engine: engine, theme: settings.theme)
            Text("превью · клик по слову — перейти · прокрутка — перемотка")
                .font(.caption2)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(8)
                .allowsHitTesting(false)
        }
    }
}

struct PrompterPreview: NSViewRepresentable {
    let engine: PlaybackEngine
    let theme: PrompterTheme

    func makeNSView(context: Context) -> PrompterCanvasView {
        let v = PrompterCanvasView(role: .preview)
        v.engine = engine
        v.theme = theme
        engine.register(v)
        engine.lineLayout = v
        return v
    }

    func updateNSView(_ v: PrompterCanvasView, context: Context) {
        v.theme = theme
    }

    static func dismantleNSView(_ v: PrompterCanvasView, coordinator: ()) {
        v.engine?.unregister(v)
    }
}

// MARK: - Показатели

private struct StatsPanel: View {
    @ObservedObject var engine: PlaybackEngine
    @ObservedObject var settings: SettingsStore
    @ObservedObject var ui: UIState

    var body: some View {
        let s = engine.stats
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Metric(title: "Осталось", value: TimeEstimator.format(s.secondsRemaining), big: true)
                Metric(title: wpmTitle, value: "\(Int(s.effectiveWPM.rounded()))", unit: "сл/мин")
                Metric(title: "Дубль", value: TimeEstimator.format(s.elapsed))
                if let d = s.targetDelta {
                    Metric(title: "К цели \(TimeEstimator.format(settings.pacing.targetDuration))",
                           value: TimeEstimator.formatDelta(d),
                           tint: abs(d) < 3 ? .green : (d > 0 ? .orange : .blue))
                } else {
                    Metric(title: "Прогноз дубля", value: TimeEstimator.format(s.projectedTotal))
                }
            }

            ProgressView(value: s.progress) {
                HStack {
                    Text("\(Int(s.position.rounded())) / \(s.totalWords) слов")
                    Spacer()
                    Text("\(Int((s.progress * 100).rounded()))%")
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            if let title = s.sectionTitle {
                HStack(spacing: 8) {
                    Image(systemName: s.sectionEnding ? "exclamationmark.circle.fill" : "bookmark")
                        .foregroundStyle(s.sectionEnding ? .orange : .secondary)
                    Text(title).lineLimit(1)
                    ProgressView(value: s.sectionProgress).frame(maxWidth: 120)
                    Spacer()
                    if let left = s.sectionSecondsRemaining {
                        Text("до конца раздела \(TimeEstimator.format(left))").monospacedDigit()
                    }
                }
                .font(.callout)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(s.sectionEnding ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.08)))
            }

            VoiceRow(engine: engine, settings: settings)

            if let take = engine.lastFinishedTake {
                HStack {
                    Image(systemName: "film")
                    Text("Дубль \(take.number): \(TimeEstimator.format(take.duration))" +
                         (take.averageWPM.map { ", \(Int($0)) сл/мин" } ?? "") +
                         (take.targetDuration.map { ", цель \(TimeEstimator.formatDelta(take.duration - $0))" } ?? ""))
                    Spacer()
                    Button("Разбор дубля") { ui.showTakes = true }
                    Button { engine.lastFinishedTake = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                }
                .font(.callout)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)))
            }
        }
        .padding(12)
    }

    private var wpmTitle: String {
        if engine.effectiveMode == .fixed { return "Скорость (фикс.)" }
        return engine.stats.measuredWPM == nil ? "Темп (ожидаемый)" : "Темп (измерен)"
    }
}

private struct Metric: View {
    let title: String
    let value: String
    var unit: String? = nil
    var big = false
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: big ? 34 : 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                if let unit { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}

private struct VoiceRow: View {
    @ObservedObject var engine: PlaybackEngine
    @ObservedObject var settings: SettingsStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 18)
            if case .listening = engine.voiceStatus {
                LevelMeter(level: engine.micLevel).frame(width: 60, height: 6)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(statusText).font(.callout).lineLimit(2)
                if case .listening = engine.voiceStatus, !engine.heardText.isEmpty {
                    Text("слышу: \(engine.heardText)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
        }
    }

    private var statusText: String {
        if settings.pacing.mode == .fixed { return "Фиксированная скорость — распознавание не используется" }
        switch engine.voiceStatus {
        case .off: return "Нажмите «Старт» — прокрутка пойдёт за голосом"
        case .unavailable(let m): return "Запасной режим (фикс. скорость): " + m
        case .listening:
            if engine.stats.isTracking { return engine.voiceStatus.text + " · следую за текстом" }
            if let since = engine.stats.secondsSinceHeard, since < 60 { return engine.voiceStatus.text + " · жду текст скрипта" }
            return engine.voiceStatus.text + " · начните читать"
        default: return engine.voiceStatus.text
        }
    }

    private var icon: String {
        if settings.pacing.mode == .fixed { return "speedometer" }
        switch engine.voiceStatus {
        case .listening: return engine.stats.isTracking ? "waveform" : "mic"
        case .unavailable: return "mic.slash"
        default: return "mic"
        }
    }

    private var color: Color {
        if case .unavailable = engine.voiceStatus { return .orange }
        if case .listening = engine.voiceStatus, engine.stats.isTracking { return .green }
        return .secondary
    }
}

private struct LevelMeter: View {
    let level: Float
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(level > 0.85 ? Color.red : Color.green)
                    .frame(width: g.size.width * CGFloat(level))
            }
        }
        .animation(.linear(duration: 0.08), value: level)
    }
}

// MARK: - Управление

private struct TransportBar: View {
    @ObservedObject var engine: PlaybackEngine
    @ObservedObject var settings: SettingsStore
    @ObservedObject var display: DisplayManager
    @ObservedObject var ui: UIState

    var body: some View {
        HStack(spacing: 14) {
            Button { engine.rewind() } label: { Image(systemName: "backward.end.fill") }
                .help("В начало (Home / ⌘0)")
            Button { engine.togglePlay() } label: {
                Label(engine.isPlaying ? "Пауза" : "Старт", systemImage: engine.isPlaying ? "pause.fill" : "play.fill")
                    .frame(minWidth: 90)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .help("Пробел / ⌘↩")
            Button { engine.stop() } label: { Image(systemName: "stop.fill") }
                .help("Стоп: завершить дубль и вернуться в начало (⌘.)")

            Divider().frame(height: 22)

            Picker("", selection: $settings.pacing.mode) {
                ForEach(PacingMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 230)

            HStack(spacing: 4) {
                Stepper(value: $settings.pacing.fixedWPM, in: 40...300, step: 10) {
                    Text("\(Int(settings.pacing.fixedWPM)) сл/мин").monospacedDigit()
                }
            }
            .help(settings.pacing.mode == .fixed ? "Скорость прокрутки (+/−)" : "Скорость запасного режима, если распознавание недоступно (+/−)")

            TargetField(seconds: $settings.pacing.targetDuration)

            Spacer()

            Toggle(isOn: $settings.output.mirrorHorizontal) { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                .toggleStyle(.button)
                .help("Зеркалить второй экран (M) — окно оператора не зеркалится")

            Menu {
                if display.externalScreens.isEmpty {
                    Text("Внешний экран не подключён")
                } else {
                    ForEach(display.externalScreens, id: \.self) { name in
                        Button("На экран «\(name)»") { display.showOnExternal(named: name) }
                    }
                }
                Button("В отдельном окне (проверка)") { display.showWindowed() }
                Divider()
                Button("Закрыть вывод") { display.userClosed() }
            } label: {
                Label(outputLabel, systemImage: "display.2")
            }
            .frame(width: 200)

            Button { ui.showTakes = true } label: { Image(systemName: "film.stack") }
                .help("Дубли и разбор (⌘Y)")
            Button { ui.showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                .help("Настройки (⌘,)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var outputLabel: String {
        switch display.placement {
        case .none: return "Вывод: выкл."
        case .external(let n): return "Вывод: \(n)"
        case .windowed: return "Вывод: окно"
        }
    }
}

private struct TargetField: View {
    @Binding var seconds: Double
    @StateObject private var textBox = StateBox("")
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "target").foregroundStyle(.secondary)
            TextField("цель", text: $textBox.value)
                .frame(width: 52)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { f in if !f { commit() } }
        }
        .help("Целевая длительность дубля, например 0:45 или 60. Пусто — без цели.")
        .onAppear { textBox.value = format(seconds) }
        .onChange(of: seconds) { s in if !focused { textBox.value = format(s) } }
    }

    private func format(_ s: Double) -> String { s > 0 ? TimeEstimator.format(s) : "" }

    private func commit() {
        let t = textBox.value.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { seconds = 0; return }
        let parts = t.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2, let m = parts[0], let s = parts[1] { seconds = m * 60 + s }
        else if parts.count == 1, let s = parts[0] { seconds = s }
        textBox.value = format(seconds)
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}
