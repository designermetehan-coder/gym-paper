import WidgetKit
import SwiftUI
import AppIntents

@main
struct GymPaperWidgetsBundle: WidgetBundle {
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

/// Control Center / Lock Screen control: start workout (iOS 18)
struct StartWorkoutControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "gympaper.control.antrenman") {
            ControlWidgetButton(action: StartWorkoutIntent()) {
                Label("Antrenmanı başlat", systemImage: "dumbbell.fill")
            }
        }
        .displayName("Antrenmanı başlat")
        .description("GYM Paper'ı açar ve bugünün antrenmanını başlatır.")
    }
}
