import PrompterCore
import SwiftUI

// MARK: - Оформление

struct AppearancePage: View {
    @ObservedObject var settings: SettingsStore
    @StateObject private var nameBox = StateBox("")

    var body: some View {
        PageScroll {
            Panel("Цветовая схема") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 10)], spacing: 10) {
                    ForEach(settings.allSchemes) { s in
                        SchemeChip(scheme: s, selected: s.id == settings.theme.colors.id) { settings.theme.colors = s }
                    }
                }
                Divider().overlay(Brand.line)
                colorRow("Текст", \.text)
                colorRow("Фон", \.background)
                colorRow("Полоса текущей строки", \.highlight)
                colorRow("Прочитанный текст", \.readText)
                colorRow("Ремарки и разделы", \.remark)
                colorRow("Маркер линии чтения", \.marker)
                Divider().overlay(Brand.line)
                HStack(spacing: 10) {
                    TextField("Название своей схемы", text: $nameBox.value).textFieldStyle(.roundedBorder)
                    Button("Сохранить как свою") {
                        let n = nameBox.value.trimmingCharacters(in: .whitespaces)
                        settings.saveCurrentSchemeAsUser(named: n.isEmpty ? "Моя схема \(settings.userSchemes.count + 1)" : n)
                        nameBox.value = ""
                    }
                    if settings.userSchemes.contains(where: { $0.id == settings.theme.colors.id }) {
                        Button("Удалить", role: .destructive) {
                            settings.userSchemes.removeAll { $0.id == settings.theme.colors.id }
                            settings.theme.colors = .brandNavy
                        }
                    }
                }
            }

            Panel("Шрифт") {
                SettingRow("Шрифт") {
                    Picker("", selection: $settings.theme.fontFamily) {
                        ForEach(FontFamily.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 200)
                }
                SettingRow("Начертание") {
                    Picker("", selection: $settings.theme.fontWeight) {
                        ForEach(FontWeightOption.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 200)
                }
                SliderRow(title: "Размер", value: $settings.theme.fontSize, range: 20...160, format: "%.0f")
            }

            Panel("Раскладка") {
                SliderRow(title: "Межстрочный интервал", value: $settings.theme.lineSpacing, range: 0.9...2.2, format: "%.2f")
                SliderRow(title: "Между абзацами", value: $settings.theme.paragraphSpacing, range: 0...1.5, format: "%.2f")
                SliderRow(title: "Поля по бокам", value: $settings.theme.horizontalMargin, range: 0...0.35, format: "%.2f")
                SliderRow(title: "Линия чтения от верха", value: $settings.theme.readingLine, range: 0.15...0.65, format: "%.2f")
                Toggle("Выравнивать по центру", isOn: $settings.theme.centered)
                Toggle("Приглушать прочитанное", isOn: $settings.theme.dimReadText)
                Toggle("Подсвечивать текущую строку", isOn: $settings.theme.highlightCurrentLine)
            }
        }
    }

    private func colorRow(_ title: String, _ key: WritableKeyPath<PrompterColors, RGBAColor>) -> some View {
        SettingRow(title) {
            ColorPicker("", selection: RGBAColor.binding(Binding(
                get: { settings.theme.colors[keyPath: key] },
                set: { v in
                    var c = settings.theme.colors
                    c[keyPath: key] = v
                    // Любая правка готовой схемы превращает её в «свою».
                    if PrompterColors.presets.contains(where: { $0.id == c.id }) { c.id = "custom"; c.name = "Своя" }
                    settings.theme.colors = c
                })), supportsOpacity: true).labelsHidden()
        }
    }
}

private struct SchemeChip: View {
    let scheme: PrompterColors
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text("Аа").font(.system(size: 22, weight: .bold)).foregroundColor(scheme.text.color)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(scheme.background.color)
                    .overlay(alignment: .bottom) { Rectangle().fill(scheme.highlight.color).frame(height: 9) }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Brand.line2, lineWidth: 1))
                Text(scheme.name).font(.system(size: 11)).foregroundColor(Brand.tx).lineLimit(1)
            }
            .padding(5)
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(selected ? Brand.hi : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(scheme.name)
    }
}

// MARK: - Вывод

struct OutputPage: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var display: DisplayManager

    var body: some View {
        PageScroll {
            Panel("Экран") {
                if display.externalScreens.isEmpty {
                    Hint("Внешний экран не найден. Подключите монитор по HDMI: вывод откроется на нём сам.")
                } else {
                    SettingRow("Показывать на") {
                        Picker("", selection: Binding(
                            get: { settings.output.preferredScreenName ?? display.externalScreens.first ?? "" },
                            set: { display.showOnExternal(named: $0) })) {
                            ForEach(display.externalScreens, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().frame(width: 220)
                    }
                }
                HStack(spacing: 10) {
                    Button("Открыть на внешнем") { display.showOnExternal() }.disabled(display.externalScreens.isEmpty)
                    Button("Открыть в окне для проверки") { display.showWindowed() }
                    Button("Закрыть вывод") { display.userClosed() }
                }
            }
            Panel("Зеркало") {
                Toggle("Зеркалить по горизонтали (для стеклянной насадки)", isOn: $settings.output.mirrorHorizontal)
                Toggle("Перевернуть по вертикали", isOn: $settings.output.mirrorVertical)
                Hint("Зеркалится только второй экран. Окно оператора всегда в нормальной ориентации.")
            }
            Panel("Текст на втором экране") {
                SliderRow(title: "Масштаб шрифта", value: $settings.output.fontScale, range: 0.5...2.0, format: "×%.2f")
                Toggle("Таймер «осталось» и отклонение от цели", isOn: $settings.output.showTimer)
                Toggle("Полоса прогресса", isOn: $settings.output.showProgress)
                Toggle("Маркер линии чтения", isOn: $settings.output.showReadingMarker)
                Toggle("Плашка «раздел заканчивается»", isOn: $settings.output.showSectionAlert)
            }
        }
    }
}

// MARK: - Речь и темп

struct SpeechPage: View {
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
        PageScroll {
            Panel("Режим") {
                Picker("", selection: $settings.pacing.mode) {
                    ForEach(PacingMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 300)
                Hint("Голос нужен только чтобы понять, какое место сценария сейчас читают. Голосовых команд нет: слова в разговоре не остановят и не перемотают текст.")
            }
            Panel("Распознавание на устройстве") {
                SettingRow("Язык речи") {
                    Picker("", selection: $settings.pacing.primaryLocale) {
                        ForEach(Self.locales, id: \.0) { Text($0.1).tag($0.0) }
                    }.labelsHidden().frame(width: 200)
                }
                Hint("Иностранные слова из сценария распознаются по подсказкам модели и сравнению по звучанию: «пармезан» и parmesan считаются одним словом. Язык должен быть добавлен в «Системные настройки → Клавиатура → Диктовка».")
            }
            Panel("Микрофон читающего") {
                SettingRow("Устройство") {
                    Picker("", selection: Binding(
                        get: { settings.pacing.inputDeviceUID ?? "" },
                        set: { settings.pacing.inputDeviceUID = $0.isEmpty ? nil : $0; settings.pacing.inputChannel = 0 })) {
                        Text("Системный по умолчанию").tag("")
                        ForEach(devices) { Text("\($0.name) (\($0.channels) кан.)").tag($0.uid) }
                    }.labelsHidden().frame(width: 260)
                }
                if let dev = devices.first(where: { $0.uid == settings.pacing.inputDeviceUID }), dev.channels > 1 {
                    SettingRow("Канал") {
                        Picker("", selection: $settings.pacing.inputChannel) {
                            Text("Все каналы вместе").tag(0)
                            ForEach(1...dev.channels, id: \.self) { Text("Только канал \($0)").tag($0) }
                        }.labelsHidden().frame(width: 260)
                    }
                }
                Hint("Если у каждого свой микрофон, выберите микрофон или канал читающего: реплики собеседника почти не попадут в распознавание. Без этого реплики не из сценария и так игнорируются.")
                Button("Применить сейчас") { engine.restartSpeechIfNeeded() }.disabled(!engine.isPlaying)
            }
            Panel("Темп") {
                SettingRow("Ожидаемый до замера") {
                    Stepper("\(Int(settings.pacing.baseWPM)) сл/мин", value: $settings.pacing.baseWPM, in: 60...250, step: 5)
                }
                SettingRow("Фиксированная и запасная") {
                    Stepper("\(Int(settings.pacing.fixedWPM)) сл/мин", value: $settings.pacing.fixedWPM, in: 40...300, step: 10)
                }
            }
        }
        .onAppear { devicesBox.value = AudioDevices.inputs() }
    }
}
