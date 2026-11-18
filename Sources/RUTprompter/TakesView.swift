import Charts
import PrompterCore
import SwiftUI

/// Пост-анализ дублей текущей сессии (хранятся в памяти).
struct TakesView: View {
    @ObservedObject var engine: PlaybackEngine
    var close: () -> Void
    @StateObject private var selectionBox = StateBox<TakeRecord.ID?>(nil)
    private var selection: TakeRecord.ID? { selectionBox.value }

    var body: some View {
        VStack(spacing: 0) {
            if engine.takes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "film.stack").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Дублей пока нет").font(.title3)
                    Text("Дубль начинается по «Старт» и заканчивается по «Стоп» или в конце текста.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(engine.takes.reversed(), selection: $selectionBox.value) { t in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Дубль \(t.number)").font(.headline)
                            Text(summary(t)).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(t.id)
                    }
                    .frame(minWidth: 180, maxWidth: 240)

                    if let t = engine.takes.first(where: { $0.id == selection }) ?? engine.takes.last {
                        TakeDetail(take: t, engine: engine)
                    }
                }
            }
            Divider()
            HStack {
                Text("Дубли хранятся до закрытия приложения.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Готово", action: close).keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 820, height: 560)
        .onAppear { selectionBox.value = engine.takes.last?.id }
    }

    private func summary(_ t: TakeRecord) -> String {
        var s = TimeEstimator.format(t.duration)
        if let w = t.averageWPM { s += " · \(Int(w)) сл/мин" }
        if !t.completed { s += " · не до конца" }
        return s
    }
}

private struct TakeDetail: View {
    let take: TakeRecord
    let engine: PlaybackEngine

    var body: some View {
        let a = TakeAnalysis(take: take)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    box("Время", TimeEstimator.format(take.duration))
                    box("Средний темп", take.averageWPM.map { "\(Int($0)) сл/мин" } ?? "—")
                    box("Прочитано", "\(Int(take.wordsRead)) из \(take.totalWords)")
                    if let target = take.targetDuration {
                        box("К цели \(TimeEstimator.format(target))", TimeEstimator.formatDelta(take.duration - target))
                    }
                }

                Text("Темп по ходу текста").font(.headline)
                if a.bins.isEmpty {
                    Text("Слишком короткий дубль для графика.").foregroundStyle(.secondary)
                } else {
                    Chart {
                        ForEach(a.bins) { b in
                            BarMark(xStart: .value("Слово", Double(b.firstWord) + 0.3), xEnd: .value("Слово", Double(b.lastWord) + 0.7),
                                    y: .value("сл/мин", b.wpm))
                                .foregroundStyle(color(for: b, median: a.medianWPM))
                        }
                        if let m = a.medianWPM {
                            RuleMark(y: .value("Медиана", m))
                                .foregroundStyle(.secondary)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .annotation(position: .top, alignment: .leading) {
                                    Text("медиана \(Int(m))").font(.caption2).foregroundStyle(.secondary)
                                }
                        }
                    }
                    .chartXAxisLabel("номер слова в скрипте")
                    .chartYAxisLabel("слов/мин")
                    .frame(height: 200)
                }

                Text("Где темп заметно менялся").font(.headline)
                if a.spots.isEmpty {
                    Text("Темп ровный — сильных провалов и ускорений нет.").foregroundStyle(.secondary)
                } else {
                    ForEach(a.spots) { s in
                        HStack(alignment: .top) {
                            Image(systemName: s.kind == .slow ? "tortoise.fill" : "hare.fill")
                                .foregroundStyle(s.kind == .slow ? .blue : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text((s.kind == .slow ? "Медленнее на " : "Быстрее на ") +
                                     "\(Int(abs(s.deviation) * 100))% · \(Int(s.bin.wpm)) сл/мин")
                                    .font(.callout.weight(.medium))
                                Text("«\(engine.excerpt(from: s.bin.firstWord, to: s.bin.lastWord))»")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Перейти") { engine.jump(to: Double(s.bin.firstWord), animated: true) }
                        }
                    }
                }
                if !take.voiceMode {
                    Text("Дубль шёл с фиксированной скоростью — график отражает её, а не реальную речь.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    private func color(for b: TakeAnalysis.Bin, median: Double?) -> Color {
        guard let m = median, m > 0 else { return .accentColor }
        let d = b.wpm / m - 1
        if d <= -0.25 { return .blue }
        if d >= 0.25 { return .orange }
        return .accentColor
    }

    private func box(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}
