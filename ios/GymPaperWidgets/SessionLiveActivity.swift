import WidgetKit
import SwiftUI
import ActivityKit
import GymPaperKit

/// Live workout: Lock Screen + Dynamic Island
/// Dark fill: icon/progress/outline in off-white; orange only for the rest countdown (where it means something)
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { ctx in
            LockView(program: ctx.attributes.program, s: ctx.state, stale: ctx.isStale)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(Color.wOnDark)
        } dynamicIsland: { ctx in
            let s = ctx.state
            let resting = s.restEnd != nil && !ctx.isStale && !s.paused
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.exercise).font(.headline).lineLimit(1)
                        Text(s.finished ? ctx.attributes.program : s.setText).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if resting, let end = s.restEnd {
                            Text(timerInterval: Date.now...max(end, .now), countsDown: true).monospacedDigit()
                                .font(.system(size: 22, weight: .heavy).italic().monospacedDigit()).foregroundStyle(.orange)
                        } else {
                            Text(s.finished ? "Bitti" : s.load).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .multilineTextAlignment(.trailing).frame(maxWidth: 110, alignment: .trailing).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(value: s.progress).tint(Color.wOnDark)
                        HStack {
                            Text(resting ? String(localized: "Dinlenme · sıradaki \(s.load)") : (s.paused ? tl("Duraklatıldı") : ctx.attributes.program))
                            Spacer()
                            Text("\(s.done)/\(s.total) set").monospacedDigit()
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: s.finished ? "checkmark" : "dumbbell.fill").foregroundStyle(Color.wOnDark)
            } compactTrailing: {
                if resting, let end = s.restEnd {
                    Text(timerInterval: Date.now...max(end, .now), countsDown: true).monospacedDigit()
                        .frame(width: 42).foregroundStyle(.orange)
                } else {
                    Text("\(s.done)/\(s.total)").monospacedDigit().font(.caption.weight(.semibold))
                }
            } minimal: {
                if resting, let end = s.restEnd {
                    ProgressView(timerInterval: Date.now...max(end, .now), countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                        .progressViewStyle(.circular).tint(.orange)
                } else {
                    Image(systemName: "dumbbell.fill").foregroundStyle(Color.wOnDark)
                }
            }
            .keylineTint(Color.wOnDark)
        }
    }
}

private struct LockView: View {
    let program: String
    let s: SessionActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        let resting = s.restEnd != nil && !stale && !s.paused
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.wOnDark.opacity(0.14))
                    Image(systemName: s.finished ? "checkmark" : "dumbbell.fill").font(.title3).foregroundStyle(Color.wOnDark)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(program).font(.caption).foregroundStyle(.white.opacity(0.7))
                    Text(s.finished ? "Antrenman tamamlandı" : s.exercise).font(.headline).foregroundStyle(.white).lineLimit(1)
                    if !s.finished {
                        Text(subtitle(resting)).font(.subheadline).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if resting, let end = s.restEnd {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(timerInterval: Date.now...max(end, .now), countsDown: true).monospacedDigit()
                            .font(.system(size: 30, weight: .heavy).italic().monospacedDigit()).foregroundStyle(.orange)
                            .multilineTextAlignment(.trailing).frame(width: 90, alignment: .trailing)
                        Text("dinlenme").font(.caption2).foregroundStyle(.white.opacity(0.6))
                    }
                } else if s.paused {
                    Image(systemName: "pause.circle.fill").font(.title).foregroundStyle(.white.opacity(0.8))
                }
            }
            // when stale (the app couldn't update for 15 min) faded + warning, so old info doesn't look live on the Lock Screen
            ProgressView(value: s.progress).tint(Color.wOnDark).opacity(stale && !s.finished ? 0.4 : 1)
            HStack {
                Text(stale && s.restEnd != nil ? "Dinlenme bitti · sıradaki sete geç"
                     : stale && !s.finished ? "Seans güncel değil · uygulamayı aç"
                     : "%\(Int((s.progress * 100).rounded())) tamamlandı")
                Spacer()
                Text("\(s.done)/\(s.total) set").monospacedDigit()
            }
            .font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
    }

    private func subtitle(_ resting: Bool) -> String {
        if s.paused { return tl("Duraklatıldı") }
        return resting ? String(localized: "Sıradaki: \(s.setText) · \(s.load)") : "\(s.setText) · \(s.load)"
    }
}

// MARK: - Intermittent fasting

/// Fasting live activity: Lock Screen + Dynamic Island.
/// Counts down to "Fast ends" while fasting and "Fast starts" in the eating window; moves to the next phase when stale.
struct FastLiveActivity: Widget {
    /// When stale the next phase is shown
    static func phase(_ s: FastActivityAttributes.ContentState, stale: Bool) -> (from: Date, to: Date, fasting: Bool) {
        stale ? (s.end, s.next, !s.fasting) : (s.start, s.end, s.fasting)
    }
    static func label(_ fasting: Bool) -> String { fasting ? tl("Oruç bitişi") : tl("Oruç başlangıcı") }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastActivityAttributes.self) { ctx in
            let p = Self.phase(ctx.state, stale: ctx.isStale)
            VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ProgressView(timerInterval: p.from...max(p.to, p.from.addingTimeInterval(1)), countsDown: false) { EmptyView() } currentValueLabel: {
                    Image(systemName: p.fasting ? "moon.stars.fill" : "fork.knife").font(.system(size: 14))
                }
                .progressViewStyle(.circular).tint(Color.wLime).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.fasting ? "Oruç · \(ctx.attributes.label)" : "Yeme aralığı").font(.headline)
                    Text("\(p.from.formatted(date: .omitted, time: .shortened)) – \(p.to.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Self.label(p.fasting)).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                    Text(timerInterval: Date.now...max(p.to, .now), countsDown: true)
                        .monospacedDigit().font(.system(size: 22, weight: .heavy).italic().monospacedDigit()).foregroundStyle(Color.wLime)
                        .multilineTextAlignment(.trailing)
                }
                .frame(maxWidth: 120, alignment: .trailing)
            }
            // fasting stages: the fill runs on the system, no updates needed
            if p.fasting {
                FastStageTrack(start: p.from, end: p.to, tint: .wLime)
            }
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.55))
            .activitySystemActionForegroundColor(.wLime)
        } dynamicIsland: { ctx in
            let p = Self.phase(ctx.state, stale: ctx.isStale)
            let tint: Color = .wLime   // marka rengi (koyu zeminde)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(p.fasting ? "Oruç" : "Yeme aralığı", systemImage: p.fasting ? "moon.stars.fill" : "fork.knife").font(.headline)
                        Text(ctx.attributes.label).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Self.label(p.fasting)).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        Text(timerInterval: Date.now...max(p.to, .now), countsDown: true).monospacedDigit()
                            .font(.system(size: 22, weight: .heavy).italic().monospacedDigit()).foregroundStyle(tint).multilineTextAlignment(.trailing)
                    }
                    .frame(maxWidth: 120, alignment: .trailing).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(timerInterval: p.from...max(p.to, p.from.addingTimeInterval(1)), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                            .tint(tint)
                        HStack {
                            Text(p.from.formatted(date: .omitted, time: .shortened))
                            Spacer()
                            Text(p.to.formatted(date: .omitted, time: .shortened))
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: p.fasting ? "moon.stars.fill" : "fork.knife").foregroundStyle(tint)
            } compactTrailing: {
                Text(timerInterval: Date.now...max(p.to, .now), countsDown: true).monospacedDigit()
                    .frame(width: 52).foregroundStyle(tint)
            } minimal: {
                ProgressView(timerInterval: p.from...max(p.to, p.from.addingTimeInterval(1)), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.circular).tint(tint)
            }
        }
    }
}

/// Fasting widget: Home Screen (small) and Lock Screen (circular / rectangular)
struct FastingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "gympaper.oruc", provider: FastProvider()) { e in
            FastingWidgetView(e: e).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Aralıklı oruç")
        .description("Oruç ya da yeme penceresinde kalan süre.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct FastEntry: TimelineEntry {
    let date: Date
    let plan: FastPlan?
}

/// New entries when the state changes (fast starts/ends); the countdown runs on the system
struct FastProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastEntry { FastEntry(date: .now, plan: FastPlan()) }
    func getSnapshot(in context: Context, completion: @escaping (FastEntry) -> Void) {
        completion(FastEntry(date: .now, plan: context.isPreview ? FastPlan() : SharedStore.shared.read()?.fast))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FastEntry>) -> Void) {
        let plan = SharedStore.shared.read()?.fast
        var entries = [FastEntry(date: .now, plan: plan)]
        if let plan {
            var t = Date.now
            for _ in 0..<6 {
                let next: Date
                switch plan.phase(at: t) {
                case .fasting(_, let end, _): next = end
                case .eating(_, let nf, _): next = nf
                }
                t = next.addingTimeInterval(1)
                entries.append(FastEntry(date: t, plan: plan))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct FastingWidgetView: View {
    let e: FastEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        if let plan = e.plan {
            let ph = plan.phase(at: e.date)
            let (from, to, fasting): (Date, Date, Bool) = {
                switch ph {
                case .fasting(let s, let end, _): return (s, end, true)
                case .eating(let since, let nf, _): return (since, nf, false)
                }
            }()
            let range = from...max(to, from.addingTimeInterval(1))
            switch family {
            case .accessoryInline:
                Label {
                    Text(fasting ? "Oruç · " : "Yeme · ") + Text(timerInterval: Date.now...max(to, .now), countsDown: true)
                } icon: { Image(systemName: fasting ? "moon.stars.fill" : "fork.knife") }
            case .accessoryCircular:
                ProgressView(timerInterval: range, countsDown: false) {
                    Image(systemName: fasting ? "moon.stars.fill" : "fork.knife")
                } currentValueLabel: {
                    Image(systemName: fasting ? "moon.stars.fill" : "fork.knife")
                }
                .progressViewStyle(.circular).widgetAccentable()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label(fasting ? "Oruç \(plan.label)" : "Yeme aralığı", systemImage: fasting ? "moon.stars.fill" : "fork.knife")
                        .font(.headline).widgetAccentable()
                    Text(timerInterval: Date.now...max(to, .now), countsDown: true).monospacedDigit().font(.system(size: 20, weight: .heavy).italic().monospacedDigit())
                    Text(fasting ? "Bitiş \(to.formatted(date: .omitted, time: .shortened))" : "Oruç \(to.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: fasting ? "moon.stars.fill" : "fork.knife").foregroundStyle(Color.wBrand)
                        Text(fasting ? "Oruç" : "Yeme aralığı").font(.caption.weight(.semibold))
                    }
                    Spacer(minLength: 0)
                    Text(timerInterval: Date.now...max(to, .now), countsDown: true)
                        .monospacedDigit().font(.system(size: 26, weight: .heavy).italic().monospacedDigit()).minimumScaleFactor(0.6)
                    ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(Color.wLime)   // brand color
                    Text(fasting ? "Bitiş \(to.formatted(date: .omitted, time: .shortened))" : "Oruç \(to.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "moon.stars")
                Text("Oruç kapalı").font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }
}
