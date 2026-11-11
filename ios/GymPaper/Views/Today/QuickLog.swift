import SwiftUI
import SwiftData
import GymPaperKit

/// Quick log: opened from the separate + button next to the tab bar (Figma "Today · Quick log").
/// Logging only; workouts start from Today and the Workout tab.
struct QuickLogSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    private struct Item: Identifiable {
        let id: String; let title: String; let icon: String; let run: () -> Void
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hızlı kayıt").font(.bDisplay(22, relativeTo: .title2)).foregroundStyle(Color.bFg)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(items) { it in
                    Button { haptic(); it.run() } label: { tile(it) }.buttonStyle(.press)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.bCard.ignoresSafeArea())
        .presentationDetents([.height(300), .large])
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
    }

    private func tile(_ it: Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Ti(it.icon, size: 22)
            Spacer(minLength: 12)
            Text(tl(it.title)).font(.geist(14, .medium, relativeTo: .subheadline)).multilineTextAlignment(.leading)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.bFg)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(Color.bMuted, in: RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous))
    }

    private var items: [Item] {
        [
            Item(id: "food", title: "Yemek", icon: "tools-kitchen-2") { app.open(.addFood(date: DayKey.today, meal: nil)) },
            Item(id: "water", title: "Su +250 ml", icon: "droplet") { addWater() },
            Item(id: "weight", title: "Kilo", icon: "scale") { app.open(.measure(quick: true)) },
            Item(id: "type", title: "Yazarak gir", icon: "pencil") { app.open(.cheat(date: DayKey.today)) },
            Item(id: "measure", title: "Ölçüm", icon: "ruler") { app.open(.measure(quick: false)) },
        ]
    }

    private func addWater() {
        guard let day = Store.day(ctx, DayKey.today) else { return }
        day.waterMl = min(20_000, day.waterMl + 250)
        Store.save(ctx)
        dismiss()
        app.toast(String(localized: "Su eklendi · \(fmt1(Double(day.waterMl) / 1000)) L"))
    }
}
