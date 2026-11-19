import AppKit
import SwiftUI

/// NSTextView, который рисует полосу текущей строки на всю ширину.
final class ScriptTextView: NSTextView {
    var currentRange: NSRange? {
        didSet { if oldValue != currentRange { needsDisplay = true } }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let r = currentRange, let lm = layoutManager, let tc = textContainer,
              r.location <= (string as NSString).length else { return }
        let glyphs = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
        var box = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        box.origin.x = 0
        box.size.width = bounds.width
        box.origin.y += textContainerOrigin.y
        box = box.insetBy(dx: 0, dy: -2)
        let hi = Brand.NS.hi
        NSGradient(starting: hi.withAlphaComponent(0.14), ending: hi.withAlphaComponent(0))?.draw(in: box, angle: 0)
        hi.setFill()
        NSRect(x: 0, y: box.minY, width: 3, height: box.height).fill()
    }
}

/// Редактор сценария: подсвечивает «# разделы», «МЕТКИ:» говорящих и «[ремарки]».
struct ScriptEditorView: NSViewRepresentable {
    @Binding var text: String
    var editable: Bool
    /// Номер строки исходного текста, на которой сейчас читающий.
    var currentLine: Int?
    /// Прокручивать за читающим (во время дубля).
    var follow: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder

        let tv = ScriptTextView(frame: .zero)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 28, height: 24)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.insertionPointColor = Brand.NS.hi
        tv.font = Coordinator.baseFont
        tv.textColor = Brand.NS.tx
        tv.string = text
        scroll.documentView = tv

        context.coordinator.textView = tv
        context.coordinator.restyle()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let tv = c.textView else { return }
        if tv.string != text {
            tv.string = text
            c.restyle()
        }
        if tv.isEditable != editable { tv.isEditable = editable }
        c.applyCurrent(line: currentLine, follow: follow)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScriptEditorView
        weak var textView: ScriptTextView?
        private var lastLine: Int?

        static let baseFont = NSFont.systemFont(ofSize: 15)

        init(_ parent: ScriptEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            restyle()
        }

        /// Диапазон строки (с номером) в исходном тексте.
        private func range(ofLine line: Int, in ns: NSString) -> NSRange? {
            var idx = 0
            var found: NSRange?
            ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, r, _, stop in
                if idx == line { found = r; stop.pointee = true }
                idx += 1
            }
            if found == nil, line == idx, ns.length == 0 || line == idx { return NSRange(location: ns.length, length: 0) }
            return found
        }

        func applyCurrent(line: Int?, follow: Bool) {
            guard let tv = textView else { return }
            guard let line else {
                tv.currentRange = nil
                lastLine = nil
                return
            }
            let ns = tv.string as NSString
            guard let r = range(ofLine: line, in: ns) else { return }
            tv.currentRange = r
            if follow, line != lastLine { tv.scrollRangeToVisible(NSRange(location: r.location, length: max(r.length, 1))) }
            lastLine = line
        }

        func restyle() {
            guard let tv = textView, let ts = tv.textStorage else { return }
            let full = NSRange(location: 0, length: ts.length)
            let para = NSMutableParagraphStyle()
            para.lineHeightMultiple = 1.22
            para.paragraphSpacing = 2

            let hdr = NSFont.systemFont(ofSize: 12, weight: .bold)
            let label = NSFont.systemFont(ofSize: 11, weight: .bold)
            let italic = NSFontManager.shared.convert(Self.baseFont, toHaveTrait: .italicFontMask)
            let ns = ts.string as NSString

            ts.beginEditing()
            ts.setAttributes([.font: Self.baseFont, .foregroundColor: Brand.NS.tx, .paragraphStyle: para], range: full)
            ns.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, r, _, _ in
                let line = ns.substring(with: r)
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") {
                    ts.addAttributes([.font: hdr, .foregroundColor: Brand.NS.accentTx, .kern: 1.1], range: r)
                    let hashes = line.prefix { $0 == "#" || $0 == " " }.count
                    ts.addAttribute(.foregroundColor, value: Brand.NS.tx3, range: NSRange(location: r.location, length: min(hashes, r.length)))
                    return
                }
                if let colon = line.firstIndex(of: ":") {
                    let lab = line[..<colon].trimmingCharacters(in: .whitespaces)
                    let letters = lab.filter { $0.isLetter }
                    if letters.count >= 2, letters.count <= 20, lab.count <= 24, lab == lab.uppercased(),
                       lab.allSatisfy({ $0.isLetter || $0 == " " || $0 == "-" || $0 == "." }) {
                        let len = line.distance(from: line.startIndex, to: colon) + 1
                        ts.addAttributes([.font: label, .foregroundColor: Brand.NS.accentTx, .backgroundColor: Brand.NS.chip, .kern: 0.6],
                                         range: NSRange(location: r.location, length: len))
                    }
                }
            }
            if let rx = try? NSRegularExpression(pattern: "\\[[^\\]\\n]*\\]") {
                for m in rx.matches(in: ts.string, range: full) {
                    ts.addAttributes([.font: italic, .foregroundColor: Brand.NS.tx3], range: m.range)
                }
            }
            ts.endEditing()
            tv.typingAttributes = [.font: Self.baseFont, .foregroundColor: Brand.NS.tx, .paragraphStyle: para]
        }
    }
}
