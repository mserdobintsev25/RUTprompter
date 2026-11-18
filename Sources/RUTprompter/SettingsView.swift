import PrompterCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var engine: PlaybackEngine
    @ObservedObject var display: DisplayManager
    var close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                AppearanceTab(settings: settings).tabItem { Text("Оформление") }
                OutputTab(settings: settings, display: display).tabItem { Text("Второй экран") }
                SpeechTab(settings: settings, engine: engine).tabItem { Text("Речь и темп") }
            }
            .padding(12)
            Divider()
            HStack {
                Spacer()
                Button("Готово", action: close).keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 640, height: 600)
    }
}

// MARK: - Оформление

private struct AppearanceTab: View {
    @ObservedObject var settings: SettingsStore
    @StateObject private var nameBox = StateBox("")

    var body: some View {
        Form {
            Section("Цветовая схема") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 8) {
                    ForEach(settings.allSchemes) { s in
                        SchemeChip(scheme: s, selected: s.id == settings.theme.colors.id) {
                            settings.theme.colors = s
                        }
                    }
                }
                colorRow("Текст", \.text)
                colorRow("Фон", \.background)
                colorRow("Полоса текущей строки", \.highlight)
                colorRow("Прочитанный текст", \.readText)
                colorRow("Ремарки и разделы", \.remark)
                colorRow("Маркер линии чтения", \.marker)
                HStack {
                    TextField("Название своей схемы", text: $nameBox.value)
                    Button("Сохранить как свою") {
                        let n = nameBox.value.trimmingCharacters(in: .whitespaces)
                        settings.saveCurrentSchemeAsUser(named: n.isEmpty ? "Моя схема \(settings.userSchemes.count + 1)" : n)
                        nameBox.value = ""
                    }
                    if settings.userSchemes.contains(where: { $0.id == settings.theme.colors.id }) {
                        Button("Удалить", role: .destructive) {
                            settings.userSchemes.removeAll { $0.id == settings.theme.colors.id }
                            settings.theme.colors = .whiteOnBlack
                        }
                    }
                }
            }

            Section("Шрифт и раскладка") {
                Picker("Шрифт", selection: $settings.theme.fontFamily) {
                    ForEach(FontFamily.allCases) { Text($0.title).tag($0) }
                }
                Picker("Начертание", selection: $settings.theme.fontWeight) {
                    ForEach(FontWeightOption.allCases) { Text($0.title).tag($0) }
                }
                slider("Размер", $settings.theme.fontSize, 20...160, "%.0f")
                slider("Межстрочный", $settings.theme.lineSpacing, 0.9...2.2, "%.2f")
                slider("Между абзацами", $settings.theme.paragraphSpacing, 0...1.5, "%.2f")
                slider("Поля по бокам", $settings.theme.horizontalMargin, 0...0.35, "%.2f")
                slider("Линия чтения (от верха)", $settings.theme.readingLine, 0.15...0.65, "%.2f")
                Toggle("По центру", isOn: $settings.theme.centered)
                Toggle("Приглушать прочитанное", isOn: $settings.theme.dimReadText)
                Toggle("Подсвечивать текущую строку", isOn: $settings.theme.highlightCurrentLine)
            }
        }
        .formStyle(.grouped)
    }

    private func colorRow(_ title: String, _ key: WritableKeyPath<PrompterColors, RGBAColor>) -> some View {
        ColorPicker(title, selection: RGBAColor.binding(Binding(
            get: { settings.theme.colors[keyPath: key] },
            set: { v in
                var c = settings.theme.colors
                c[keyPath: key] = v
                // Любая правка готового пресета превращает его в «свою».
                if ColorScheme_isPreset(c.id) { c.id = "custom"; c.name = "Своя" }
                settings.theme.colors = c
            })), supportsOpacity: true)
    }

    private func ColorScheme_isPreset(_ id: String) -> Bool { PrompterColors.presets.contains { $0.id == id } }

    private func slider(_ title: String, _ v: Binding<Double>, _ r: ClosedRange<Double>, _ fmt: String) -> some View {
        HStack {
            Text(title)
            Slider(value: v, in: r)
            Text(String(format: fmt, v.wrappedValue)).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }
}

private struct SchemeChip: View {
    let scheme: PrompterColors
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("Аа").font(.title2.weight(.bold)).foregroundStyle(scheme.text.color)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(scheme.background.color)
                    .overlay(alignment: .bottom) { Rectangle().fill(scheme.highlight.color).frame(height: 8) }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(scheme.name).font(.caption).lineLimit(1)
            }
            .padding(4)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Второй экран

private struct OutputTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var display: DisplayManager

    var body: some View {
        Form {
            Section {
                Toggle("Зеркалить по горизонтали (для стеклянной насадки)", isOn: $settings.output.mirrorHorizontal)
                Toggle("Перевернуть по вертикали", isOn: $settings.output.mirrorVertical)
                Text("Зеркалится только второй экран — окно оператора всегда в нормальной ориентации.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Текст на этом экране") {
                HStack {
                    Text("Масштаб шрифта")
                    Slider(value: $settings.output.fontScale, in: 0.5...2.0)
                    Text(String(format: "×%.2f", settings.output.fontScale)).monospacedDigit().frame(width: 50)
                }
                Toggle("Таймер «осталось» и цель", isOn: $settings.output.showTimer)
                Toggle("Полоса прогресса", isOn: $settings.output.showProgress)
                Toggle("Маркер линии чтения", isOn: $settings.output.showReadingMarker)
                Toggle("Плашка «раздел заканчивается»", isOn: $settings.output.showSectionAlert)
            }
            Section("Экран") {
                if display.externalScreens.isEmpty {
                    Text("Внешний экран не найден. Подключите монитор по HDMI — вывод откроется на нём автоматически.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Показывать на", selection: Binding(
                        get: { settings.output.preferredScreenName ?? display.externalScreens.first ?? "" },
                        set: { display.showOnExternal(named: $0) })) {
                        ForEach(display.externalScreens, id: \.self) { Text($0).tag($0) }
                    }
                }
                HStack {
                    Button("Открыть на внешнем") { display.showOnExternal() }
                        .disabled(display.externalScreens.isEmpty)
                    Button("Открыть в окне (проверка)") { display.showWindowed() }
                    Button("Закрыть вывод") { display.userClosed() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Речь

private struct SpeechTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var engine: PlaybackEngine
    @StateObject private var devicesBox = StateBox<[AudioInputDevice]>([])
    private var devices: [AudioInputDevice] { devicesBox.value }

    private static let locales: [(String, String)] = [
        ("ru-RU", "Русский"), ("en-US", "English (US)"), ("en-GB", "English (UK)"),
        ("uk-UA", "Українська"), ("de-DE", "Deutsch"), ("fr-FR", "Français"),
        ("es-ES", "Español"), ("it-IT", "Italiano")
    ]

    var body: some View {
        Form {
            Section {
                Picker("Режим", selection: $settings.pacing.mode) {
                    ForEach(PacingMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Голос используется только чтобы понять, какое место скрипта сейчас читают. Голосовых команд нет и не будет — фразы в разговоре не остановят и не перемотают текст.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Распознавание (только на устройстве)") {
                Picker("Основной язык", selection: $settings.pacing.primaryLocale) {
                    ForEach(Self.locales, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("Второй язык параллельно", selection: Binding(
                    get: { settings.pacing.secondaryLocale ?? "" },
                    set: { settings.pacing.secondaryLocale = $0.isEmpty ? nil : $0 })) {
                    Text("Нет").tag("")
                    ForEach(Self.locales, id: \.0) { Text($0.1).tag($0.0) }
                }
                Text("Вторая модель помогает с иностранными словами и терминами. Если язык не установлен для офлайн-диктовки, он будет пропущен (Системные настройки → Клавиатура → Диктовка).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Микрофон читающего") {
                Picker("Устройство", selection: Binding(
                    get: { settings.pacing.inputDeviceUID ?? "" },
                    set: { settings.pacing.inputDeviceUID = $0.isEmpty ? nil : $0; settings.pacing.inputChannel = 0 })) {
                    Text("Системный по умолчанию").tag("")
                    ForEach(devices) { Text("\($0.name) (\($0.channels) кан.)").tag($0.uid) }
                }
                if let dev = devices.first(where: { $0.uid == settings.pacing.inputDeviceUID }), dev.channels > 1 {
                    Picker("Канал", selection: $settings.pacing.inputChannel) {
                        Text("Все каналы вместе").tag(0)
                        ForEach(1...dev.channels, id: \.self) { Text("Только канал \($0)").tag($0) }
                    }
                }
                Text("Если у каждого свой микрофон (петличка), выберите микрофон или канал читающего — так реплики собеседника почти не попадут в распознавание. Без этого реплики не из скрипта и так игнорируются.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Применить сейчас") { engine.restartSpeechIfNeeded() }
                    .disabled(!engine.isPlaying)
            }
            Section("Темп") {
                Stepper(value: $settings.pacing.baseWPM, in: 60...250, step: 5) {
                    Text("Ожидаемый темп до замера: \(Int(settings.pacing.baseWPM)) сл/мин")
                }
                Stepper(value: $settings.pacing.fixedWPM, in: 40...300, step: 10) {
                    Text("Фиксированная / запасная скорость: \(Int(settings.pacing.fixedWPM)) сл/мин")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { devicesBox.value = AudioDevices.inputs() }
    }
}
