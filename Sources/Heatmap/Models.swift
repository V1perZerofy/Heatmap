import SwiftUI
import ActivityKit
import UserNotifications
import Shared

enum AppTab: String {
    case habits, food, day, lists
}

/// Which tab is open and whether the focus timer is showing. Notifications can switch tabs.
final class Router: ObservableObject {
    static let shared = Router()
    @Published var tab: AppTab = .habits
    @Published var showTimer = false
}

@MainActor
final class AppModel: ObservableObject {
    @Published var data: AppData {
        didSet {
            Store.save(data)
            scheduleSideEffects()
        }
    }

    private var pending: DispatchWorkItem?
    private var observer: NSObjectProtocol?

    init() {
        var loaded = Store.load() ?? AppData.defaults
        loaded.migrate()
        loaded.ensureAutoPicks()
        loaded.tidyReminders()
        Store.save(loaded)
        data = loaded
        observer = NotificationCenter.default.addObserver(forName: .heatmapDataChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reloadFromDisk() }
        }
    }

    /// Picks up changes made by notification buttons, and fills in tonight's meal for a new day.
    func reloadFromDisk() {
        var d = Store.load() ?? data
        d.migrate()
        d.ensureAutoPicks()
        d.tidyReminders()
        data = d
    }

    /// Widget reloads and reminder rescheduling are batched, so typing doesn't trigger them per key.
    private func scheduleSideEffects() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Store.reloadWidgets()
            Scheduler.refresh(self.data, requestPermission: false)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func refreshReminders(requestPermission: Bool) {
        Scheduler.refresh(data, requestPermission: requestPermission)
    }

    // MARK: Habits

    func habit(_ id: String) -> Habit? { data.habits.first { $0.id == id } }

    func setMinutes(_ id: String, day: Date, minutes: Int?) {
        guard let i = data.habits.firstIndex(where: { $0.id == id }) else { return }
        let key = DayKey.key(day)
        if let minutes {
            data.habits[i].log[key] = max(0, min(1440, minutes))
        } else {
            data.habits[i].log.removeValue(forKey: key)
        }
    }

    func add(minutes: Int, to id: String) {
        let now = Date()
        let current = habit(id)?.minutes(on: now) ?? 0
        setMinutes(id, day: now, minutes: current + minutes)
    }

    /// Open -> done, done without minutes -> open. Returns false when minutes are logged,
    /// so the caller can open the day editor instead of wiping them.
    @discardableResult
    func toggleToday(_ id: String) -> Bool {
        let now = Date()
        switch habit(id)?.minutes(on: now) {
        case nil:
            setMinutes(id, day: now, minutes: 0)
            return true
        case 0?:
            setMinutes(id, day: now, minutes: nil)
            return true
        default:
            return false
        }
    }

    func upsert(_ habit: Habit) {
        if let i = data.habits.firstIndex(where: { $0.id == habit.id }) {
            data.habits[i] = habit
        } else {
            data.habits.append(habit)
        }
    }

    func delete(_ id: String) {
        data.habits.removeAll { $0.id == id }
    }

    // MARK: Food

    func choose(_ meal: Meal, for day: Date, servings: Int) {
        var d = data
        d.choose(meal, for: day, servings: servings)
        d.ensureAutoPicks()
        data = d
    }

    func saveMeal(_ meal: Meal) {
        if let i = data.meals.firstIndex(where: { $0.id == meal.id }) {
            data.meals[i] = meal
        } else {
            data.meals.append(meal)
        }
        var d = data
        d.ensureAutoPicks()
        data = d
    }

    func deleteMeal(_ id: String) {
        var d = data
        d.meals.removeAll { $0.id == id }
        d.picks = d.picks.filter { $0.value.mealID != id }
        d.ensureAutoPicks()
        data = d
    }
}

@MainActor
final class FocusTimer: ObservableObject {
    struct Session: Codable {
        var habitID: String
        var habitName: String
        var start: Date
        var accumulated: TimeInterval
        var running: Bool
        var targetMinutes: Int // 0 = open session
    }

    @Published private(set) var session: Session? {
        didSet { persist() }
    }

    private static let key = "focus-session"
    private let center = UNUserNotificationCenter.current()

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(Session.self, from: data) {
            session = s
        }
    }

    var elapsed: TimeInterval {
        guard let s = session else { return 0 }
        return s.accumulated + (s.running ? Date().timeIntervalSince(s.start) : 0)
    }

    func start(_ habit: Habit) {
        guard session == nil else { return }
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        session = Session(habitID: habit.id, habitName: habit.name, start: Date(), accumulated: 0, running: true, targetMinutes: 25)
        schedule()
        startActivity(habit)
    }

    func pause() {
        guard var s = session, s.running else { return }
        s.accumulated += Date().timeIntervalSince(s.start)
        s.running = false
        session = s
        schedule()
        updateActivity()
    }

    func resume() {
        guard var s = session, !s.running else { return }
        s.start = Date()
        s.running = true
        session = s
        schedule()
        updateActivity()
    }

    func setTarget(_ minutes: Int) {
        session?.targetMinutes = minutes
        schedule()
        updateActivity()
    }

    /// Returns what to log, or nil if the session was shorter than 30 seconds.
    func finish() -> (habitID: String, minutes: Int)? {
        let e = elapsed
        let id = session?.habitID
        discard()
        guard let id, e >= 30 else { return nil }
        return (id, max(1, Int((e / 60).rounded())))
    }

    func discard() {
        session = nil
        center.removePendingNotificationRequests(withIdentifiers: ["focus"])
        endActivities()
    }

    // MARK: Notification when the target is reached

    private func schedule() {
        center.removePendingNotificationRequests(withIdentifiers: ["focus"])
        guard let s = session, s.running, s.targetMinutes > 0 else { return }
        let remaining = Double(s.targetMinutes * 60) - elapsed
        guard remaining > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Focus session done"
        content.body = "\(s.targetMinutes) minutes of \(s.habitName). Open the app to log it."
        content.sound = .default
        content.userInfo = ["tab": AppTab.habits.rawValue]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
        center.add(UNNotificationRequest(identifier: "focus", content: content, trigger: trigger))
    }

    // MARK: Live Activity

    private var activityState: FocusAttributes.ContentState? {
        guard let s = session else { return nil }
        if s.running {
            return .init(start: s.start.addingTimeInterval(-s.accumulated), pausedElapsed: nil, targetMinutes: s.targetMinutes)
        }
        return .init(start: Date(), pausedElapsed: s.accumulated, targetMinutes: s.targetMinutes)
    }

    private func startActivity(_ habit: Habit) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let state = activityState else { return }
        endActivities()
        let attributes = FocusAttributes(habitName: habit.name, symbol: habit.symbol, colorIndex: habit.colorIndex)
        _ = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
    }

    private func updateActivity() {
        guard let state = activityState else { return }
        for activity in Activity<FocusAttributes>.activities {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        }
    }

    private func endActivities() {
        for activity in Activity<FocusAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// After a relaunch, put the lock screen timer back if a session is still going.
    func restoreActivity(habit: Habit?) {
        guard session != nil else {
            endActivities()
            return
        }
        if Activity<FocusAttributes>.activities.isEmpty, let habit {
            startActivity(habit)
        } else {
            updateActivity()
        }
    }

    private func persist() {
        if let s = session, let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Self.key)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.key)
        }
    }
}
