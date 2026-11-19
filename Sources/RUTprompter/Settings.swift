import AppKit
import SwiftUI

struct RGBAColor: Codable, Equatable, Hashable {
    var r: Double, g: Double, b: Double, a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ ns: NSColor) {
        let c = ns.usingColorSpace(.sRGB) ?? NSColor.white
        self.init(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    }

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var color: Color { Color(nsColor: nsColor) }

    /// Привязка для SwiftUI ColorPicker.
    static func binding(_ base: Binding<RGBAColor>) -> Binding<Color> {
        Binding(get: { base.wrappedValue.color },
                set: { base.wrappedValue = RGBAColor(NSColor($0)) })
    }
}

/// Цветовая схема («выключка») — полностью настраиваемая.
struct PrompterColors: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var text: RGBAColor
    var background: RGBAColor
    /// Полоса текущей строки.
    var highlight: RGBAColor
    /// Уже прочитанный текст.
    var readText: RGBAColor
    /// Ремарки, метки говорящих, заголовки разделов.
    var remark: RGBAColor
    /// Маркер линии чтения.
    var marker: RGBAColor

    /// Фирменная: тёмно-синий фон, голубые акценты (по умолчанию).
    static let brandNavy = PrompterColors(
        id: "brand-navy", name: "Фирменная тёмная",
        text: RGBAColor(1, 1, 1), background: RGBAColor(0.027, 0.078, 0.169),
        highlight: RGBAColor(0.498, 0.89, 1, 0.14), readText: RGBAColor(1, 1, 1, 0.34),
        remark: RGBAColor(0.498, 0.89, 1), marker: RGBAColor(0.498, 0.89, 1))
    /// Фирменная светлая: белый фон, синий 005CC9.
    static let brandLight = PrompterColors(
        id: "brand-light", name: "Фирменная светлая",
        text: RGBAColor(0.043, 0.165, 0.361), background: RGBAColor(1, 1, 1),
        highlight: RGBAColor(0, 0.361, 0.788, 0.09), readText: RGBAColor(0.043, 0.165, 0.361, 0.26),
        remark: RGBAColor(0, 0.361, 0.788), marker: RGBAColor(0, 0.4, 1))
    static let whiteOnBlack = PrompterColors(
        id: "white-black", name: "Белый на чёрном",
        text: RGBAColor(1, 1, 1), background: RGBAColor(0, 0, 0),
        highlight: RGBAColor(1, 1, 1, 0.12), readText: RGBAColor(0.45, 0.45, 0.45),
        remark: RGBAColor(0.35, 0.75, 1), marker: RGBAColor(1, 0.25, 0.25))
    static let yellowOnBlack = PrompterColors(
        id: "yellow-black", name: "Жёлтый на чёрном",
        text: RGBAColor(1, 0.86, 0.1), background: RGBAColor(0, 0, 0),
        highlight: RGBAColor(1, 0.86, 0.1, 0.14), readText: RGBAColor(0.5, 0.43, 0.1),
        remark: RGBAColor(0.6, 0.8, 1), marker: RGBAColor(1, 0.3, 0.2))
    static let blackOnWhite = PrompterColors(
        id: "black-white", name: "Чёрный на белом",
        text: RGBAColor(0, 0, 0), background: RGBAColor(1, 1, 1),
        highlight: RGBAColor(1, 0.85, 0, 0.3), readText: RGBAColor(0.6, 0.6, 0.6),
        remark: RGBAColor(0.1, 0.4, 0.8), marker: RGBAColor(0.9, 0.1, 0.1))
    static let greenOnBlack = PrompterColors(
        id: "green-black", name: "Зелёный на чёрном",
        text: RGBAColor(0.35, 1, 0.5), background: RGBAColor(0, 0, 0),
        highlight: RGBAColor(0.35, 1, 0.5, 0.12), readText: RGBAColor(0.15, 0.45, 0.2),
        remark: RGBAColor(1, 0.8, 0.3), marker: RGBAColor(1, 0.3, 0.3))
    static let presets = [brandNavy, brandLight, whiteOnBlack, yellowOnBlack, blackOnWhite, greenOnBlack]
}

enum FontFamily: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif, helvetica, avenir, ptSans, mono
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Системный"
        case .rounded: return "Округлый"
        case .serif: return "Georgia"
        case .helvetica: return "Helvetica Neue"
        case .avenir: return "Avenir Next"
        case .ptSans: return "PT Sans"
        case .mono: return "Моноширинный"
        }
    }

    func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        func named(_ family: String) -> NSFont? {
            let traits: NSFontTraitMask = weight.rawValue >= NSFont.Weight.semibold.rawValue ? .boldFontMask : []
            let nsWeight = weight.rawValue >= NSFont.Weight.bold.rawValue ? 9 : weight.rawValue >= NSFont.Weight.semibold.rawValue ? 8 : weight.rawValue >= NSFont.Weight.medium.rawValue ? 6 : 5
            return NSFontManager.shared.font(withFamily: family, traits: traits, weight: nsWeight, size: size)
        }
        switch self {
        case .system: return .systemFont(ofSize: size, weight: weight)
        case .rounded:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            if let d = base.fontDescriptor.withDesign(.rounded) { return NSFont(descriptor: d, size: size) ?? base }
            return base
        case .serif: return named("Georgia") ?? .systemFont(ofSize: size, weight: weight)
        case .helvetica: return named("Helvetica Neue") ?? .systemFont(ofSize: size, weight: weight)
        case .avenir: return named("Avenir Next") ?? .systemFont(ofSize: size, weight: weight)
        case .ptSans: return named("PT Sans") ?? .systemFont(ofSize: size, weight: weight)
        case .mono: return .monospacedSystemFont(ofSize: size, weight: weight)
        }
    }
}

enum FontWeightOption: String, Codable, CaseIterable, Identifiable {
    case regular, medium, semibold, bold
    var id: String { rawValue }
    var title: String {
        switch self {
        case .regular: return "Обычный"
        case .medium: return "Средний"
        case .semibold: return "Полужирный"
        case .bold: return "Жирный"
        }
    }
    var nsWeight: NSFont.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

/// Оформление текста суфлёра.
struct PrompterTheme: Codable, Equatable {
    var colors: PrompterColors = .brandNavy
    var fontFamily: FontFamily = .system
    var fontWeight: FontWeightOption = .semibold
    /// Размер шрифта в пунктах на каждые 1000 пикселей ширины экрана —
    /// так текст адаптивно масштабируется под любой экран и превью.
    var fontSize: Double = 64
    /// Межстрочный интервал (множитель).
    var lineSpacing: Double = 1.25
    /// Отступ между абзацами, доля высоты строки.
    var paragraphSpacing: Double = 0.4
    /// Боковые поля, доля ширины.
    var horizontalMargin: Double = 0.08
    var centered: Bool = false
    /// Линия чтения — доля высоты экрана сверху.
    var readingLine: Double = 0.35
    var dimReadText: Bool = true
    var highlightCurrentLine: Bool = true
}

/// Настройки конкретного экрана вывода (не влияют на окно оператора).
struct OutputSettings: Codable, Equatable {
    var mirrorHorizontal = false
    var mirrorVertical = false
    /// Множитель к размеру шрифта темы — только для этого экрана.
    var fontScale: Double = 1.0
    var showTimer = true
    var showProgress = true
    var showReadingMarker = true
    var showSectionAlert = true
    var hideControls = true
    /// Имя предпочитаемого экрана (если внешних несколько).
    var preferredScreenName: String?
}

enum PacingMode: String, Codable, CaseIterable, Identifiable {
    case voice, fixed
    var id: String { rawValue }
    var title: String { self == .voice ? "По голосу" : "Фикс. скорость" }
}

struct PacingSettings: Codable, Equatable {
    var mode: PacingMode = .voice
    /// Скорость для фиксированного режима и запасного режима, слов/мин.
    var fixedWPM: Double = 130
    /// Темп «по умолчанию» для ETA, пока реальный ещё не измерен.
    var baseWPM: Double = 130
    var primaryLocale = "ru-RU"
    /// Не используется: две on-device модели одновременно мешают друг
    /// другу. Поле оставлено для совместимости сохранённых настроек.
    var secondaryLocale: String? = nil
    var inputDeviceUID: String?
    /// 0 — смешать все каналы, 1...n — взять только этот канал
    /// (когда у читающего свой микрофон на многоканальной карте).
    var inputChannel: Int = 0
    /// Целевая длительность дубля, сек. 0 — не задана.
    var targetDuration: Double = 0
}

/// Хранилище настроек в UserDefaults (JSON).
final class SettingsStore: ObservableObject {
    @Published var theme: PrompterTheme { didSet { save(theme, "theme.v2") } }
    @Published var output: OutputSettings { didSet { save(output, "output") } }
    @Published var pacing: PacingSettings { didSet { save(pacing, "pacing") } }
    @Published var userSchemes: [PrompterColors] { didSet { save(userSchemes, "userSchemes") } }

    private let defaults = UserDefaults.standard

    init() {
        func load<T: Decodable>(_ key: String) -> T? {
            guard let data = UserDefaults.standard.data(forKey: "rut." + key) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        theme = load("theme.v2") ?? PrompterTheme()
        output = load("output") ?? OutputSettings()
        pacing = load("pacing") ?? PacingSettings()
        userSchemes = load("userSchemes") ?? []
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "rut." + key) }
    }

    var allSchemes: [PrompterColors] { PrompterColors.presets + userSchemes }

    func saveCurrentSchemeAsUser(named name: String) {
        var s = theme.colors
        s.id = "user-" + UUID().uuidString
        s.name = name
        userSchemes.append(s)
        theme.colors = s
    }
}

/// Автосохранение текущего скрипта.
enum ScriptStorage {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RUTprompter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("script.txt")
    }

    static func load() -> String? { try? String(contentsOf: url, encoding: .utf8) }
    static func save(_ text: String) { try? text.write(to: url, atomically: true, encoding: .utf8) }

    static let sample = """
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

/// Замена `@State`: в Command Line Tools нет плагина макросов SwiftUI,
/// поэтому локальное состояние вьюх держим в `@StateObject`.
final class StateBox<T>: ObservableObject {
    @Published var value: T
    init(_ value: T) { self.value = value }
}
