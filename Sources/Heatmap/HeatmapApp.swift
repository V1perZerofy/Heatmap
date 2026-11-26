import SwiftUI
import UserNotifications
import Shared

@main
struct HeatmapApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var timer = FocusTimer()
    @StateObject private var router = Router.shared
    @StateObject private var calendar = CalendarStore()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(timer)
                .environmentObject(router)
                .environmentObject(calendar)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var router: Router
    @EnvironmentObject var calendar: CalendarStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $router.tab) {
            HabitsView()
                .tabItem { Label("Habits", systemImage: "square.grid.3x3.fill") }
                .tag(AppTab.habits)
            FoodView()
                .tabItem { Label("Food", systemImage: "fork.knife") }
                .tag(AppTab.food)
            DayView()
                .tabItem { Label("Day", systemImage: "calendar") }
                .tag(AppTab.day)
            ListsView()
                .tabItem { Label("Lists", systemImage: "checklist") }
                .tag(AppTab.lists)
        }
        .tint(Palette.flame)
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $router.showTimer) {
            FocusView()
                .environmentObject(model)
                .environmentObject(timer)
                .fontDesign(.rounded)
                .preferredColorScheme(.dark)
        }
        .onAppear {
            if let s = timer.session {
                router.showTimer = true
                timer.restoreActivity(habit: model.habit(s.habitID))
            }
            model.refreshReminders(requestPermission: true)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // New day, or a notification button changed something while we were away
                model.reloadFromDisk()
                model.refreshReminders(requestPermission: false)
                calendar.reload()
                if timer.session != nil { router.showTimer = true }
            }
        }
    }
}

/// Shows banners while the app is open, handles the "done" buttons on reminders,
/// and opens the right tab when a reminder is tapped.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier

        if action == Scheduler.reminderLater {
            Scheduler.snooze(response.notification.request.content)
        } else if action == Scheduler.reminderDone, let id = info["reminder"] as? String,
                  let dayKey = info["day"] as? String, let day = DayKey.date(fromKey: dayKey) {
            if var data = Store.load() {
                data.setReminderDone(id, on: day, true)
                Store.save(data)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .heatmapDataChanged, object: nil)
                }
            }
        } else if action.hasPrefix(Scheduler.donePrefix), let day = info["day"] as? String {
            // Tick the habit off straight in the stored data; the app may not even be open
            let habitID = String(action.dropFirst(Scheduler.donePrefix.count))
            if var data = Store.load(), let i = data.habits.firstIndex(where: { $0.id == habitID }) {
                if data.habits[i].log[day] == nil { data.habits[i].log[day] = 0 }
                Store.save(data)
                Store.reloadWidgets()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .heatmapDataChanged, object: nil)
                }
            }
        } else if action == UNNotificationDefaultActionIdentifier,
                  let raw = info["tab"] as? String, let tab = AppTab(rawValue: raw) {
            DispatchQueue.main.async { Router.shared.tab = tab }
        }
        completionHandler()
    }
}
