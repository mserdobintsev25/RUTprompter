import PrompterCore
import SwiftUI

enum AppPage: String, CaseIterable, Identifiable {
    case script, takes, appearance, output, speech
    var id: String { rawValue }

    var title: String {
        switch self {
        case .script: return "Сценарий"
        case .takes: return "Дубли"
        case .appearance: return "Оформление"
        case .output: return "Вывод"
        case .speech: return "Речь и микрофон"
        }
    }

    var icon: String {
        switch self {
        case .script: return "doc.text"
        case .takes: return "film.stack"
        case .appearance: return "textformat"
        case .output: return "display"
        case .speech: return "mic"
        }
    }
}

private func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let m10 = n % 10, m100 = n % 100
    let form = (m10 == 1 && m100 != 11) ? one : ((2...4).contains(m10) && !(12...14).contains(m100) ? few : many)
    return "\(n) \(form)"
}

/// Окно оператора «Студия»: боковая панель, страница, плавающая капсула управления.
struct OperatorView: View {
    @ObservedObject var engine: PlaybackEngine
    @ObservedObject var settings: SettingsStore
    @ObservedObject var display: DisplayManager
    @ObservedObject var script: ScriptModel
    @ObservedObject var ui: UIState
    var openFile: () -> Void
    var saveFile: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(engine: engine, settings: settings, ui: ui)
                .frame(width: 236)
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    ToolbarRow(engine: engine, settings: settings, display: display, ui: ui)
                    pageContent
                }
                TransportCapsule(engine: engine, settings: settings)
                    .padding(.bottom, 24)
            }
            .background(Brand.bg)
        }
        .ignoresSafeArea()
        .frame(minWidth: 980, minHeight: 640)
    }

    @ViewBuilder private var pageContent: some View {
        switch ui.page {
        case .script:
            ScriptPage(engine: engine, settings: settings, script: script, ui: ui, openFile: openFile, saveFile: saveFile)
        case .takes: TakesPage(engine: engine)
        case .appearance: AppearancePage(settings: settings)
        case .output: OutputPage(settings: settings, display: display)
        case .speech: SpeechPage(settings: settings, engine: engine)
        }
    }
}

// MARK: - Боковая панель

private struct SidebarView: View {
    @ObservedObject var engine: PlaybackEngine
    @ObservedObject var settings: SettingsStore
    @ObservedObject var ui: UIState

    private struct Item: Identifiable {
        enum State { case done, current, upcoming }
        let id: Int
        let title: String
        let first: Int
        let seconds: Double
        let state: State
        let progress: Double
    }

    private var items: [Item] {
        let doc = engine.document
        let pos = engine.stats.position
        let wpm = engine.stats.effectiveWPM
        return doc.sections.enumerated().map { i, sec in
            let end = doc.sectionEnd(i)
            let len = Double(max(end - sec.firstWord, 1))
            let state: Item.State = pos >= Double(end) ? .done : (pos >= Double(sec.firstWord) ? .current : .upcoming)
            return Item(id: i, title: sec.title, first: sec.firstWord,
                        seconds: TimeEstimator.secondsRemaining(wordsRemaining: len, wpm: wpm),
                        state: state, progress: min(1, max(0, (pos - Double(sec.firstWord)) / len)))
        }
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar)
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 40)
                HStack(spacing: 10) {
                    BrandTile(size: 32)
                    Text("RUTprompter").font(.system(size: 17, weight: .heavy)).tracking(-0.2).foregroundColor(Brand.tx)
                }
                .padding(.horizontal, 8).padding(.bottom, 16)

                VStack(spacing: 2) {
                    navItem(.script, badge: nil)
                    navItem(.takes, badge: engine.takes.isEmpty ? nil : "\(engine.takes.count)")
                    navItem(.appearance, badge: nil)
                    navItem(.output, badge: nil)
                }

                Text("РАЗДЕЛЫ").font(.system(size: 11, weight: .bold)).tracking(1.1)
                    .foregroundColor(Brand.tx2).padding(.horizontal, 10).padding(.top, 20).padding(.bottom, 6)

                if items.isEmpty {
                    Text("Начните строку с «# », чтобы добавить раздел.")
                        .font(.system(size: 12)).foregroundColor(Brand.tx2).padding(.horizontal, 10)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 2) { ForEach(items) { sectionRow($0) } }
                    }
                }
                Spacer(minLength: 8)
                MicCard(engine: engine, settings: settings, ui: ui)
            }
            .padding(.horizontal, 12).padding(.bottom, 14)
        }
        .overlay(alignment: .trailing) { Rectangle().fill(Brand.line).frame(width: 1) }
    }

    private func navItem(_ page: AppPage, badge: String?) -> some View {
        let on = ui.page == page
        return Button { ui.page = page } label: {
            HStack(spacing: 10) {
                Image(systemName: page.icon).font(.system(size: 14, weight: .medium)).frame(width: 20)
                Text(page.title).font(.system(size: 13, weight: on ? .semibold : .medium))
                Spacer()
                if let badge { Text(badge).font(.system(size: 12)).opacity(0.8) }
            }
            .foregroundColor(on ? .white : Brand.tx)
            .padding(.horizontal, 10).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Brand.accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionRow(_ it: Item) -> some View {
        Button {
            ui.page = .script
            engine.jump(to: Double(it.first), animated: true)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().strokeBorder(it.state == .upcoming ? Brand.line2 : (it.state == .done ? Brand.accent : Brand.hi), lineWidth: 2)
                    if it.state == .done {
                        Circle().fill(Brand.accent)
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundColor(.white)
                    } else if it.state == .current {
                        Circle().fill(Brand.hi).frame(width: 6, height: 6)
                    }
                }
                .frame(width: 16, height: 16)
                Text(it.title).font(.system(size: 13, weight: it.state == .current ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 4)
                Text(TimeEstimator.format(it.seconds)).font(.system(size: 12)).monospacedDigit().foregroundColor(Brand.tx2)
            }
            .foregroundColor(it.state == .done ? Brand.tx2 : Brand.tx)
            .padding(.horizontal, 10).frame(height: 34)
            .background(alignment: .leading) {
                if it.state == .current {
                    ZStack(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.chip)
                        GeometryReader { g in
                            Rectangle().fill(Brand.hi).frame(width: g.size.width * CGFloat(it.progress), height: 3)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct LevelBars: View {
    let level: Float
    let active: Bool
    private let base: [CGFloat] = [6, 11, 16, 9, 14, 6, 3]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<7, id: \.self) { i in
                let k: CGFloat = active ? 0.3 + 0.7 * CGFloat(level) : 0.35
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Brand.hi.opacity(active ? 1 : 0.35))
                    .frame(width: 3, height: max(base[i] * k, 2))
            }
        }
        .frame(height: 18)
        .animation(.linear(duration: 0.08), value: level)
    }
}

private struct MicCard: View {
    @ObservedObject var engine: PlaybackEngine
    @ObservedObject var settings: SettingsStore
    @ObservedObject var ui: UIState

    private var info: (title: String, sub: String, color: Color, active: Bool) {
        if settings.pacing.mode == .fixed { return ("Без микрофона", "скорость задана вручную", Brand.tx2, false) }
        switch engine.voiceStatus {
        case .listening:
            return (engine.stats.isTracking ? "Слушаю вас" : "Слушаю", settings.pacing.primaryLocale, Brand.hi, true)
        case .starting: return ("Запуск…", "распознавание", Brand.tx2, false)
        case .unavailable(let m): return ("Запасной режим", m, Brand.warn, false)
        case .off: return ("Микрофон", "включится со «Старт»", Brand.tx2, false)
        }
    }

    var body: some View {
        let i = info
        return Button { ui.page = .speech } label: {
            HStack(spacing: 10) {
                Image(systemName: i.color == Brand.warn ? "mic.slash" : "mic").font(.system(size: 14, weight: .medium))
                    .foregroundColor(i.color).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(i.title).font(.system(size: 12, weight: .semibold)).foregroundColor(Brand.tx).lineLimit(1)
                    Text(i.sub).font(.system(size: 11)).foregroundColor(Brand.tx2).lineLimit(2)
                }
                Spacer(minLength: 4)
                LevelBars(level: engine.micLevel, active: i.active)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Brand.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Настройки распознавания и микрофона")
    }
}

// MARK: - Тулбар

private struct ToolbarRow: View {
    @ObservedObject var engine: PlaybackEngine
    @ObservedObject var settings: SettingsStore
    @ObservedObject var display: DisplayManager
    @ObservedObject var ui: UIState

    private var subtitle: String {
        switch ui.page {
        case .script:
            var s = plural(engine.document.wordCount, "слово", "слова", "слов") + " · " +
                plural(engine.document.sections.count, "раздел", "раздела", "разделов")
            if !engine.takes.isEmpty { s += " · " + plural(engine.takes.count, "дубль", "дубля", "дублей") }
            return s
        case .takes: return engine.takes.isEmpty ? "Пока пусто" : plural(engine.takes.count, "дубль", "дубля", "дублей") + " за сессию"
        case .appearance: return "Как выглядит текст на экране"
        case .output: return "Второй экран и зеркало"
        case .speech: return "Распознавание на устройстве"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ui.page.title).font(.system(size: 18, weight: .bold)).tracking(-0.2).foregroundColor(Brand.tx)
                Text(subtitle).font(.system(size: 12)).foregroundColor(Brand.tx2)
            }
            Spacer()
            if let t = engine.lastFinishedTake {
                HStack(spacing: 8) {
                    Button { ui.page = .takes } label: {
                        Text("Дубль \(t.number) · \(TimeEstimator.format(t.duration)) · разбор")
                    }
                    .buttonStyle(.plain)
                    Button { engine.lastFinishedTake = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                        .buttonStyle(.plain).help("Скрыть")
                }
                .brandPill(.soft)
            }
            TargetPill(settings: settings, engine: engine)
            OutputMenu(display: display, ui: ui)
        }
        .padding(.horizontal, 22)
        .frame(height: 64)
    }
}

private struct TargetPill: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var engine: PlaybackEngine
    @StateObject private var open = StateBox(false)
    @StateObject private var text = StateBox("")

    private var target: Double { settings.pacing.targetDuration }

    var body: some View {
        Button { open.value.toggle() } label: {
            HStack(spacing: 8) {
                if target > 0, let d = engine.stats.targetDelta, engine.stats.elapsed > 1, d <= 0 { HoloSeal(size: 18) }
                Text(label)
            }
            .brandPill(.line)
        }
        .buttonStyle(.plain)
        .help("Целевая длительность дубля")
        .popover(isPresented: $open.value, arrowEdge: .bottom) { editor }
    }

    private var label: String {
        guard target > 0 else { return "задать цель" }
        var s = "цель " + TimeEstimator.format(target)
        if let d = engine.stats.targetDelta, engine.stats.elapsed > 1 { s += " · " + TimeEstimator.formatDelta(d) }
        return s
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Целевая длительность дубля").font(.system(size: 13, weight: .bold))
            HStack(spacing: 8) {
                TextField("0:45", text: $text.value).textFieldStyle(.roundedBorder).frame(width: 84).onSubmit(commit)
                Button("Задать", action: commit)
            }
            HStack(spacing: 6) {
                ForEach([15, 30, 45, 60, 90], id: \.self) { sec in
                    Button { set(Double(sec)) } label: { Text(TimeEstimator.format(Double(sec))) }
                        .buttonStyle(.plain).brandPill(.soft, size: 12)
                }
            }
            Button("Без цели") { set(0) }
            Hint("Например 0:45 или 45 секунд. Приложение покажет, укладывается ли текущий темп.")
                .frame(width: 240)
        }
        .padding(16)
        .onAppear { text.value = target > 0 ? TimeEstimator.format(target) : "" }
    }

    private func set(_ seconds: Double) {
        settings.pacing.targetDuration = seconds
        open.value = false
    }

    private func commit() {
        let t = text.value.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { set(0); return }
        let parts = t.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2, let m = parts[0], let s = parts[1] { set(m * 60 + s) }
        else if parts.count == 1, let s = parts[0] { set(s) }
    }
}

private struct OutputMenu: View {
    @ObservedObject var display: DisplayManager
    @ObservedObject var ui: UIState

    private var label: String {
        switch display.placement {
        case .none: return "Вывод выключен"
        case .external(let n): return "Вывод · \(n)"
        case .windowed: return "Вывод · окно"
        }
    }

    var body: some View {
        // Меню системное, поэтому внешний вид рисуем сами, а меню кладём сверху прозрачным.
        HStack(spacing: 6) {
            Image(systemName: "display").font(.system(size: 12, weight: .semibold))
            Text(label)
        }
        .brandPill(.fill)
        .overlay(
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
                Button("Настройки вывода…") { ui.page = .output }
            } label: {
                Rectangle().fill(Color.white.opacity(0.001))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        )
        .help("Куда выводить текст для читающего")
    }
}

// MARK: - Страница сценария

private struct ScriptPage: View {
    @ObservedObject var engine: PlaybackEngine
    @ObservedObject var settings: SettingsStore
    @ObservedObject var script: ScriptModel
    @ObservedObject var ui: UIState
    var openFile: () -> Void
    var saveFile: () -> Void

    /// Строка исходного текста, на которой сейчас читающий.
    private var currentLine: Int? {
        let doc = engine.document
        guard !doc.words.isEmpty else { return nil }
        let idx = min(max(Int(engine.stats.position), 0), doc.words.count - 1)
        let loc = doc.words[idx].range.location
        let ns = doc.displayText as NSString
        var line = 0
        var i = 0
        let end = min(loc, ns.length)
        while i < end {
            if ns.character(at: i) == 10 { line += 1 }
            i += 1
        }
        return line
    }

    private var locked: Bool { engine.isPlaying && !ui.editUnlocked }

    var body: some View {
        HStack(spacing: 18) {
            editor
            preview.frame(width: 336)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
        .onChange(of: engine.isPlaying) { playing in if !playing { ui.editUnlocked = false } }
    }

    private var editor: some View {
        ZStack {
            ScriptEditorView(text: $script.text, editable: !locked, currentLine: currentLine, follow: engine.isPlaying)
                .opacity(locked ? 0.6 : 1)
            VStack {
                Spacer()
                LinearGradient(colors: [Brand.surface.opacity(0), Brand.surface], startPoint: .top, endPoint: .bottom)
                    .frame(height: 140)
            }
            .allowsHitTesting(false)
            VStack {
                if engine.isPlaying { banner }
                Spacer()
                HStack(spacing: 4) {
                    Spacer()
                    iconButton("folder", "Открыть .txt или .md (⌘O)", openFile)
                    iconButton("square.and.arrow.down", "Сохранить как… (⌘S)", saveFile)
                }
            }
            .padding(12)
        }
        .background(Brand.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Brand.line, lineWidth: 1))
    }

    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: ui.editUnlocked ? "pencil" : "lock.fill")
            Text(ui.editUnlocked ? "Правка на ходу: вывод обновляется сразу" : "Идёт дубль: текст защищён от случайной правки")
            Spacer()
            Button(ui.editUnlocked ? "Готово" : "Править") { ui.editUnlocked.toggle() }
        }
        .font(.system(size: 12))
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Brand.line, lineWidth: 1))
    }

    private func iconButton(_ name: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 13, weight: .medium)).foregroundColor(Brand.tx2)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Brand.surface2))
                .overlay(Circle().strokeBorder(Brand.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var preview: some View {
        ZStack(alignment: .topLeading) {
            PrompterPreview(engine: engine, theme: settings.theme)
            Text("КАК УВИДИТ ЧИТАЮЩИЙ")
                .font(.system(size: 10, weight: .bold)).tracking(1.4)
                .foregroundColor(settings.theme.colors.text.color.opacity(0.7))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(settings.theme.colors.background.color))
                .overlay(Capsule().strokeBorder(settings.theme.colors.text.color.opacity(0.14), lineWidth: 1))
                .padding(12)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Brand.line2, lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
        .help("Клик по слову переходит к нему, прокрутка трекпадом перематывает")
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

// MARK: - Капсула управления

private struct TransportCapsule: View {
    @ObservedObject var engine: PlaybackEngine
    @ObservedObject var settings: SettingsStore

    var body: some View {
        let s = engine.stats
        HStack(spacing: 16) {
            capButton("backward.end.fill", "В начало (Home)") { engine.rewind() }
            Button { engine.togglePlay() } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Brand.electric))
                    .shadow(color: Brand.electric.opacity(0.4), radius: 10, y: 6)
            }
            .buttonStyle(.plain)
            .help("Старт и пауза (пробел)")
            .accessibilityLabel(engine.isPlaying ? "Пауза" : "Старт")
            capButton("stop.fill", "Стоп: завершить дубль (⌘.)") { engine.stop() }
            Rectangle().fill(Brand.line2).frame(width: 1, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(TimeEstimator.format(s.secondsRemaining))
                    .font(.system(size: 28, weight: .heavy)).monospacedDigit().tracking(-0.5).foregroundColor(Brand.tx)
                Text("осталось").font(.system(size: 11)).foregroundColor(Brand.tx2)
            }
            .frame(minWidth: 66, alignment: .leading)
            pace(s)
            ModeSwitch(settings: settings)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Brand.line2, lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 22, y: 14)
    }

    private func capButton(_ name: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 14, weight: .semibold)).foregroundColor(Brand.tx)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    @ViewBuilder private func pace(_ s: PlaybackStats) -> some View {
        if engine.effectiveMode == .fixed {
            HStack(spacing: 8) {
                stepButton("minus") { engine.adjustSpeed(-10) }
                VStack(spacing: 1) {
                    Text("\(Int(settings.pacing.fixedWPM))").font(.system(size: 20, weight: .heavy)).monospacedDigit().foregroundColor(Brand.tx)
                    Text(settings.pacing.mode == .voice ? "запасной режим" : "сл/мин")
                        .font(.system(size: 11)).foregroundColor(Brand.tx2)
                }
                .frame(minWidth: 70)
                stepButton("plus") { engine.adjustSpeed(10) }
            }
        } else {
            HStack(spacing: 10) {
                ChevronMark().fill(Brand.hi).frame(width: 17, height: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Int(s.effectiveWPM.rounded()))").font(.system(size: 20, weight: .heavy)).monospacedDigit().foregroundColor(Brand.tx)
                    Text(s.measuredWPM == nil ? "сл/мин · ожидаемый" : "сл/мин · по голосу")
                        .font(.system(size: 11)).foregroundColor(Brand.tx2)
                }
            }
            .frame(minWidth: 118, alignment: .leading)
        }
    }

    private func stepButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 11, weight: .bold)).foregroundColor(Brand.tx)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Brand.surface2))
                .overlay(Circle().strokeBorder(Brand.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(name == "plus" ? "Быстрее (+)" : "Медленнее (−)")
    }
}

private struct ModeSwitch: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PacingMode.allCases) { m in
                let on = settings.pacing.mode == m
                Button { settings.pacing.mode = m } label: {
                    Text(m == .voice ? "Голос" : "Темп")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(on ? Brand.tx : Brand.tx2)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(on ? Brand.surface : .clear)
                            .shadow(color: .black.opacity(on ? 0.18 : 0), radius: 2, y: 1))
                }
                .buttonStyle(.plain)
                .help(m == .voice ? "Прокрутка идёт за голосом читающего" : "Прокрутка с фиксированной скоростью")
            }
        }
        .padding(3)
        .background(Capsule().fill(Brand.surface2))
        .overlay(Capsule().strokeBorder(Brand.line, lineWidth: 1))
    }
}
