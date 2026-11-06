import WidgetKit
import SwiftUI
import AppIntents

@main
struct BalliWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CalorieWidget()
        WaterWidget()
        WorkoutWidget()
        RingsWidget()
        StepsWidget()
        WeekWidget()
        SessionLiveActivity()
        FastingWidget()
        FastLiveActivity()
        StartWorkoutControl()
    }
}

/// Denetim Merkezi / kilit ekranı denetimi: antrenmanı başlat (iOS 18; hedef zaten iOS 18+) (TE-12)
struct StartWorkoutControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "balli.control.antrenman") {
            ControlWidgetButton(action: StartWorkoutIntent()) {
                Label("Antrenmanı başlat", systemImage: "dumbbell.fill")
            }
        }
        .displayName("Antrenmanı başlat")
        .description("GYM Paper'ı açar ve bugünün antrenmanını başlatır.")
    }
}
