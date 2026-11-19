import AppKit
import SwiftUI

/// Фирменный слой: цвета, шеврон, плашки, значок-печать.
/// Основной цвет 005CC9 и его оттенки; яркий синий, тёмно-синий и голубой
/// взяты из листа компонентов. Светлая и тёмная темы следуют системе.
enum Brand {

    // MARK: Цвета

    static func rgb(_ v: UInt32, _ a: Double = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: CGFloat(a))
    }

    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    /// Те же токены для AppKit (NSTextView).
    enum NS {
        static let bg = dynamic(light: rgb(0xEDF1F8), dark: rgb(0x091325))
        static let surface = dynamic(light: rgb(0xFFFFFF), dark: rgb(0x101D38))
        static let surface2 = dynamic(light: rgb(0xF0F4FB), dark: rgb(0x16264A))
        static let line = dynamic(light: rgb(0x0A285A, 0.10), dark: rgb(0xFFFFFF, 0.09))
        static let line2 = dynamic(light: rgb(0x0A285A, 0.20), dark: rgb(0xFFFFFF, 0.20))
        static let tx = dynamic(light: rgb(0x0B1B33), dark: rgb(0xF1F6FF))
        static let tx2 = dynamic(light: rgb(0x566783), dark: rgb(0x9DAECB))
        static let tx3 = dynamic(light: rgb(0x8D9BB5), dark: rgb(0x6E81A6))
        /// Заливки (кнопки, выбранный пункт).
        static let accent = dynamic(light: rgb(0x005CC9), dark: rgb(0x0A64DC))
        /// Текст и тонкие линии акцентного цвета.
        static let accentTx = dynamic(light: rgb(0x005CC9), dark: rgb(0x82BAFF))
        static let hi = dynamic(light: rgb(0x0066FF), dark: rgb(0x2B7BFF))
        static let chip = dynamic(light: rgb(0xE3EDFB), dark: rgb(0x182A52))
    }

    static let bg = Color(nsColor: NS.bg)
    static let surface = Color(nsColor: NS.surface)
    static let surface2 = Color(nsColor: NS.surface2)
    static let line = Color(nsColor: NS.line)
    static let line2 = Color(nsColor: NS.line2)
    static let tx = Color(nsColor: NS.tx)
    static let tx2 = Color(nsColor: NS.tx2)
    static let tx3 = Color(nsColor: NS.tx3)
    static let accent = Color(nsColor: NS.accent)
    static let accentTx = Color(nsColor: NS.accentTx)
    static let hi = Color(nsColor: NS.hi)
    static let chip = Color(nsColor: NS.chip)

    /// Не зависят от темы.
    static let electric = Color(nsColor: rgb(0x0066FF))
    static let brandBlue = Color(nsColor: rgb(0x005CC9))
    static let navy = Color(nsColor: rgb(0x123A8C))
    static let cyan = Color(nsColor: rgb(0x7FE3FF))
    static let warn = Color(nsColor: rgb(0xFF9F0A))
}

// MARK: - Шеврон

/// Знак из трёх шевронов. Геометрия снята с присланного листа компонентов
/// (viewBox 592×622); при получении оригинального SVG заменить точки.
struct ChevronMark: Shape {
    private static let polys: [[(CGFloat, CGFloat)]] = [
        [(0, 0), (95, 0), (192, 310), (97, 310)],
        [(160, 0), (255, 0), (352, 310), (257, 310)],
        [(320, 0), (415, 0), (512, 310), (417, 310)],
        [(175, 312), (269, 312), (179, 622), (82, 622)],
        [(334, 312), (428, 312), (338, 622), (241, 622)],
        [(493, 312), (587, 312), (497, 622), (400, 622)]
    ]

    func path(in rect: CGRect) -> Path {
        let w: CGFloat = 592, h: CGFloat = 622
        let s = min(rect.width / w, rect.height / h)
        let ox = rect.minX + (rect.width - w * s) / 2
        let oy = rect.minY + (rect.height - h * s) / 2
        var p = Path()
        for poly in Self.polys {
            for (i, q) in poly.enumerated() {
                let pt = CGPoint(x: ox + q.0 * s, y: oy + q.1 * s)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
        return p
    }
}

// MARK: - Значок-печать

struct SealShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let R = min(rect.width, rect.height)
        var p = Path()
        let n = 120
        for k in 0...n {
            let t = 2 * Double.pi * Double(k) / Double(n)
            let r = R * (0.44 + 0.06 * cos(12 * t))
            let pt = CGPoint(x: c.x + CGFloat(r * cos(t)), y: c.y + CGFloat(r * sin(t)))
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Голографическая печать — «дубль укладывается в цель».
struct HoloSeal: View {
    var size: CGFloat = 30
    var body: some View {
        SealShape()
            .fill(AngularGradient(colors: [Color(nsColor: Brand.rgb(0xBFF3EE)), Color(nsColor: Brand.rgb(0xE6C8F6)),
                                           Color(nsColor: Brand.rgb(0xFFF3B5)), Color(nsColor: Brand.rgb(0xB6EAD8)),
                                           Color(nsColor: Brand.rgb(0xC9D4FF)), Color(nsColor: Brand.rgb(0xBFF3EE))],
                                  center: .center, angle: .degrees(210)))
            .overlay(Image(systemName: "checkmark").font(.system(size: size * 0.36, weight: .bold))
                .foregroundColor(Color(nsColor: Brand.rgb(0x10213F))))
            .frame(width: size, height: size)
    }
}

// MARK: - Плашки

enum PillKind { case fill, line, soft }

struct BrandPill: ViewModifier {
    let kind: PillKind
    var size: CGFloat = 13

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .bold))
            .lineLimit(1)
            .padding(.horizontal, size + 1)
            .padding(.vertical, size * 0.5)
            .foregroundColor(kind == .fill ? .white : Brand.accentTx)
            .background(Capsule().fill(kind == .fill ? Brand.electric : (kind == .soft ? Brand.chip : .clear)))
            .overlay(Capsule().strokeBorder(Brand.hi, lineWidth: kind == .line ? 2 : 0))
    }
}

extension View {
    func brandPill(_ kind: PillKind, size: CGFloat = 13) -> some View { modifier(BrandPill(kind: kind, size: size)) }
}

/// Иконка-плитка бренда.
struct BrandTile: View {
    var size: CGFloat = 32
    var body: some View {
        Group {
            if let img = BrandAssets.tileBlue {
                Image(nsImage: img).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.3).fill(Brand.electric)
                    .overlay(ChevronMark().fill(Color.white).padding(size * 0.25))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

// MARK: - Вспомогательное

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

/// Карточка настроек: заголовок капсом и содержимое на светлой поверхности.
struct Panel<Content: View>: View {
    let title: String?
    let content: Content
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold)).tracking(1.1)
                    .foregroundColor(Brand.tx2)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Brand.line, lineWidth: 1))
    }
}

/// Прокручиваемая страница с нижним отступом под плавающую капсулу.
struct PageScroll<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 4)
                .padding(.bottom, 110)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(Brand.accent)
    }
}

/// Строка «название — элемент управления».
struct SettingRow<Control: View>: View {
    let title: String
    let control: Control
    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }
    var body: some View {
        HStack(spacing: 12) {
            Text(title).foregroundColor(Brand.tx)
            Spacer(minLength: 12)
            control
        }
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var body: some View {
        HStack(spacing: 12) {
            Text(title).foregroundColor(Brand.tx).frame(width: 170, alignment: .leading)
            Slider(value: $value, in: range).tint(Brand.accent)
            Text(String(format: format, value))
                .monospacedDigit().foregroundColor(Brand.tx2).frame(width: 48, alignment: .trailing)
        }
    }
}

struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 12)).foregroundColor(Brand.tx2).fixedSize(horizontal: false, vertical: true)
    }
}
