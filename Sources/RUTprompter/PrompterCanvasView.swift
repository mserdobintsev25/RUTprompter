import AppKit
import PrompterCore

/// Отрисовка текста суфлёра. Один и тот же класс используется для
/// превью в окне оператора (всегда нормальная ориентация) и для окна
/// вывода на втором экране (с собственным зеркалированием и масштабом).
///
/// Позиция в словах → вертикальное смещение: внутри строки смещение
/// растёт пропорционально горизонтальному положению слова, поэтому
/// текст едет плавно, а не прыгает построчно.
final class PrompterCanvasView: NSView {

    enum Role { case preview, output }

    let role: Role
    weak var engine: PlaybackEngine?

    var theme = PrompterTheme() { didSet { if theme != oldValue { invalidateText() } } }
    var output = OutputSettings() { didSet { if output != oldValue { invalidateText() } } }

    private var document = PrompterDocument("")
    private let storage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))

    private struct WordGeom {
        let yStart: CGFloat
        let lineRect: CGRect
    }
    private var geoms: [WordGeom] = []
    private var layoutValid = false
    private var laidOutWidth: CGFloat = -1
    private var dimmedUpTo = -1
    private var stats = PlaybackStats()
    private var lastDrawnPosition = -1.0

    init(role: Role) {
        self.role = role
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        container.lineFragmentPadding = 0
        layoutManager.allowsNonContiguousLayout = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    // MARK: Входы от движка

    func setDocument(_ doc: PrompterDocument) {
        document = doc
        invalidateText()
    }

    func positionDidChange() { needsDisplay = true }

    func statsDidChange(_ s: PlaybackStats) {
        let needs = role == .output && (s.secondsRemaining.rounded() != stats.secondsRemaining.rounded()
                                        || s.sectionEnding != stats.sectionEnding || s.targetDelta != stats.targetDelta)
        stats = s
        if needs { needsDisplay = true }
    }

    private var position: Double { engine?.displayPosition ?? 0 }

    // MARK: Раскладка

    private var scale: CGFloat {
        let base = max(bounds.width, 200) / 1000
        return base * CGFloat(role == .output ? output.fontScale : 1)
    }
    private var marginX: CGFloat { bounds.width * CGFloat(theme.horizontalMargin) }
    private var readingY: CGFloat { bounds.height * CGFloat(theme.readingLine) }

    private func invalidateText() {
        layoutValid = false
        dimmedUpTo = -1
        needsDisplay = true
    }

    private func ensureLayout() {
        if layoutValid && laidOutWidth == bounds.width { return }
        laidOutWidth = bounds.width
        layoutValid = true
        dimmedUpTo = -1

        let size = CGFloat(theme.fontSize) * scale
        let font = theme.fontFamily.font(size: size, weight: theme.fontWeight.nsWeight)
        let small = theme.fontFamily.font(size: size * 0.55, weight: .semibold)
        let remarkFont = NSFontManager.shared.convert(theme.fontFamily.font(size: size * 0.7, weight: .regular), toHaveTrait: .italicFontMask)

        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = CGFloat(theme.lineSpacing)
        para.paragraphSpacing = size * CGFloat(theme.paragraphSpacing)
        para.alignment = theme.centered ? .center : .natural
        para.lineBreakMode = .byWordWrapping

        let headerPara = para.mutableCopy() as! NSMutableParagraphStyle
        headerPara.paragraphSpacingBefore = size * 0.5
        headerPara.lineHeightMultiple = 1.1

        let colors = theme.colors
        let attr = NSMutableAttributedString(string: document.displayText, attributes: [
            .font: font, .foregroundColor: colors.text.nsColor, .paragraphStyle: para
        ])
        for run in document.runs {
            switch run.kind {
            case .header:
                attr.addAttributes([.font: small, .foregroundColor: colors.remark.nsColor,
                                    .paragraphStyle: headerPara, .kern: size * 0.04], range: run.range)
            case .remark:
                attr.addAttributes([.font: remarkFont, .foregroundColor: colors.remark.nsColor], range: run.range)
            case .speakerLabel:
                attr.addAttributes([.font: small, .foregroundColor: colors.remark.nsColor], range: run.range)
            }
        }
        storage.setAttributedString(attr)
        container.size = NSSize(width: max(bounds.width - 2 * marginX, 50), height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)

        geoms = document.words.map { w in
            let g = layoutManager.glyphRange(forCharacterRange: w.range, actualCharacterRange: nil)
            let line = layoutManager.lineFragmentRect(forGlyphAt: g.location, effectiveRange: nil)
            let used = layoutManager.lineFragmentUsedRect(forGlyphAt: g.location, effectiveRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: g, in: container)
            let frac = used.width > 1 ? min(max((rect.minX - used.minX) / used.width, 0), 1) : 0
            return WordGeom(yStart: line.minY + line.height * frac, lineRect: line)
        }
    }

    /// Вертикальная координата (в координатах текста) для позиции.
    private func y(at p: Double) -> CGFloat {
        guard !geoms.isEmpty else { return 0 }
        let n = geoms.count
        if p <= 0 { return geoms[0].yStart }
        if p >= Double(n) { return geoms[n - 1].lineRect.maxY }
        let i = Int(p.rounded(.down))
        let f = CGFloat(p - Double(i))
        let a = geoms[i].yStart
        let b = i + 1 < n ? geoms[i + 1].yStart : geoms[i].lineRect.maxY
        return a + (b - a) * f
    }

    /// Обратное преобразование y → позиция.
    private func position(atY y: CGFloat) -> Double {
        guard !geoms.isEmpty else { return 0 }
        let n = geoms.count
        if y <= geoms[0].yStart { return 0 }
        if y >= geoms[n - 1].lineRect.maxY { return Double(n) }
        var lo = 0, hi = n - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if geoms[mid].yStart <= y { lo = mid } else { hi = mid - 1 }
        }
        let a = geoms[lo].yStart
        let b = lo + 1 < n ? geoms[lo + 1].yStart : geoms[lo].lineRect.maxY
        let f = b > a ? Double((y - a) / (b - a)) : 0
        return Double(lo) + min(max(f, 0), 1)
    }

    /// Позиция на `delta` строк выше/ниже (для стрелок ↑/↓).
    func position(byMovingLines delta: Int, from p: Double) -> Double {
        ensureLayout()
        guard !geoms.isEmpty else { return p }
        let i = min(max(Int(p.rounded(.down)), 0), geoms.count - 1)
        let lineH = geoms[i].lineRect.height
        return position(atY: y(at: p) + CGFloat(delta) * lineH)
    }

    private var scrollOffset: CGFloat { y(at: position) - readingY }

    // MARK: Отрисовка

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ensureLayout()
        let colors = theme.colors
        colors.background.nsColor.setFill()
        bounds.fill()

        ctx.saveGState()
        if role == .output {
            if output.mirrorHorizontal { ctx.translateBy(x: bounds.width, y: 0); ctx.scaleBy(x: -1, y: 1) }
            if output.mirrorVertical { ctx.translateBy(x: 0, y: bounds.height); ctx.scaleBy(x: 1, y: -1) }
        }

        let p = position
        lastDrawnPosition = p
        let offset = scrollOffset
        let origin = CGPoint(x: marginX, y: -offset)

        updateDimming(p)

        if theme.highlightCurrentLine, !geoms.isEmpty, p < Double(geoms.count) {
            let i = min(max(Int(p.rounded(.down)), 0), geoms.count - 1)
            var band = geoms[i].lineRect
            band.origin.x = 0
            band.size.width = bounds.width
            band.origin.y += origin.y
            colors.highlight.nsColor.setFill()
            NSBezierPath(roundedRect: band.insetBy(dx: bounds.width * 0.015, dy: -band.height * 0.04),
                         xRadius: 8, yRadius: 8).fill()
        }

        let visible = CGRect(x: 0, y: offset, width: container.size.width, height: bounds.height)
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        layoutManager.drawBackground(forGlyphRange: glyphs, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphs, at: origin)

        if document.wordCount == 0 {
            let s = NSAttributedString(string: "Вставьте текст скрипта в окне оператора", attributes: [
                .font: NSFont.systemFont(ofSize: 28 * scale, weight: .medium),
                .foregroundColor: colors.readText.nsColor])
            s.draw(at: CGPoint(x: marginX, y: readingY))
        }

        if role == .preview || output.showReadingMarker { drawReadingMarker(colors) }
        if role == .output { drawOverlays(colors) }
        ctx.restoreGState()
    }

    private func updateDimming(_ p: Double) {
        guard theme.dimReadText, !document.words.isEmpty else {
            if dimmedUpTo != -1 {
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: storage.length))
                dimmedUpTo = -1
            }
            return
        }
        let i = min(max(Int(p.rounded(.down)), 0), document.words.count)
        guard i != dimmedUpTo else { return }
        dimmedUpTo = i
        let full = NSRange(location: 0, length: storage.length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        let end = i < document.words.count ? document.words[i].range.location : storage.length
        if end > 0 {
            layoutManager.addTemporaryAttribute(.foregroundColor, value: theme.colors.readText.nsColor,
                                                forCharacterRange: NSRange(location: 0, length: end))
        }
    }

    private func drawReadingMarker(_ colors: PrompterColors) {
        let h = max(CGFloat(theme.fontSize) * scale * 0.45, 8)
        let x = max(marginX * 0.35, 4)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: x, y: readingY - h / 2))
        path.line(to: CGPoint(x: x + h * 0.8, y: readingY))
        path.line(to: CGPoint(x: x, y: readingY + h / 2))
        path.close()
        colors.marker.nsColor.setFill()
        path.fill()
    }

    private func drawOverlays(_ colors: PrompterColors) {
        let fs = max(bounds.width / 1000 * 22, 12)
        let electric = NSColor(srgbRed: 0, green: 0.4, blue: 1, alpha: 1)
        let brand = NSColor(srgbRed: 0, green: 0.361, blue: 0.788, alpha: 1)
        if output.showProgress {
            let h = max(fs * 0.3, 4)
            colors.readText.nsColor.withAlphaComponent(0.35).setFill()
            CGRect(x: 0, y: 0, width: bounds.width, height: h).fill()
            colors.marker.nsColor.setFill()
            CGRect(x: 0, y: 0, width: bounds.width * CGFloat(stats.progress), height: h).fill()
        }
        // Время: фирменная плашка, как «19:30» из листа компонентов.
        if output.showTimer {
            var text = TimeEstimator.format(stats.secondsRemaining)
            if let d = stats.targetDelta, stats.elapsed > 1 { text += "  ·  " + TimeEstimator.formatDelta(d) }
            let s = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: fs * 1.25, weight: .bold), .foregroundColor: NSColor.white])
            let size = s.size()
            let pad = fs * 0.9
            let rect = CGRect(x: bounds.width - size.width - pad * 2 - fs * 1.2,
                              y: bounds.height - size.height - pad * 0.9 - fs * 0.9,
                              width: size.width + pad * 2, height: size.height + pad * 0.9)
            electric.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            s.draw(at: CGPoint(x: rect.minX + pad, y: rect.minY + pad * 0.45))
        }
        // «Раздел заканчивается»: плашка с двойной обводкой, как «мероприятие».
        if output.showSectionAlert, stats.sectionEnding, let title = stats.sectionTitle,
           let left = stats.sectionSecondsRemaining {
            let s = NSAttributedString(string: "\(title) · ещё \(TimeEstimator.format(left))", attributes: [
                .font: NSFont.systemFont(ofSize: fs * 1.05, weight: .bold), .foregroundColor: NSColor.white])
            let size = s.size()
            let outer = CGRect(x: fs * 1.2, y: bounds.height - size.height - fs * 2.5,
                               width: size.width + fs * 2.2, height: size.height + fs * 1.1)
            brand.setFill()
            NSBezierPath(roundedRect: outer, xRadius: fs * 0.7, yRadius: fs * 0.7).fill()
            let inner = outer.insetBy(dx: fs * 0.26, dy: fs * 0.26)
            NSColor.white.setStroke()
            let ring = NSBezierPath(roundedRect: inner, xRadius: fs * 0.5, yRadius: fs * 0.5)
            ring.lineWidth = max(fs * 0.1, 1.5)
            ring.stroke()
            s.draw(at: CGPoint(x: outer.minX + fs * 1.1, y: outer.minY + fs * 0.55))
        }
    }

    // MARK: Управление мышью (только превью — окно оператора)

    override func mouseDown(with event: NSEvent) {
        guard role == .preview, let engine else { return }
        ensureLayout()
        let pt = convert(event.locationInWindow, from: nil)
        let inText = CGPoint(x: pt.x - marginX, y: pt.y + scrollOffset)
        var fraction: CGFloat = 0
        let ci = layoutManager.characterIndex(for: inText, in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
        if let w = document.wordIndex(atCharacter: ci) {
            engine.jump(to: Double(w), animated: true)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard role == .preview, let engine else { return }
        ensureLayout()
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
        let newP = position(atY: y(at: engine.displayPosition) - dy)
        engine.scrub(to: newP)
    }

    override func resetCursorRects() {
        if role == .preview { addCursorRect(bounds, cursor: .pointingHand) }
    }
}
