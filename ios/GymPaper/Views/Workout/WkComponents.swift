import SwiftUI
import SwiftData
import GymPaperKit

// Shared parts of the Workout screen

/// Empty state with a dashed border
struct WkEmpty<A: View>: View {
    var icon: String?
    var title: String
    var text: String?
    @ViewBuilder var action: A
    var body: some View {
        VStack(spacing: 8) {
            if let icon { Ti(icon, size: 24).foregroundStyle(Color.bMutedFg) }
            Text(tl(title)).font(.geist(16, .medium)).foregroundStyle(Color.bFg)
            if let text { Text(tl(text)).font(.bSm).foregroundStyle(Color.bMutedFg).multilineTextAlignment(.center) }
            action.padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 32)
        .overlay(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous).strokeBorder(Color.bBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}
extension WkEmpty where A == EmptyView {
    init(icon: String?, title: String, text: String?) { self.init(icon: icon, title: title, text: text) { EmptyView() } }
}

/// Section title
struct WkSectionTitle<A: View>: View {
    var title: String
    @ViewBuilder var action: A
    var body: some View {
        HStack {
            Text(tl(title).uppercased(with: .current)).font(.geist(12, .medium, relativeTo: .caption)).tracking(0.6).foregroundStyle(Color.bMutedFg)
            Spacer()
            action
        }
        .padding(.top, 8)
    }
}
extension WkSectionTitle where A == EmptyView { init(_ title: String) { self.init(title: title) { EmptyView() } } }

/// Exercise thumbnail (MoveKit poster; neutral box otherwise)
struct WkThumb: View {
    var name: String? = nil
    var size: CGFloat = 56
    var body: some View { MotionThumb(name: name, size: size) }
}

/// Divided list inside a card
struct WkDivided<C: View>: View {
    @ViewBuilder var content: C
    var body: some View {
        _VariadicView.Tree(WkDividedLayout()) { content }
    }
}
private struct WkDividedLayout: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        VStack(spacing: 0) {
            ForEach(children) { c in
                c
                if c.id != last { Rectangle().fill(Color.bBorder).frame(height: 1) }
            }
        }
    }
}

/// Divided list inside a card
struct WkListCard<C: View>: View {
    var border: Color? = nil
    @ViewBuilder var content: C
    var body: some View {
        WkDivided { content }
            .bCard(padding: 0, highlight: border)
            .clipShape(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
    }
}

// MARK: - Day strip

enum WkDayState { case done, todo, rest }

struct WkDayMark: View {
    var state: WkDayState; var sel: Bool
    var body: some View {
        switch state {
        case .done:
            Circle().fill(Color.bSuccess).frame(width: 14, height: 14).overlay(Ti("check", size: 10).foregroundStyle(.white))
        case .todo:
            Circle().fill(sel ? Color.bSelFg.opacity(0.35) : Color.bFg.opacity(0.25)).frame(width: 14, height: 14)
        case .rest:
            Circle().strokeBorder(sel ? Color.bSelFg.opacity(0.45) : Color.bFg.opacity(0.3), lineWidth: 1.5).frame(width: 14, height: 14)
        }
    }
}

struct WkDayStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Namespace private var ns
    @Binding var value: Int
    var todayIndex: Int
    var label: (Int) -> String
    var status: (Int) -> WkDayState
    /// Legend explaining dot / ring / check
    var legend = false
    var body: some View {
        VStack(spacing: 6) {
        HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { i in
                let sel = i == value, l = label(i), rest = l == "–"
                // the selection slides between days
                Button { withAnimation(reduce ? nil : .snappy(duration: 0.28, extraBounce: 0.04)) { value = i } } label: {
                    VStack(spacing: 2) {
                        WkDayMark(state: status(i), sel: sel).padding(.bottom, 2)
                        Text(DayKey.dayShort[i]).font(.geist(13, .semibold, relativeTo: .footnote)).lineLimit(1).minimumScaleFactor(0.6)
                        // if the name doesn't fit it isn't truncated, it's hidden
                        WkFitLabel(text: l)
                            .foregroundStyle(sel ? Color.bSelFg.opacity(rest ? 0.6 : 0.85) : (rest ? Color.bMutedFg.opacity(0.7) : Color.bMutedFg))
                    }
                    .foregroundStyle(sel ? Color.bSelFg : Color.bFg)
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous).fill(Color.bCard)
                            if sel { RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous).fill(Color.bSel).matchedGeometryEffect(id: "daySel", in: ns) }
                        }
                    }
                }
                .buttonStyle(.press)
                .accessibilityLabel("\(DayKey.dayLong[i])\(i == todayIndex ? ", bugün" : ""), \(rest ? "antrenman yok" : l)")
                .accessibilityAddTraits(sel ? [.isSelected] : [])
            }
        }
        if legend {
            HStack(spacing: 14) {
                legendItem(.done, "Yapıldı"); legendItem(.todo, "Antrenman"); legendItem(.rest, "Dinlenme")
            }
            .font(.geist(11, relativeTo: .caption2)).foregroundStyle(Color.bMutedFg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
        }
        }
        .padding(.vertical, 8)
        .sensoryFeedback(.selection, trigger: value)
    }
    private func legendItem(_ s: WkDayState, _ t: String) -> some View {
        HStack(spacing: 5) { WkDayMark(state: s, sel: false).scaleEffect(0.85); Text(tl(t)) }
    }
}

/// Day strip label: one line, or two lines split at words if it doesn't fit; empty if that doesn't fit either
private struct WkFitLabel: View {
    let text: String
    var body: some View {
        let words = text.split(separator: " ").map(String.init)
        let font = Font.geist(10, relativeTo: .caption2)
        ViewThatFits(in: .horizontal) {
            Text(text).font(font).tracking(-0.2).lineLimit(1).fixedSize()
            if words.count >= 2 {
                VStack(spacing: 0) {
                    Text(words[0]).lineLimit(1).fixedSize()
                    Text(words.dropFirst().joined(separator: " ")).lineLimit(1).fixedSize()
                }
                .font(font).tracking(-0.2)
            }
            Color.clear.frame(width: 1, height: 12)
        }
        .frame(maxWidth: .infinity)
    }
}

struct WkWeekNav: View {
    @Binding var wk: Int
    var onToday: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Button { wk -= 1 } label: { Ti("chevron-left") }.buttonStyle(.b(.outline, .iconLarge)).accessibilityLabel("Önceki hafta")
            Spacer()
            VStack(spacing: 2) {
                Text(label).font(.geist(14, .medium, relativeTo: .subheadline)).foregroundStyle(Color.bFg)
                Text("\(Wk.shortDate(Wk.weekDate(0, wk))) – \(Wk.shortDate(Wk.weekDate(6, wk)))").font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg)
            }
            Spacer()
            HStack(spacing: 0) {
                if wk != 0 { Button("Bugün") { onToday() }.buttonStyle(.b(.ghost)) }
                Button { wk += 1 } label: { Ti("chevron-right") }.buttonStyle(.b(.outline, .iconLarge)).accessibilityLabel("Sonraki hafta")
            }
        }
        .padding(.vertical, -4)
    }
    private var label: String {
        switch wk {
        case 0: tl("Bu hafta"); case -1: tl("Geçen hafta"); case 1: tl("Gelecek hafta")
        default: wk < 0 ? String(localized: "\(-wk) hafta önce") : String(localized: "\(wk) hafta sonra")
        }
    }
}

// MARK: - Exercise row

struct WkExRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    var e: Exercise
    var label: String
    var edit: Bool
    var dc: Int
    var onOpen: () -> Void
    var onCheck: (() -> Void)?
    var onDel: (() -> Void)?
    /// Drag handle (two lines) in edit mode, left of the image
    var handle: WkHandle? = nil

    var body: some View {
        let full = dc >= e.sets
        HStack(spacing: 12) {
            if edit, let handle {
                handle.padding(.leading, -4).padding(.trailing, -6)
            } else if !edit {
                Text(label).font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg).lineLimit(1).minimumScaleFactor(0.6).frame(width: 24, alignment: .leading)
            }
            WkThumb(name: e.name, size: edit ? 44 : 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).font(.bDisplay(16, relativeTo: .body)).lineLimit(edit ? 1 : 3)
                    .foregroundStyle(full && !edit ? Color.bMutedFg : Color.bFg)
                    .animation(.snappy(duration: 0.3).delay(0.12), value: full)
                Text(Wk.meta(e)).font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg).lineLimit(1)
                if !e.note.isEmpty && !edit { Text(e.note).font(.bXs).italic().foregroundStyle(Color.bMutedFg).padding(.top, 2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if edit {
                if let onDel {
                    Button(action: onDel) { Ti("trash", size: 20) }.buttonStyle(.b(.ghost, .iconLarge)).bButtonFg(Color.bDestructive)
                        .accessibilityLabel("\(e.name) sil")
                }
                Ti("chevron-right").foregroundStyle(Color.bMutedFg)
            } else {
                Button { onCheck?() } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(full ? Color.bSuccess : .clear)
                        if !full { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.bInput, lineWidth: 1) }
                        if full { Ti("check", size: 16).foregroundStyle(.white).transition(.scale(scale: 0.3).combined(with: .opacity)) }
                    }
                    .frame(width: 24, height: 24)
                    // when checked it first shrinks in, then settles overshooting by 15%
                    .keyframeAnimator(initialValue: 1.0, trigger: full) { v, k in v.scaleEffect(k) } keyframes: { _ in
                        CubicKeyframe(full && !reduce ? 0.86 : 1.0, duration: 0.08)
                        SpringKeyframe(1.0, duration: 0.3, spring: Spring(response: 0.28, dampingRatio: 0.55))
                    }
                    .frame(width: 44, height: 44)
                    .animation(.spring(response: 0.28, dampingFraction: 0.6), value: full)
                    .sensoryFeedback(.success, trigger: full) { _, new in new }
                }
                .buttonStyle(.press)
                .disabled(onCheck == nil).opacity(onCheck == nil ? 0.4 : 1)
                .padding(.vertical, -8).padding(.trailing, -8)
                .accessibilityLabel("\(e.name) yapıldı").accessibilityValue(full ? "işaretli" : "işaretsiz")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, edit ? 8 : 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityAction(named: "Aç", onOpen)
    }
}

/// Program blocks: a single card or a superset card with a full outline
struct WkBlockList: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    var prog: WorkoutProgram
    var edit: Bool
    var date: String?
    var future = false
    @Binding var route: WkSheet?

    var body: some View {
        let blocks = prog.blocks
        let day = date.flatMap { Store.day(ctx, $0, create: false) }
        let visible = WkVis.make(blocks, edit: edit)
        WkReorderList(items: visible, spacing: 12, enabled: edit, onCommit: reorderBlocks) { v, handle in
            let b = v.b, no = v.no
            if b.kind == .single, let e = b.ex {
                WkListCard {
                    row(e, label: "#\(no)", day: day, onDel: edit ? { delBlock(b) } : nil, handle: edit ? handle : nil)
                        // no swipe to delete in view mode: the exercise is deleted from the program in edit mode
                }
            } else {
                superset(b, no: no, day: day, handle: edit ? handle : nil)
            }
        }
    }

    private func row(_ e: Exercise, label: String, day: DayLog?, onDel: (() -> Void)?, handle: WkHandle?) -> some View {
        WkExRow(e: e, label: label, edit: edit, dc: exDoneCount(e, day: day),
                onOpen: { route = edit ? .exForm(pid: prog.pid, eid: e.id, bid: nil, preset: nil) : .exercise(pid: prog.pid, eid: e.id, date: date ?? DayKey.today) },
                onCheck: (future || date == nil) ? nil : { haptic(.medium); Wk.toggleExDone(ctx, date: date!, prog: prog, e: e) },
                onDel: onDel, handle: handle)
    }

    @ViewBuilder private func superset(_ b: Block, no: Int, day: DayLog?, handle: WkHandle?) -> some View {
        // a border only on meaningful blocks (warm-up/cool-down); a plain superset has none, like other cards
        let border: Color = b.tag == "warm" ? .bPrimary : b.tag == "cool" ? .bChart2 : .clear
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if edit, let handle { handle.padding(.leading, -4) }
                BBadge(variant: .secondary) { Text("Süperset") }
                if b.tag == "warm" { BBadge(variant: .soft) { Text("Isınma") } }
                if b.tag == "cool" { BBadge(variant: .outline) { Text("Soğuma") } }
                Text("\(b.rounds) tur · \(b.rest) sn dinlenme").font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg).lineLimit(1)
                Spacer(minLength: 0)
                if edit {
                    Button { route = .blockForm(pid: prog.pid, bid: b.id) } label: { Ti("pencil", size: 20) }.buttonStyle(.b(.ghost, .iconLarge)).accessibilityLabel("Süperseti düzenle")
                    Button { delBlock(b) } label: { Ti("trash", size: 20) }.buttonStyle(.b(.ghost, .iconLarge)).bButtonFg(Color.bDestructive).accessibilityLabel("Süperseti sil")
                }
            }
            .padding(.top, 12).padding(.horizontal, edit ? 8 : 16)
            if b.exs.isEmpty { Text("Henüz hareket yok. Aşağıdan ekle.").font(.bXs).foregroundStyle(Color.bMutedFg).padding(.horizontal, 16).padding(.top, 8) }
            if edit {
                // exercises inside a superset are reordered with the handle too
                WkReorderList(items: b.exs, spacing: 0, enabled: true, onCommit: { reorderEx(b, $0) }) { e, h in
                    row(e, label: "", day: day, onDel: { delEx(b, e) }, handle: h)
                        .background(Color.bCard)
                        .overlay(alignment: .top) { Rectangle().fill(Color.bBorder).frame(height: 1) }
                }
                .padding(.top, 4)
            } else {
                WkDivided {
                    ForEach(Array(b.exs.enumerated()), id: \.element.id) { k, e in
                        row(e, label: "\(no)\(String(UnicodeScalar(97 + k)!))", day: day, onDel: nil, handle: nil)

                    }
                }
                .padding(.top, 4)
            }
            if edit {
                Button { route = .exPicker(pid: prog.pid, bid: b.id, newFor: nil) } label: { BLabel("Süpersete hareket", icon: "plus") }
                    .buttonStyle(.b(.secondary)).padding(.horizontal, 16).padding(.bottom, 12)
            } else { Color.clear.frame(height: 4) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bCard, in: RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous).strokeBorder(border, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
    }

    // MARK: Editing (undoable delete)
    /// Written once on release (past days are protected by editBlocks)
    private func reorderBlocks(_ ids: [String]) {
        Wk.editBlocks(ctx, prog) { bl in
            let m = Dictionary(bl.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let moved = ids.compactMap { m[$0] }
            bl = moved + bl.filter { !ids.contains($0.id) }
        }
    }
    private func reorderEx(_ b: Block, _ ids: [String]) {
        Wk.editBlocks(ctx, prog) { bl in
            guard let i = bl.firstIndex(where: { $0.id == b.id }) else { return }
            let m = Dictionary(bl[i].exs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let moved = ids.compactMap { m[$0] }
            bl[i].exs = moved + bl[i].exs.filter { !ids.contains($0.id) }
        }
    }
    // undo only puts the deleted item back; other changes made in between are kept
    private func delBlock(_ b: Block) {
        guard let at = prog.blocks.firstIndex(where: { $0.id == b.id }) else { return }
        withAnimation { Wk.editBlocks(ctx, prog) { $0.removeAll { $0.id == b.id } } }
        app.toast(String(localized: "\(b.kind == .single ? b.ex?.name ?? tl("Hareket") : tl("Süperset")) silindi"), kind: .delete) {
            var bl = prog.blocks
            guard !bl.contains(where: { $0.id == b.id }) else { return }
            bl.insert(b, at: min(at, bl.count)); withAnimation { prog.blocks = bl }
        }
    }
    private func delEx(_ b: Block, _ e: Exercise) {
        guard let k = b.exs.firstIndex(where: { $0.id == e.id }) else { return }
        withAnimation { Wk.editBlocks(ctx, prog) { bl in if let i = bl.firstIndex(where: { $0.id == b.id }) { bl[i].exs.removeAll { $0.id == e.id } } } }
        app.toast(String(localized: "\(e.name) silindi"), kind: .delete) {
            var bl = prog.blocks
            guard let i = bl.firstIndex(where: { $0.id == b.id }), !bl[i].exs.contains(where: { $0.id == e.id }) else { return }
            bl[i].exs.insert(e, at: min(k, bl[i].exs.count)); withAnimation { prog.blocks = bl }
        }
    }
}

private struct WkVis: Identifiable {
    var no: Int; var bi: Int; var b: Block
    var id: String { b.id }
    static func make(_ blocks: [Block], edit: Bool) -> [WkVis] {
        var out: [WkVis] = []
        for (i, b) in blocks.enumerated() where !(b.kind == .superset && b.exs.isEmpty && !edit) { out.append(WkVis(no: out.count + 1, bi: i, b: b)) }
        return out
    }
}

/// "Her pazartesi tekrarla"
struct WkRepeatToggle: View {
    var date: String
    @Binding var value: Bool
    var body: some View {
        if date >= DayKey.today {
            Button { haptic(); value.toggle() } label: {
                HStack(spacing: 10) {
                    BCheck(checked: value)
                    Text("Her \(Wk.lower(DayKey.dayLong[DayKey.weekday(date)])) tekrarla").font(.bSm).foregroundStyle(Color.bFg)
                    Spacer()
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(value ? [.isSelected] : [])
        }
    }
}

/// Number input (text ↔ number)
struct WkNumField: View {
    var placeholder: String = ""
    @Binding var text: String
    var decimal = false
    var center = false
    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .multilineTextAlignment(center ? .center : .leading)
            .textFieldStyle(.b)
            .onChange(of: text) { _, v in
                // only the first decimal separator stays ("62,5," → "62,5")
                var seen = false
                let f = decimal ? String(v.filter { ch in
                    if ch == "," || ch == "." { defer { seen = true }; return !seen }
                    return ch.isNumber
                }) : v.filter(\.isNumber)
                if f != v { text = f }
            }
    }
}

func wkNum(_ s: String) -> Double { trNum(s) }
func wkClamp(_ s: String, _ lo: Int, _ hi: Int) -> Int { min(hi, max(lo, Int(wkNum(s).rounded()))) }

/// Strength level badge
struct WkLevelChip: View {
    var idx: Int
    var body: some View {
        let tones: [(Color, Color)] = [(.bMuted, .bFg), (Color.bChart2.opacity(0.15), .bFg), (Color.bPrimary.opacity(0.12), .bFg), (Color.bPrimary.opacity(0.25), .bFg), (.bPrimary, .bPrimaryFg)]
        let t = tones[max(0, min(4, idx))]
        Text(idx < 0 ? "Başlangıç altı" : WkProgress.levels[min(4, idx)]).font(.geist(12, .semibold, relativeTo: .caption))
            .padding(.horizontal, 10).frame(height: 24).background(t.0, in: Capsule()).foregroundStyle(t.1).fixedSize()
    }
}


// MARK: - Drag to reorder

/// Two-line handle: vertical drag reorders; up/down actions for VoiceOver
struct WkHandle: View {
    var onChange: (CGFloat) -> Void
    var onEnd: () -> Void
    var onStep: (Int) -> Void
    /// The finger's vertical position on screen: the list scrolls on its own near the edges
    var onLocation: (CGFloat) -> Void = { _ in }
    /// A cancelled drag (call, system gesture) never gets onEnded; the GestureState resets itself
    @GestureState private var active = false
    var body: some View {
        // the two lines are drawn by hand (crisp in every theme)
        VStack(spacing: 5) {
            Capsule().frame(width: 20, height: 2.5)
            Capsule().frame(width: 20, height: 2.5)
        }
            .foregroundStyle(Color.bFg.opacity(active ? 0.9 : 0.55))
            .frame(width: 40, height: 48).contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($active) { _, st, _ in st = true }
                    .onChanged { onChange($0.translation.height); onLocation($0.location.y) }
                    .onEnded { _ in onEnd() }
            )
            .onChange(of: active) { _, a in if !a { onEnd() } }
            .accessibilityElement()
            .accessibilityLabel("Sırala")
            .accessibilityHint("Sürükleyerek taşı")
            .accessibilityAction(named: "Yukarı taşı") { onStep(-1) }
            .accessibilityAction(named: "Aşağı taşı") { onStep(1) }
    }
}

private struct WkHeightKey: PreferenceKey {
    static var defaultValue: [AnyHashable: CGFloat] { [:] }
    static func reduce(value: inout [AnyHashable: CGFloat], nextValue: () -> [AnyHashable: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// List reordered live with a handle. The dragged row grows slightly with a shadow, the others slide;
/// a haptic on every swap. The order is written once on release via `onCommit`.
struct WkReorderList<Item: Identifiable, Row: View>: View where Item.ID: Hashable {
    let items: [Item]
    var spacing: CGFloat
    var enabled: Bool
    var onCommit: ([Item.ID]) -> Void
    var row: (Item, WkHandle) -> Row

    init(items: [Item], spacing: CGFloat = 12, enabled: Bool = true, onCommit: @escaping ([Item.ID]) -> Void,
         @ViewBuilder row: @escaping (Item, WkHandle) -> Row) {
        self.items = items; self.spacing = spacing; self.enabled = enabled; self.onCommit = onCommit; self.row = row
    }

    @State private var order: [Item.ID]?
    @State private var dragging: Item.ID?
    @State private var translation: CGFloat = 0
    @State private var consumed: CGFloat = 0
    @State private var heights: [AnyHashable: CGFloat] = [:]
    /// Auto-scroll at the screen edge: an exercise can be moved to the very top/bottom of a long list
    @State private var fingerY: CGFloat = 0
    @State private var autoTask: Task<Void, Never>?
    @State private var proxy: ScrollViewProxy?

    private let swapAnim = Animation.spring(response: 0.32, dampingFraction: 0.82)
    private static var screenH: CGFloat {
        (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene)?.screen.bounds.height ?? 844
    }
    private static var edge: CGFloat { 140 }

    var body: some View {
        ScrollViewReader { reader in
            content.onAppear { proxy = reader }
        }
    }

    @ViewBuilder private var content: some View {
        let ids = order ?? items.map(\.id)
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        VStack(spacing: spacing) {
            ForEach(ids, id: \.self) { id in
                if let it = byId[id] {
                    let isDrag = dragging == id
                    row(it, handle(for: id, ids: ids))
                        .background(GeometryReader { g in
                            Color.clear.preference(key: WkHeightKey.self, value: [AnyHashable(id): g.size.height])
                        })
                        .scaleEffect(isDrag ? 1.02 : 1)
                        .shadow(color: .black.opacity(isDrag ? 0.18 : 0), radius: isDrag ? 14 : 0, y: isDrag ? 8 : 0)
                        .offset(y: isDrag ? translation - consumed : 0)
                        .zIndex(isDrag ? 1 : 0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDrag)
                        .id(id)
                }
            }
        }
        .onPreferenceChange(WkHeightKey.self) { heights = $0 }
        // clear a stuck drag if the list changes from outside or editing ends
        .onChange(of: items.map(\.id)) { _, _ in if dragging == nil { order = nil } }
        .onChange(of: enabled) { _, _ in autoTask?.cancel(); autoTask = nil; translation = 0; consumed = 0; dragging = nil; order = nil }
    }

    private func handle(for id: Item.ID, ids: [Item.ID]) -> WkHandle {
        WkHandle(
            onChange: { t in drag(id, t, ids) },
            onEnd: { end() },
            onStep: { d in step(id, d, ids) },
            onLocation: { y in fingerY = y; autoScrollIfNeeded() }
        )
    }

    /// With the finger at the top/bottom edge: the row moves one step per tick and the list scrolls just enough to keep it visible
    private var edgeDir: Int {
        if fingerY < Self.edge { return -1 }
        if fingerY > Self.screenH - Self.edge { return 1 }
        return 0
    }

    private func autoScrollIfNeeded() {
        guard enabled, dragging != nil, autoTask == nil, edgeDir != 0 else { return }
        autoTask = Task { @MainActor in
            while !Task.isCancelled, dragging != nil, edgeDir != 0 {
                autoStep(edgeDir)
                try? await Task.sleep(for: .milliseconds(230))
            }
            autoTask = nil
        }
    }

    private func autoStep(_ d: Int) {
        guard let id = dragging, var o = order, let i = o.firstIndex(of: id) else { return }
        let j = i + d
        guard j >= 0, j < o.count else { return }
        o.swapAt(i, j)
        withAnimation(swapAnim) { order = o }
        // the row settles into its new slot; the drag continues from here when the finger moves again
        consumed = translation
        UISelectionFeedbackGenerator().selectionChanged()
        let y = min(0.85, max(0.15, fingerY / Self.screenH))
        withAnimation(.easeOut(duration: 0.2)) { proxy?.scrollTo(id, anchor: UnitPoint(x: 0.5, y: y)) }
    }

    private func drag(_ id: Item.ID, _ t: CGFloat, _ ids: [Item.ID]) {
        guard enabled else { return }
        if dragging == nil {
            order = ids; consumed = 0; translation = 0
            dragging = id
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        translation = t
        guard var o = order, let i = o.firstIndex(of: id) else { return }
        let shift = translation - consumed
        if shift > 0, i + 1 < o.count {
            let h = (heights[AnyHashable(o[i + 1])] ?? 64) + spacing
            if shift > h / 2 {
                o.swapAt(i, i + 1)
                withAnimation(swapAnim) { order = o; consumed += h }
                UISelectionFeedbackGenerator().selectionChanged()
            }
        } else if shift < 0, i > 0 {
            let h = (heights[AnyHashable(o[i - 1])] ?? 64) + spacing
            if -shift > h / 2 {
                o.swapAt(i, i - 1)
                withAnimation(swapAnim) { order = o; consumed -= h }
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    private func end() {
        autoTask?.cancel(); autoTask = nil
        guard dragging != nil else { return }
        let final = order
        if let final, final != items.map(\.id) { onCommit(final) }
        withAnimation(swapAnim) {
            translation = 0; consumed = 0; dragging = nil; order = nil
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Accessibility: one step up/down
    private func step(_ id: Item.ID, _ d: Int, _ ids: [Item.ID]) {
        var o = ids
        guard let i = o.firstIndex(of: id) else { return }
        let j = i + d
        guard j >= 0, j < o.count else { return }
        o.swapAt(i, j)
        withAnimation(swapAnim) { onCommit(o) }
    }
}

// MARK: - Week circles (1.2): done = green check, selected = filled, planned = muted, rest = outline

struct WkWeekCircles: View {
    @Binding var value: Int
    var todayIndex: Int
    var status: (Int) -> WkDayState
    var body: some View {
        // same day rings as Nutrition: done = green ring, workout day = ring, rest = faint
        NutDayRings(selected: $value, wk: wk, todayIndex: todayIndex, allowFuture: true, status: { i in
            switch status(i) { case .done: .onTarget; case .todo: .empty; case .rest: .rest }
        }, value: { i in
            switch status(i) { case .done: tl("Tamamlandı"); case .todo: tl("Antrenman var"); case .rest: tl("Dinlenme") }
        })
    }
    @Environment(\.wkWeekOffset) private var wk
    private func dayNo(_ i: Int) -> String { String(Int(Wk.weekDate(i, wk).suffix(2)) ?? 0) }
}

private struct WkWeekOffsetKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    var wkWeekOffset: Int { get { self[WkWeekOffsetKey.self] } set { self[WkWeekOffsetKey.self] = newValue } }
}
