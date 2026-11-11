import SwiftUI
import SwiftData
import GymPaperKit

/// My measurements: chart + all measurements by month; edit / swipe to delete / add
struct ProfileMeasuresScreen: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \BodyMeasure.date, order: .reverse) private var measures: [BodyMeasure]
    @State private var editing: MeasureEdit?

    struct MeasureEdit: Identifiable {
        var m: BodyMeasure?
        var id: String { m.map { "\($0.persistentModelID.hashValue)" } ?? "new" }
    }

    var body: some View {
        let p = profiles.first ?? UserProfile()
        let G = GoalState(startKg: p.startKg, goals: p.goals, measures: measures)
        let prev = measures.prevKgMap()
        BScreen(pinHeader: false) {
            HStack(alignment: .top) {
                WkPushedHeader(eyebrow: "Profil", title: "Ölçümlerim", sub: measures.isEmpty ? nil : String(localized: "\(measures.count) ölçüm"))
                Spacer(minLength: 0)
                ProfileTextButton("Ekle") { editing = MeasureEdit(m: nil) }
                    .padding(.top, 4)
            }
            if measures.isEmpty {
                BEmpty(symbol: "scalemass", title: "Henüz ölçüm yok", text: "Kilonu ve çevre ölçülerini ekle; değişimi burada grafikle görürsün.",
                       action: "İlk ölçümünü ekle") { editing = MeasureEdit(m: nil) }
            } else {
                ProfileMeasuresCard(measures: measures, goal: G.active, onEdit: { editing = MeasureEdit(m: $0) }, onDelete: delete, showList: false)
                ForEach(groups, id: \.key) { g in
                    ProfileSectionTitle(g.title)
                    LazyVStack(spacing: 0) {
                        ForEach(Array(g.items.enumerated()), id: \.element.persistentModelID) { i, m in
                            if i > 0 { Rectangle().fill(Color.bBorder).frame(height: 1).padding(.leading, 16) }
                            row(m, prevKg: prev[m.persistentModelID])
                                .bSwipeDelete { delete(m) }
                        }
                    }
                    .bCard(padding: 0)
                    .clipShape(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
                }
            }
        }
        .sheet(item: $editing) { e in MeasureSheet(edit: e.m) }
    }

    /// Groups by month (newest first)
    private var groups: [(key: String, title: String, items: [BodyMeasure])] {
        var order: [String] = []
        var map: [String: [BodyMeasure]] = [:]
        for m in measures {
            let k = String(DayKey.of(m.date).prefix(7))
            if map[k] == nil { order.append(k) }
            map[k, default: []].append(m)
        }
        return order.map { k in (k, trMonthYear(k + "-01"), map[k] ?? []) }
    }

    private func row(_ m: BodyMeasure, prevKg: Double?) -> some View {
        let d = (m.kg != nil && prevKg != nil) ? m.kg! - prevKg! : nil
        let extra = profileMeasureFields.dropFirst().compactMap { f in m[keyPath: f.key].map { "\(tl(f.label)) \(fmt1($0)) \(f.unit)" } }
        return Button { editing = MeasureEdit(m: m) } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trLongDate(DayKey.of(m.date))).font(.geist(15, .medium)).foregroundStyle(Color.bFg)
                    if !extra.isEmpty {
                        Text(extra.joined(separator: " · ")).font(.bXs).foregroundStyle(Color.bMutedFg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    if let kg = m.kg {
                        (Text(fmt1(kg)).font(.bNum(17)) + Text(" kg").font(.bXs).foregroundStyle(Color.bMutedFg))
                            .monospacedDigit().foregroundStyle(Color.bFg)
                    }
                    if let d, d != 0 {
                        Text("\(d < 0 ? "↓" : "↑") \(fmt1(abs(d))) kg").font(.geist(12, .medium)).monospacedDigit()
                            .foregroundStyle(d < 0 ? Color.bSuccess : Color.bMutedFg)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press)
    }

    /// Deletes a measurement (undoable)
    private func delete(_ m: BodyMeasure) {
        let date = m.date
        let vals = profileMeasureFields.map { ($0.key, m[keyPath: $0.key]) }
        withAnimation { ctx.delete(m) }
        Store.save(ctx)
        app.toast("Ölçüm silindi", kind: .delete) {
            let n = BodyMeasure(date: date, kg: nil)
            for (k, v) in vals { n[keyPath: k] = v }
            ctx.insert(n); Store.save(ctx)
        }
    }
}

extension Array where Element == BodyMeasure {
    /// Previous weight of each measurement in a newest-first list, in one pass
    func prevKgMap() -> [PersistentIdentifier: Double] {
        var out: [PersistentIdentifier: Double] = [:]
        var last: Double?
        for m in reversed() {
            if let last { out[m.persistentModelID] = last }
            if let kg = m.kg { last = kg }
        }
        return out
    }
}
