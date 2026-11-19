import Charts
import PrompterCore
import SwiftUI

/// Пост-анализ дублей текущей сессии (хранятся в памяти).
struct TakesPage: View {
    @ObservedObject var engine: PlaybackEngine
    @StateObject private var selectionBox = StateBox<TakeRecord.ID?>(nil)

    private var selected: TakeRecord? {
        engine.takes.first(where: { $0.id == selectionBox.value }) ?? engine.takes.last
    }

    var body: some View {
        Group {
            if engine.takes.isEmpty {
                VStack(spacing: 10) {
                    ChevronMark().fill(Brand.hi.opacity(0.35)).frame(width: 40, height: 42)
                    Text("Дублей пока нет").font(.system(size: 17, weight: .bold)).foregroundColor(Brand.tx)
                    Text("Дубль начинается по «Старт» и заканчивается по «Стоп» или в конце текста.")
                        .foregroundColor(Brand.tx2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 80)
            } else {
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 6) {
                        ForEach(engine.takes.reversed()) { t in
                            TakeRow(take: t, selected: t.id == selected?.id) { selectionBox.value = t.id }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: 210)
                    if let t = selected {
                        ScrollView { TakeDetail(take: t, engine: engine).padding(.bottom, 110) }
                    }
                }
                .padding(.horizontal, 22)
            }
        }
        .onAppear { selectionBox.value = engine.takes.last?.id }
    }
}

private struct TakeRow: View {
    let take: TakeRecord
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Дубль \(take.number)").font(.system(size: 14, weight: .bold)).foregroundColor(selected ? .white : Brand.tx)
                Text(summary).font(.system(size: 11)).foregroundColor(selected ? .white.opacity(0.8) : Brand.tx2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Brand.accent : Brand.surface))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Brand.line, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private var summary: String {
        var s = TimeEstimator.format(take.duration)
        if let w = take.averageWPM { s += " · \(Int(w)) сл/мин" }
        if !take.completed { s += " · не до конца" }
        return s
    }
}

private struct TakeDetail: View {
    let take: TakeRecord
    let engine: PlaybackEngine

    var body: some View {
        let a = TakeAnalysis(take: take)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                box("Время", TimeEstimator.format(take.duration))
                box("Средний темп", take.averageWPM.map { "\(Int($0)) сл/мин" } ?? "—")
                box("Прочитано", "\(Int(take.wordsRead)) из \(take.totalWords)")
                if let target = take.targetDuration {
                    let d = take.duration - target
                    box("К цели \(TimeEstimator.format(target))", TimeEstimator.formatDelta(d), seal: d <= 0 && take.completed)
                }
            }

            Panel("Темп по ходу текста") {
                if a.bins.isEmpty {
                    Hint("Слишком короткий дубль для графика.")
                } else {
                    Chart {
                        ForEach(a.bins) { b in
                            BarMark(xStart: .value("Слово", Double(b.firstWord) + 0.3), xEnd: .value("Слово", Double(b.lastWord) + 0.7),
                                    y: .value("сл/мин", b.wpm))
                                .foregroundStyle(color(for: b, median: a.medianWPM))
                        }
                        if let m = a.medianWPM {
                            RuleMark(y: .value("Медиана", m))
                                .foregroundStyle(Brand.tx3)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .annotation(position: .top, alignment: .leading) {
                                    Text("медиана \(Int(m))").font(.caption2).foregroundColor(Brand.tx2)
                                }
                        }
                    }
                    .chartXAxisLabel("номер слова в сценарии")
                    .chartYAxisLabel("слов/мин")
                    .frame(height: 200)
                }
            }

            Panel("Где темп заметно менялся") {
                if a.spots.isEmpty {
                    Hint("Темп ровный: сильных провалов и ускорений нет.")
                } else {
                    ForEach(a.spots) { s in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: s.kind == .slow ? "tortoise.fill" : "hare.fill")
                                .foregroundColor(s.kind == .slow ? Brand.hi : Brand.warn)
                            VStack(alignment: .leading, spacing: 2) {
                                Text((s.kind == .slow ? "Медленнее на " : "Быстрее на ") +
                                     "\(Int(abs(s.deviation) * 100))% · \(Int(s.bin.wpm)) сл/мин")
                                    .font(.system(size: 13, weight: .semibold)).foregroundColor(Brand.tx)
                                Text("«\(engine.excerpt(from: s.bin.firstWord, to: s.bin.lastWord))»")
                                    .font(.system(size: 13)).foregroundColor(Brand.tx2)
                            }
                            Spacer()
                            Button("Перейти") { engine.jump(to: Double(s.bin.firstWord), animated: true) }
                        }
                    }
                }
                if !take.voiceMode {
                    Hint("Дубль шёл с фиксированной скоростью: график показывает её, а не реальную речь.")
                }
            }
        }
    }

    private func color(for b: TakeAnalysis.Bin, median: Double?) -> Color {
        guard let m = median, m > 0 else { return Brand.accent }
        let d = b.wpm / m - 1
        if d <= -0.25 { return Brand.cyan }
        if d >= 0.25 { return Brand.warn }
        return Brand.hi
    }

    private func box(_ title: String, _ value: String, seal: Bool = false) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11)).foregroundColor(Brand.tx2)
                Text(value).font(.system(size: 22, weight: .heavy)).monospacedDigit().foregroundColor(Brand.tx)
            }
            if seal { Spacer(minLength: 0); HoloSeal(size: 30) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Brand.line, lineWidth: 1))
    }
}
