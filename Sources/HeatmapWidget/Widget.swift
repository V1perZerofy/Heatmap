import WidgetKit
import SwiftUI
import ActivityKit
import Shared

@main
struct HeatmapWidgetBundle: WidgetBundle {
    var body: some Widget {
        HabitsWidget()
        FocusLiveActivity()
    }
}

// MARK: - Habits widget

struct DataEntry: TimelineEntry {
    let date: Date
    let data: AppData
}

struct DataProvider: TimelineProvider {
    func placeholder(in context: Context) -> DataEntry {
        DataEntry(date: Date(), data: AppData.defaults)
    }

    func getSnapshot(in context: Context, completion: @escaping (DataEntry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DataEntry>) -> Void) {
        // The app reloads widgets on every change; this covers the day rolling over.
        let cal = DayKey.calendar
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [current()], policy: .after(tomorrow)))
    }

    private func current() -> DataEntry {
        DataEntry(date: Date(), data: Store.load() ?? AppData.defaults)
    }
}

struct HabitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HabitsWidget", provider: DataProvider()) { entry in
            HabitsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Heatmap")
        .description("Your habits, streaks and the last months of practice.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct HabitsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DataEntry

    var body: some View {
        let shown = Array(entry.data.habits.prefix(family == .systemLarge ? 4 : 2))
        VStack(alignment: .leading, spacing: 8) {
            if shown.isEmpty {
                Text("Add a habit in the app").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(shown) { habit in
                let done = habit.isDone(on: entry.date)
                let streak = habit.streak(asOf: entry.date).days
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: habit.symbol).foregroundStyle(habit.color)
                        Text(habit.name).lineLimit(1)
                        Spacer(minLength: 4)
                        if streak > 0 {
                            Label("\(streak)", systemImage: "flame.fill").foregroundStyle(Palette.flame)
                        }
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(done ? habit.color : Color.secondary)
                    }
                    .font(.caption.weight(.semibold))

                    HeatmapView(habit: habit, grid: .recent(weeks: 40, now: entry.date), showLabels: false)
                }
            }
            Spacer(minLength: 0)
        }
        .fontDesign(.rounded)
    }
}

// MARK: - Focus timer on the lock screen and in the Dynamic Island

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusAttributes.self) { context in
            FocusLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let color = Palette.color(context.attributes.colorIndex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.habitName, systemImage: context.attributes.symbol)
                        .font(.headline)
                        .foregroundStyle(color)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FocusClock(state: context.state)
                        .font(.title2.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FocusProgress(state: context.state, color: color)
                }
            } compactLeading: {
                Image(systemName: context.attributes.symbol).foregroundStyle(color)
            } compactTrailing: {
                FocusClock(state: context.state)
                    .frame(maxWidth: 52)
                    .foregroundStyle(color)
            } minimal: {
                Image(systemName: context.attributes.symbol).foregroundStyle(color)
            }
        }
    }
}

struct FocusLockScreenView: View {
    let attributes: FocusAttributes
    let state: FocusAttributes.ContentState

    var body: some View {
        let color = Palette.color(attributes.colorIndex)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(attributes.habitName, systemImage: attributes.symbol)
                    .font(.headline)
                    .foregroundStyle(color)
                Spacer()
                Text(state.running ? (state.targetMinutes > 0 ? "Target \(state.targetMinutes) min" : "Open session") : "Paused")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            FocusClock(state: state)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            FocusProgress(state: state, color: color)
        }
        .padding(16)
        .fontDesign(.rounded)
    }
}

/// Counts up on its own while running, so the activity needs no updates.
struct FocusClock: View {
    let state: FocusAttributes.ContentState

    var body: some View {
        if let paused = state.pausedElapsed {
            let s = Int(paused)
            Text(s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60))
                .monospacedDigit()
        } else {
            Text(state.start, style: .timer)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

struct FocusProgress: View {
    let state: FocusAttributes.ContentState
    let color: Color

    var body: some View {
        if state.targetMinutes > 0 {
            let target = TimeInterval(state.targetMinutes * 60)
            if let paused = state.pausedElapsed {
                ProgressView(value: min(1, paused / target))
                    .tint(color)
            } else {
                ProgressView(timerInterval: state.start...state.start.addingTimeInterval(target), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(color)
            }
        }
    }
}
