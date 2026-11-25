import Foundation
import UserNotifications
import Shared

/// Two kinds of local reminders, rebuilt from current data whenever it changes or the app opens:
/// - Food at the deadline (16:30): tonight's meal and what's still missing
/// - Habits in the evening: only the ones still open, each with its own "done" button
enum Reminders {
    static let prefix = "r."
    static let donePrefix = "done."
    static let daysAhead = 7

    static func refresh(_ data: AppData, requestPermission: Bool) {
        let center = UNUserNotificationCenter.current()
        let anyOn = data.settings.remindHabits || data.settings.remindFood
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                guard anyOn, requestPermission else { return }
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { replace(data) }
                }
            case .denied:
                return
            default:
                replace(data)
            }
        }
    }

    private static func replace(_ data: AppData) {
        let center = UNUserNotificationCenter.current()
        let (requests, categories) = build(data, now: Date())
        center.setNotificationCategories(categories)
        center.getPendingNotificationRequests { pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for request in requests {
                center.add(request)
            }
        }
    }

    static func build(_ data: AppData, now: Date) -> ([UNNotificationRequest], Set<UNNotificationCategory>) {
        let cal = DayKey.calendar
        let s = data.settings
        let today = cal.startOfDay(for: now)
        var requests: [UNNotificationRequest] = []
        var categories: Set<UNNotificationCategory> = []

        func at(_ day: Date, _ minutes: Int) -> Date {
            cal.date(byAdding: .minute, value: minutes, to: day) ?? day
        }

        func add(_ id: String, _ title: String, _ body: String, _ date: Date, info: [String: String], category: String? = nil) {
            guard date > now else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = info
            if let category { content.categoryIdentifier = category }
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            requests.append(UNNotificationRequest(identifier: prefix + id, content: content, trigger: trigger))
        }

        for offset in 0..<daysAhead {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let key = DayKey.key(day)

            // Food at the deadline
            if s.remindFood, let pick = data.pick(for: day) {
                let missing = data.missing(on: day)
                let title = pick.leftover ? "Leftovers tonight: \(pick.meal.name)" : pick.auto ? "Picked for you: \(pick.meal.name)" : "Tonight: \(pick.meal.name)"
                let need = missing.isEmpty ? "You have everything." : "Still to buy: \(missing.joined(separator: ", "))."
                let body = pick.leftover ? "Nothing to buy or cook, just heat it up." : "\(pick.meal.minutes) min\(pick.servings == 2 ? ", for 2" : ""). \(need)"
                if !pick.cooked {
                    add("food.\(key)", title, body, at(day, s.foodDeadlineMinutes),
                        info: ["tab": AppTab.food.rawValue, "day": key])
                }
            }

            // Habits still open, with a button for each (iOS shows up to four)
            if s.remindHabits {
                let open = data.habits.filter { $0.isScheduled(on: day) && !$0.isDone(on: day) }
                if !open.isEmpty {
                    let categoryID = "habits.\(key)"
                    let actions = open.prefix(4).map {
                        UNNotificationAction(identifier: donePrefix + $0.id, title: "\($0.name) done", options: [])
                    }
                    categories.insert(UNNotificationCategory(identifier: categoryID, actions: actions, intentIdentifiers: [], options: []))
                    let title = open.count == 1 ? "\(open[0].name) is still open" : "\(open.count) habits still open"
                    let streaks = open.map { h -> String in
                        let st = h.streak(asOf: day).days
                        return st > 1 ? "\(h.name) (\(st)-day streak)" : h.name
                    }
                    add("habits.\(key)", title, streaks.joined(separator: ", ") + ". Hold to tick off.",
                        at(day, s.habitNudgeMinutes), info: ["tab": AppTab.habits.rawValue, "day": key], category: categoryID)
                }
            }
        }
        return (requests, categories)
    }
}
