import Foundation
import SwiftUI
import WidgetKit

// MARK: - Habits

public struct Habit: Codable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var symbol: String
    public var colorIndex: Int
    /// "yyyy-MM-dd" -> minutes. A key with 0 minutes still counts as done.
    public var log: [String: Int]
    /// ISO weekdays (1 = Monday ... 7 = Sunday). Empty means every day.
    public var days: [Int]

    public init(id: String = UUID().uuidString, name: String, symbol: String, colorIndex: Int, log: [String: Int] = [:], days: [Int] = []) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorIndex = colorIndex
        self.log = log
        self.days = days
    }

    enum CodingKeys: String, CodingKey { case id, name, symbol, colorIndex, log, days }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Habit"
        symbol = (try? c.decodeIfPresent(String.self, forKey: .symbol)) ?? "star.fill"
        colorIndex = (try? c.decodeIfPresent(Int.self, forKey: .colorIndex)) ?? 0
        log = (try? c.decodeIfPresent([String: Int].self, forKey: .log)) ?? [:]
        days = (try? c.decodeIfPresent([Int].self, forKey: .days)) ?? []
    }

    public var color: Color { Palette.color(colorIndex) }

    public func minutes(on day: Date) -> Int? { log[DayKey.key(day)] }

    public func isDone(on day: Date) -> Bool { log[DayKey.key(day)] != nil }

    public func isScheduled(on day: Date) -> Bool {
        days.isEmpty || days.contains(DayKey.isoWeekday(day))
    }

    public func total(inYear year: Int) -> Int {
        let prefix = String(format: "%04d-", year)
        return log.reduce(0) { $1.key.hasPrefix(prefix) ? $0 + $1.value : $0 }
    }

    /// Days in a row. Unscheduled days are skipped, an unfinished today doesn't count against you,
    /// and one missed scheduled day per week is forgiven (a freeze).
    public func streak(asOf now: Date = Date()) -> StreakInfo {
        guard let earliest = log.keys.min() else { return StreakInfo(days: 0, freezeUsedThisWeek: false) }
        let cal = DayKey.calendar
        let today = cal.startOfDay(for: now)
        let thisWeek = DayKey.weekKey(today)
        var count = isDone(on: today) ? 1 : 0
        var frozenWeeks: Set<String> = []
        guard var day = cal.date(byAdding: .day, value: -1, to: today) else { return StreakInfo(days: count, freezeUsedThisWeek: false) }
        while DayKey.key(day) >= earliest {
            if isDone(on: day) {
                count += 1
            } else if isScheduled(on: day) {
                let week = DayKey.weekKey(day)
                if frozenWeeks.contains(week) { break }
                frozenWeeks.insert(week)
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return StreakInfo(days: count, freezeUsedThisWeek: count > 0 && frozenWeeks.contains(thisWeek))
    }

    /// Longest streak ever, by the same rules as `streak`: the longest stretch with at most one
    /// missed scheduled day per week, counting its done days.
    public func bestStreak(asOf now: Date = Date()) -> Int {
        guard let earliest = log.keys.min(), var day = DayKey.date(fromKey: earliest) else { return 0 }
        let cal = DayKey.calendar
        let today = cal.startOfDay(for: now)
        var doneBefore = [0] // done days before index i
        var lastMiss: [String: Int] = [:] // week -> index of its latest missed day
        var start = 0, best = 0, i = 0
        while day <= today {
            let done = isDone(on: day)
            doneBefore.append(doneBefore[i] + (done ? 1 : 0))
            if !done && isScheduled(on: day) && day < today {
                let week = DayKey.weekKey(day)
                // A second miss in the same week ends the stretch at the first one
                if let p = lastMiss[week], p >= start { start = p + 1 }
                lastMiss[week] = i
            }
            best = max(best, doneBefore[i + 1] - doneBefore[start])
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            i += 1
        }
        return best
    }

    public var scheduleText: String {
        if days.isEmpty || days.count == 7 { return "Every day" }
        return days.sorted().map { DayKey.shortNames[$0 - 1] }.joined(separator: ", ")
    }
}

public struct StreakInfo: Hashable {
    public let days: Int
    public let freezeUsedThisWeek: Bool
}

// MARK: - Food

/// Supermarket sections, in the order you walk through a typical German supermarket.
public enum Aisle: String, Codable, CaseIterable, Identifiable {
    case produce, bread, meat, fridge, dry, frozen, drinks, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .produce: return "Fruit and veg"
        case .bread: return "Bread"
        case .meat: return "Meat and fish"
        case .fridge: return "Fridge"
        case .dry: return "Pasta, rice, sauces"
        case .frozen: return "Frozen"
        case .drinks: return "Drinks"
        case .other: return "Other"
        }
    }

    /// Rough guess for ingredients that came without a section.
    public static func guess(_ name: String) -> Aisle {
        let n = name.lowercased()
        let table: [(Aisle, [String])] = [
            (.frozen, ["tk ", "tiefkühl", "frozen", "fischstäbchen", "pommes", "fries", "rahmspinat"]),
            (.bread, ["brötchen", "toast", "brot", "baguette", "wrap", "tortilla", "bagel"]),
            (.meat, ["bacon", "speck", "guanciale", "hähnchen", "chicken", "hack", "minced", "lachs", "salmon", "wurst", "würstchen", "schinken", "ham", "beef", "rind", "schnitzel", "leberkäse", "kasseler", "garnelen", "fisch"]),
            (.fridge, ["egg", "eier", "milk", "milch", "cheese", "käse", "pecorino", "parmesan", "gorgonzola", "butter", "joghurt", "yogurt", "sahne", "cream", "mozzarella", "feta", "quark", "kloßteig"]),
            (.dry, ["pasta", "spaghetti", "nudel", "penne", "fusilli", "trofie", "orecchiette", "reis", "rice", "pesto", "teriyaki", "müsli", "muesli", "sauce", "soße", "mehl", "flour", "oil", "öl", "dose", "glas", "beans", "bohnen", "senf", "curry", "kokosmilch", "brühe", "paniermehl", "mayonnaise", "püree", "apfelmus", "walnüsse", "röstzwiebeln", "ananas", "kirschen", "sauerkraut", "gurken"]),
            (.produce, ["zwiebel", "onion", "garlic", "knoblauch", "paprika", "pepper", "salat", "lettuce", "gurke", "cucumber", "apfel", "apple", "banana", "kartoffel", "potato", "karotte", "möhre", "carrot", "brokkoli", "broccoli", "zucchini", "spargel", "kürbis", "zitrone", "rosmarin", "suppengemüse", "erbsen", "bohnen grün", "grüne bohnen"]),
            (.drinks, ["saft", "juice", "wasser", "water", "cola", "bier", "beer"]),
        ]
        for (aisle, words) in table where words.contains(where: { n.contains($0) }) {
            return aisle
        }
        return .other
    }
}

public struct Ingredient: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var aisle: Aisle
    /// Amount for ONE portion, nil if not tracked
    public var amount: Double?
    /// "g", "ml", "Stk", "Scheiben", or a pack like "Glas", "Dose", "Pck", "Bund"
    public var unit: String

    public init(id: String = UUID().uuidString, name: String, aisle: Aisle? = nil, amount: Double? = nil, unit: String = "") {
        self.id = id
        self.name = name
        self.aisle = aisle ?? Aisle.guess(name)
        self.amount = amount
        self.unit = unit
    }

    enum CodingKeys: String, CodingKey { case id, name, aisle, amount, unit }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        aisle = (try? c.decodeIfPresent(Aisle.self, forKey: .aisle)) ?? Aisle.guess(name)
        amount = try? c.decodeIfPresent(Double.self, forKey: .amount)
        unit = (try? c.decodeIfPresent(String.self, forKey: .unit)) ?? ""
    }

    public func amountText(servings: Int) -> String {
        Amount.text(amount.map { $0 * Double(servings) }, unit: unit)
    }
}

/// Turns per-portion amounts into sensible shopping amounts.
public enum Amount {
    /// Units you buy as a whole pack, whatever the portion
    public static let packs: Set<String> = ["Glas", "Dose", "Pck", "Bund", "Knolle", "Topf", "Becher", "Flasche"]

    public static func text(_ value: Double?, unit: String) -> String {
        if packs.contains(unit) { return "1 \(unit)" }
        guard let v = value, v > 0 else { return "" }
        switch unit {
        case "g", "ml":
            let rounded = Int((v / 25).rounded(.up)) * 25
            if rounded >= 1000 && rounded % 100 == 0 {
                let big = Double(rounded) / 1000
                return String(format: big == big.rounded() ? "%.0f %@" : "%.1f %@", big, unit == "g" ? "kg" : "l")
            }
            return "\(max(25, rounded)) \(unit)"
        default:
            let n = Int(v.rounded(.up))
            return unit.isEmpty ? "\(n)" : "\(n) \(unit)"
        }
    }
}

public struct Meal: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var minutes: Int
    public var ingredients: [Ingredient]
    /// Last day you ate it ("yyyy-MM-dd"), used to bring back meals you haven't had in a while
    public var lastEaten: String?

    public init(id: String = UUID().uuidString, name: String, minutes: Int, ingredients: [Ingredient], lastEaten: String? = nil) {
        self.id = id
        self.name = name
        self.minutes = minutes
        self.ingredients = ingredients
        self.lastEaten = lastEaten
    }

    enum CodingKeys: String, CodingKey { case id, name, minutes, ingredients, lastEaten }

    /// Also reads meals from version 2, where ingredients were plain strings.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Meal"
        minutes = (try? c.decodeIfPresent(Int.self, forKey: .minutes)) ?? 20
        if let full = try? c.decodeIfPresent([Ingredient].self, forKey: .ingredients) {
            ingredients = full
        } else if let names = try? c.decodeIfPresent([String].self, forKey: .ingredients) {
            ingredients = names.map { Ingredient(name: $0) }
        } else {
            ingredients = []
        }
        lastEaten = try? c.decodeIfPresent(String.self, forKey: .lastEaten)
    }
}

public struct MealPick: Codable, Hashable {
    public var mealID: String
    /// Chosen by the app, not by you. It stays changeable.
    public var auto: Bool
    public var cooked: Bool
    /// 1, or 2 when you cook for tonight and tomorrow
    public var servings: Int
    /// Eating what's left from yesterday: nothing to buy or cook
    public var leftover: Bool

    public init(mealID: String, auto: Bool, cooked: Bool = false, servings: Int = 1, leftover: Bool = false) {
        self.mealID = mealID
        self.auto = auto
        self.cooked = cooked
        self.servings = servings
        self.leftover = leftover
    }

    enum CodingKeys: String, CodingKey { case mealID, auto, cooked, servings, leftover }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mealID = try c.decode(String.self, forKey: .mealID)
        auto = (try? c.decodeIfPresent(Bool.self, forKey: .auto)) ?? false
        cooked = (try? c.decodeIfPresent(Bool.self, forKey: .cooked)) ?? false
        servings = (try? c.decodeIfPresent(Int.self, forKey: .servings)) ?? 1
        leftover = (try? c.decodeIfPresent(Bool.self, forKey: .leftover)) ?? false
    }
}

/// Something you have at home.
public struct PantryItem: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var aisle: Aisle
    /// Salt, oil, spices: never on the shopping list, never used up
    public var always: Bool

    public init(id: String = UUID().uuidString, name: String, aisle: Aisle? = nil, always: Bool = false) {
        self.id = id
        self.name = name
        self.aisle = aisle ?? Aisle.guess(name)
        self.always = always
    }

    enum CodingKeys: String, CodingKey { case id, name, aisle, always }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        aisle = (try? c.decodeIfPresent(Aisle.self, forKey: .aisle)) ?? Aisle.guess(name)
        always = (try? c.decodeIfPresent(Bool.self, forKey: .always)) ?? false
    }
}

public struct ShoppingItem: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let aisle: Aisle
    /// How many meals need it
    public let count: Int
    /// "250 g", or "" when no amount is known
    public let amountText: String
}

// MARK: - Reminders and lists

public struct Reminder: Codable, Hashable, Identifiable {
    public var id: String
    public var title: String
    /// Time of day, minutes after midnight
    public var minutes: Int
    /// "yyyy-MM-dd" for a one-time reminder; nil repeats on `days`
    public var once: String?
    /// ISO weekdays for repeating reminders; empty means every day
    public var days: [Int]
    /// Adds tonight's meal to the notification
    public var aboutDinner: Bool
    /// Days it was ticked off
    public var doneDates: [String]

    public init(id: String = UUID().uuidString, title: String, minutes: Int, once: String? = nil, days: [Int] = [], aboutDinner: Bool = false, doneDates: [String] = []) {
        self.id = id
        self.title = title
        self.minutes = minutes
        self.once = once
        self.days = days
        self.aboutDinner = aboutDinner
        self.doneDates = doneDates
    }

    enum CodingKeys: String, CodingKey { case id, title, minutes, once, days, aboutDinner, doneDates }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? "Reminder"
        minutes = (try? c.decodeIfPresent(Int.self, forKey: .minutes)) ?? 9 * 60
        once = try? c.decodeIfPresent(String.self, forKey: .once)
        days = (try? c.decodeIfPresent([Int].self, forKey: .days)) ?? []
        aboutDinner = (try? c.decodeIfPresent(Bool.self, forKey: .aboutDinner)) ?? false
        doneDates = (try? c.decodeIfPresent([String].self, forKey: .doneDates)) ?? []
    }

    public func occurs(on day: Date) -> Bool {
        if let once { return once == DayKey.key(day) }
        return days.isEmpty || days.contains(DayKey.isoWeekday(day))
    }

    public func isDone(on day: Date) -> Bool { doneDates.contains(DayKey.key(day)) }

    public var repeatText: String {
        if let once, let d = DayKey.date(fromKey: once) {
            return d.formatted(.dateTime.weekday(.abbreviated).day().month())
        }
        if days.isEmpty || days.count == 7 { return "Every day" }
        if Set(days) == Set([1, 2, 3, 4, 5]) { return "Weekdays" }
        return days.sorted().map { DayKey.shortNames[$0 - 1] }.joined(separator: ", ")
    }
}

public struct ListItem: Codable, Hashable, Identifiable {
    public var id: String
    public var text: String
    public var done: Bool

    public init(id: String = UUID().uuidString, text: String, done: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
    }
}

public struct UserList: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var items: [ListItem]
    /// Packing-style lists you tick through again and again
    public var reusable: Bool

    public init(id: String = UUID().uuidString, name: String, items: [ListItem] = [], reusable: Bool = false) {
        self.id = id
        self.name = name
        self.items = items
        self.reusable = reusable
    }
}

/// Something you added to the shopping list by hand.
public struct ExtraItem: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var aisle: Aisle

    public init(id: String = UUID().uuidString, name: String, aisle: Aisle? = nil) {
        self.id = id
        self.name = name
        self.aisle = aisle ?? Aisle.guess(name)
    }
}

// MARK: - Settings

public struct AppSettings: Codable, Hashable {
    public var remindHabits: Bool
    public var habitNudgeMinutes: Int
    public var remindFood: Bool
    /// If tonight's meal isn't chosen by this time, the app's pick stays.
    public var foodDeadlineMinutes: Int
    /// Cooking time used for the app's own picks
    public var usualCookMinutes: Int

    public init() {
        remindHabits = true
        habitNudgeMinutes = 20 * 60
        remindFood = true
        foodDeadlineMinutes = 16 * 60 + 30
        usualCookMinutes = 30
    }

    enum CodingKeys: String, CodingKey {
        case remindHabits, habitNudgeMinutes, remindFood, foodDeadlineMinutes, usualCookMinutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        remindHabits = (try? c.decodeIfPresent(Bool.self, forKey: .remindHabits)) ?? d.remindHabits
        habitNudgeMinutes = (try? c.decodeIfPresent(Int.self, forKey: .habitNudgeMinutes)) ?? d.habitNudgeMinutes
        remindFood = (try? c.decodeIfPresent(Bool.self, forKey: .remindFood)) ?? d.remindFood
        foodDeadlineMinutes = (try? c.decodeIfPresent(Int.self, forKey: .foodDeadlineMinutes)) ?? d.foodDeadlineMinutes
        usualCookMinutes = (try? c.decodeIfPresent(Int.self, forKey: .usualCookMinutes)) ?? d.usualCookMinutes
    }
}

// MARK: - Everything the app stores

public struct AppData: Codable {
    public var version: Int
    public var habits: [Habit]
    public var meals: [Meal]
    /// day key -> that day's meal
    public var picks: [String: MealPick]
    /// What's at home right now
    public var pantry: [PantryItem]
    /// Added to the shopping list by hand
    public var extraShopping: [ExtraItem]
    public var reminders: [Reminder]
    public var lists: [UserList]
    public var settings: AppSettings

    public static let currentVersion = 5

    public static var defaults: AppData {
        AppData(
            version: currentVersion,
            habits: [
                Habit(name: "Coding", symbol: "chevron.left.forwardslash.chevron.right", colorIndex: 0),
                Habit(name: "Table tennis", symbol: "figure.table.tennis", colorIndex: 1, days: [1, 3, 4]),
                Habit(name: "Reading", symbol: "book", colorIndex: 2),
                Habit(name: "Danish", symbol: "character.bubble", colorIndex: 5),
            ],
            meals: StarterMeals.all + FamilyMeals.all,
            picks: [:],
            pantry: [],
            extraShopping: [],
            reminders: [Reminder(title: "Cook", minutes: 19 * 60, aboutDinner: true)],
            lists: [],
            settings: AppSettings()
        )
    }

    public init(version: Int, habits: [Habit], meals: [Meal], picks: [String: MealPick], pantry: [PantryItem],
                extraShopping: [ExtraItem], reminders: [Reminder], lists: [UserList], settings: AppSettings) {
        self.version = version
        self.habits = habits
        self.meals = meals
        self.picks = picks
        self.pantry = pantry
        self.extraShopping = extraShopping
        self.reminders = reminders
        self.lists = lists
        self.settings = settings
    }

    enum CodingKeys: String, CodingKey { case version, habits, meals, picks, pantry, extraShopping, reminders, lists, settings }

    /// Missing fields fall back to defaults, so files from older versions still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppData.defaults
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        version = value(.version, 1)
        habits = value(.habits, d.habits)
        meals = value(.meals, [])
        picks = value(.picks, [:])
        pantry = value(.pantry, [])
        extraShopping = value(.extraShopping, [])
        reminders = value(.reminders, [])
        lists = value(.lists, [])
        settings = value(.settings, d.settings)
    }

    /// Brings data from older versions up to date.
    public mutating func migrate() {
        guard version < AppData.currentVersion else { return }
        if version < 3 {
            if meals.isEmpty {
                meals = StarterMeals.all
            } else {
                for i in meals.indices {
                    if let known = StarterMeals.all.first(where: { $0.name == meals[i].name }) {
                        meals[i].minutes = known.minutes
                    }
                }
            }
            if !habits.contains(where: { $0.name.lowercased().contains("danish") || $0.name.lowercased().contains("dänisch") }) {
                habits.append(Habit(name: "Danish", symbol: "character.bubble", colorIndex: 5))
            }
            if let i = habits.firstIndex(where: { $0.name.lowercased().contains("table tennis") }), habits[i].days.isEmpty {
                habits[i].days = [1, 3, 4]
            }
        }
        if version < 4 {
            // The family recipes, added once; ones you already have by name are skipped
            let have = Set(meals.map { $0.name.lowercased() })
            meals += FamilyMeals.all.filter { !have.contains($0.name.lowercased()) }
        }
        if version < 5 {
            if !reminders.contains(where: { $0.title.lowercased() == "cook" }) {
                reminders.append(Reminder(title: "Cook", minutes: 19 * 60, aboutDinner: true))
            }
        }
        version = AppData.currentVersion
    }
}

// MARK: - Food helpers

public extension AppData {
    func meal(_ id: String) -> Meal? { meals.first { $0.id == id } }

    func pick(for day: Date) -> (meal: Meal, auto: Bool, cooked: Bool, servings: Int, leftover: Bool)? {
        guard let p = picks[DayKey.key(day)], let m = meal(p.mealID) else { return nil }
        return (m, p.auto, p.cooked, p.servings, p.leftover)
    }

    /// Meals planned within `days` of the given day, to avoid repeats.
    func nearbyMealIDs(around day: Date, days: Int = 3) -> Set<String> {
        let cal = DayKey.calendar
        var ids: Set<String> = []
        for offset in -days...days where offset != 0 {
            if let d = cal.date(byAdding: .day, value: offset, to: day), let p = picks[DayKey.key(d)] {
                ids.insert(p.mealID)
            }
        }
        return ids
    }

    /// A meal that fits the time. Prefers what you haven't eaten for longest (never eaten counts as longest),
    /// with a little randomness among the top few so it doesn't feel mechanical.
    func suggest(maxMinutes: Int?, for day: Date, excluding: Set<String> = []) -> Meal? {
        let fits = meals.filter { maxMinutes == nil || $0.minutes <= maxMinutes! }
        guard !fits.isEmpty else { return nil }
        let nearby = nearbyMealIDs(around: day)
        var pool = fits.filter { !nearby.contains($0.id) && !excluding.contains($0.id) }
        if pool.isEmpty { pool = fits.filter { !excluding.contains($0.id) } }
        if pool.isEmpty { pool = fits }
        let ranked = pool.sorted { ($0.lastEaten ?? "") < ($1.lastEaten ?? "") }
        return ranked.prefix(3).randomElement()
    }

    /// Records what was eaten, then fills today and the next two days with the app's picks.
    mutating func ensureAutoPicks(now: Date = Date()) {
        let cal = DayKey.calendar
        let today = cal.startOfDay(for: now)
        let todayKey = DayKey.key(today)

        // Past days count as eaten
        for (key, p) in picks where key < todayKey && !p.leftover {
            if let i = meals.firstIndex(where: { $0.id == p.mealID }), (meals[i].lastEaten ?? "") < key {
                meals[i].lastEaten = key
            }
        }

        for offset in 0..<3 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let key = DayKey.key(day)
            if let p = picks[key], meal(p.mealID) != nil { continue }
            if let m = suggest(maxMinutes: settings.usualCookMinutes, for: day) ?? suggest(maxMinutes: nil, for: day) {
                picks[key] = MealPick(mealID: m.id, auto: true)
            }
        }

        // Forget picks older than two weeks (lastEaten keeps the history)
        if let cutoff = cal.date(byAdding: .day, value: -14, to: today) {
            let old = DayKey.key(cutoff)
            picks = picks.filter { $0.key >= old }
        }
    }

    /// Your choice for a day. Cooking for two makes the next day leftovers.
    mutating func choose(_ meal: Meal, for day: Date, servings: Int) {
        let cal = DayKey.calendar
        let key = DayKey.key(day)
        let previous = picks[key]
        picks[key] = MealPick(mealID: meal.id, auto: false, servings: servings)
        guard let next = cal.date(byAdding: .day, value: 1, to: day) else { return }
        let nextKey = DayKey.key(next)
        let nextPick = picks[nextKey]
        if servings == 2 {
            // Leftovers replace the app's pick, but never something you chose yourself
            if nextPick == nil || nextPick!.auto || nextPick!.leftover {
                picks[nextKey] = MealPick(mealID: meal.id, auto: false, leftover: true)
            }
        } else if let prev = previous, prev.servings == 2, let np = nextPick, np.leftover {
            // No longer cooking for two: tomorrow is open again
            picks[nextKey] = nil
        }
    }

    /// What to buy for the meals of `days` days starting today, grouped and ordered by aisle.
    /// Leftover days need nothing, "always at home" items never show up.
    func shopping(days: Int, now: Date = Date()) -> [ShoppingItem] {
        let cal = DayKey.calendar
        let today = cal.startOfDay(for: now)
        struct Acc { var aisle: Aisle; var unit: String; var total: Double?; var count: Int }
        var order: [String] = []
        var acc: [String: Acc] = [:]
        for offset in 0..<days {
            guard let day = cal.date(byAdding: .day, value: offset, to: today), let p = pick(for: day), !p.leftover else { continue }
            for ing in p.meal.ingredients where !isAlwaysAtHome(ing.name) {
                let scaled = ing.amount.map { $0 * Double(p.servings) }
                if var e = acc[ing.name] {
                    e.count += 1
                    if e.unit == ing.unit, let t = e.total, let s = scaled {
                        e.total = Amount.packs.contains(ing.unit) ? t : t + s
                    } else if e.unit != ing.unit {
                        e.total = nil
                    }
                    acc[ing.name] = e
                } else {
                    order.append(ing.name)
                    acc[ing.name] = Acc(aisle: ing.aisle, unit: ing.unit, total: scaled, count: 1)
                }
            }
        }
        let items = order.compactMap { name -> ShoppingItem? in
            guard let e = acc[name] else { return nil }
            return ShoppingItem(name: name, aisle: e.aisle, count: e.count, amountText: Amount.text(e.total, unit: e.unit))
        }
        let aisleOrder = Aisle.allCases
        return items.sorted {
            (aisleOrder.firstIndex(of: $0.aisle) ?? 0, $0.name) < (aisleOrder.firstIndex(of: $1.aisle) ?? 0, $1.name)
        }
    }

    // MARK: Storage

    private static func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces).lowercased() }

    func hasAtHome(_ name: String) -> Bool {
        let n = AppData.norm(name)
        return pantry.contains { AppData.norm($0.name) == n }
    }

    func isAlwaysAtHome(_ name: String) -> Bool {
        let n = AppData.norm(name)
        return pantry.contains { $0.always && AppData.norm($0.name) == n }
    }

    mutating func addToPantry(_ name: String, aisle: Aisle? = nil, always: Bool = false) {
        let v = name.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty, !hasAtHome(v) else { return }
        pantry.append(PantryItem(name: v, aisle: aisle, always: always))
    }

    mutating func removeFromPantry(_ name: String) {
        let n = AppData.norm(name)
        pantry.removeAll { AppData.norm($0.name) == n }
    }

    mutating func toggleAlways(_ id: String) {
        if let i = pantry.firstIndex(where: { $0.id == id }) { pantry[i].always.toggle() }
    }

    /// Ticking a shopping item puts it in storage, unticking takes it out again.
    mutating func setAtHome(_ item: ShoppingItem, _ value: Bool) {
        if value { addToPantry(item.name, aisle: item.aisle) } else { removeFromPantry(item.name) }
    }

    /// Ingredients of that day's meal that aren't at home (with amounts when known)
    func missing(on day: Date) -> [String] {
        guard let p = pick(for: day), !p.leftover else { return [] }
        return p.meal.ingredients
            .filter { !hasAtHome($0.name) }
            .map { ing in
                let amount = ing.amountText(servings: p.servings)
                return amount.isEmpty ? ing.name : "\(ing.name) (\(amount))"
            }
    }

    /// Marks that day's meal as cooked and takes the used-up ingredients out of storage.
    mutating func markCooked(on day: Date, usedUp: [String]) {
        let key = DayKey.key(day)
        guard var p = picks[key] else { return }
        p.cooked = true
        picks[key] = p
        if let i = meals.firstIndex(where: { $0.id == p.mealID }) { meals[i].lastEaten = key }
        for name in usedUp where !isAlwaysAtHome(name) { removeFromPantry(name) }
    }
}

// MARK: - Reminder helpers

public extension AppData {
    func reminders(on day: Date) -> [Reminder] {
        reminders.filter { $0.occurs(on: day) }.sorted { $0.minutes < $1.minutes }
    }

    /// One-time reminders whose day has passed without being ticked off
    func missedReminders(now: Date = Date()) -> [Reminder] {
        let today = DayKey.key(now)
        return reminders
            .filter { r in
                guard let once = r.once else { return false }
                return once < today && !r.doneDates.contains(once)
            }
            .sorted { ($0.once ?? "") < ($1.once ?? "") }
    }

    mutating func setReminderDone(_ id: String, on day: Date, _ done: Bool) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        let key = DayKey.key(day)
        reminders[i].doneDates.removeAll { $0 == key }
        if done { reminders[i].doneDates.append(key) }
    }

    /// Drops ticks older than 30 days and finished one-time reminders older than a week.
    mutating func tidyReminders(now: Date = Date()) {
        let cal = DayKey.calendar
        guard let month = cal.date(byAdding: .day, value: -30, to: now),
              let week = cal.date(byAdding: .day, value: -7, to: now) else { return }
        let monthKey = DayKey.key(month), weekKey = DayKey.key(week)
        // Finished one-time reminders go first: once their tick is dropped they'd look missed
        reminders.removeAll { r in
            guard let once = r.once else { return false }
            return once < weekKey && r.doneDates.contains(once)
        }
        for i in reminders.indices {
            reminders[i].doneDates.removeAll { $0 < monthKey }
        }
    }
}

public enum StarterMeals {
    public static var all: [Meal] {
        func m(_ name: String, _ minutes: Int, _ items: [String]) -> Meal {
            Meal(name: name, minutes: minutes, ingredients: items.map { Ingredient(name: $0) })
        }
        return [
            m("Bacon, egg and cheese rolls", 15, ["Brötchen", "Bacon", "Eggs", "Cheese slices"]),
            m("Carbonara", 25, ["Spaghetti", "Guanciale or Speck", "Eggs", "Pecorino"]),
            m("Pasta with pesto", 15, ["Pasta", "Pesto", "Parmesan"]),
            m("Toast and scrambled eggs", 10, ["Toast", "Eggs", "Butter"]),
            m("Teriyaki Chicken", 30, ["Teriyaki", "Hähnchenbrust", "Reis"]),
            m("Müsli", 5, ["Müsli", "Milch"]),
        ]
    }
}

/// Dishes from the family meal plan that take 45 minutes or less, without tomatoes, spinach or mushrooms.
/// Amounts are written for four people as in the original and stored per portion.
public enum FamilyMeals {
    public static var all: [Meal] {
        func m(_ name: String, _ minutes: Int, _ items: [(String, Double, String)]) -> Meal {
            Meal(name: name, minutes: minutes, ingredients: items.map { name, forFour, unit in
                Ingredient(name: name, amount: Amount.packs.contains(unit) ? 1 : forFour / 4, unit: unit)
            })
        }
        return [
            m("Hot Dogs", 15, [("Wiener Würstchen", 8, "Stk"), ("Hot-Dog-Brötchen", 8, "Stk"), ("Röstzwiebeln", 1, "Pck"), ("Gewürzgurken", 1, "Glas")]),
            m("Hähnchencurry, Reis, Möhren", 40, [("Hähnchenbrust", 600, "g"), ("Möhren", 500, "g"), ("Kokosmilch", 1, "Dose"), ("Reis", 400, "g"), ("Currypaste", 1, "Glas")]),
            m("Paprika-Sahne-Hähnchen, Reis", 40, [("Hähnchenbrust", 600, "g"), ("Paprika", 3, "Stk"), ("Sahne", 200, "ml"), ("Reis", 400, "g")]),
            m("Nudelauflauf", 45, [("Penne", 500, "g"), ("Kochschinken", 200, "g"), ("Reibekäse", 200, "g"), ("Sahne", 200, "ml")]),
            m("Nudelsalat, Würstchen", 30, [("Fusilli", 500, "g"), ("Wiener Würstchen", 8, "Stk"), ("Gewürzgurken", 1, "Glas"), ("Mayonnaise", 1, "Glas"), ("Erbsen", 300, "g")]),
            m("Frikadellen, Kartoffeln, Möhren", 45, [("Hackfleisch", 600, "g"), ("Kartoffeln", 1000, "g"), ("Möhren", 500, "g"), ("Eier", 1, "Stk")]),
            m("Schnitzel, Kartoffeln, Brokkoli", 45, [("Schweineschnitzel", 4, "Stk"), ("Paniermehl", 1, "Pck"), ("Eier", 2, "Stk"), ("Kartoffeln", 1000, "g"), ("Brokkoli", 1, "Stk")]),
            m("Bratwurst, Kartoffeln, Möhren", 35, [("Frische Bratwurst", 6, "Stk"), ("Kartoffeln", 1000, "g"), ("Möhren", 500, "g")]),
            m("Leberkäse, Püree, Erbsen", 20, [("Leberkäse", 4, "Scheiben"), ("Kartoffelpüree", 1, "Pck"), ("Milch", 500, "ml"), ("Erbsen", 450, "g")]),
            m("Kasseler, Püree, Sauerkraut", 45, [("Kasseler", 800, "g"), ("Kartoffeln", 1000, "g"), ("Milch", 200, "ml"), ("Sauerkraut", 1, "Dose")]),
            m("Schnitzelchen, Püree, Erbsen", 30, [("Minutenschnitzel", 8, "Stk"), ("Kartoffeln", 1000, "g"), ("Milch", 200, "ml"), ("Erbsen", 450, "g")]),
            m("Hamburger, Pommes", 35, [("Rinderhack", 600, "g"), ("Burgerbrötchen", 4, "Stk"), ("Pommes", 750, "g"), ("Kopfsalat", 1, "Stk"), ("Käsescheiben", 200, "g")]),
            m("Toast Hawaii", 20, [("Toastbrot", 1, "Pck"), ("Kochschinken", 200, "g"), ("Ananas", 1, "Dose"), ("Käsescheiben", 200, "g")]),
            m("Chicken Alfredo", 30, [("Hähnchenbrust", 500, "g"), ("Bandnudeln", 500, "g"), ("Sahne", 200, "ml"), ("Parmesan", 100, "g"), ("Brokkoli", 1, "Stk")]),
            m("Eier in Senfsoße, Kartoffeln", 30, [("Eier", 8, "Stk"), ("Kartoffeln", 1000, "g"), ("Senf", 1, "Glas"), ("Sahne", 200, "ml")]),
            m("Spargel, Kartoffeln, Rührei", 40, [("Spargel weiß", 1500, "g"), ("Kartoffeln", 1000, "g"), ("Eier", 8, "Stk"), ("Butter", 1, "Becher")]),
            m("Fischstäbchen, Kartoffeln", 25, [("Fischstäbchen", 30, "Stk"), ("Kartoffeln", 1000, "g")]),
            m("Nudelsuppe, Baguette", 30, [("Hühnerbrühe", 1000, "ml"), ("Suppennudeln", 250, "g"), ("Suppengemüse", 1, "Bund"), ("Baguette", 4, "Stk")]),
            m("Nudel-Ei-Speckpfanne", 25, [("Bandnudeln", 500, "g"), ("Eier", 6, "Stk"), ("Speckwürfel", 1, "Pck")]),
            m("Spaghetti Gorgonzola", 20, [("Spaghetti", 500, "g"), ("Gorgonzola", 200, "g"), ("Sahne", 200, "ml"), ("Walnüsse", 50, "g")]),
            m("Orecchiette mit Kartoffeln", 35, [("Orecchiette", 500, "g"), ("Kartoffeln", 500, "g"), ("Parmesan", 100, "g")]),
            m("Bandnudeln mit Räucherlachs", 25, [("Bandnudeln", 500, "g"), ("Räucherlachs", 200, "g"), ("Sahne", 200, "ml"), ("Zitrone", 1, "Stk")]),
            m("Trofie mit Bohnen und Kartoffeln", 30, [("Trofie", 500, "g"), ("Grüne Bohnen", 400, "g"), ("Kartoffeln", 500, "g"), ("Pesto", 1, "Glas")]),
            m("Lachs, Reis, Salat", 30, [("Lachsfilet", 600, "g"), ("Reis", 400, "g"), ("Feldsalat", 200, "g")]),
            m("Milchreis, Kirschen", 35, [("Milchreis", 250, "g"), ("Milch", 1000, "ml"), ("Sauerkirschen", 1, "Glas")]),
            m("Püree, Rührei, Brokkoli", 30, [("Kartoffeln", 1000, "g"), ("Milch", 200, "ml"), ("Eier", 8, "Stk"), ("Brokkoli", 2, "Stk")]),
            m("Pfannkuchen", 30, [("Eier", 4, "Stk"), ("Milch", 1000, "ml"), ("Mehl", 500, "g"), ("Apfelmus", 1, "Glas")]),
            m("Reibekuchen, Apfelmus", 45, [("Kartoffeln", 1500, "g"), ("Eier", 3, "Stk"), ("Zwiebeln", 1, "Stk"), ("Apfelmus", 1, "Glas")]),
            m("Kürbissuppe, Baguette", 35, [("Hokkaido-Kürbis", 1, "Stk"), ("Zwiebeln", 2, "Stk"), ("Sahne", 200, "ml"), ("Baguette", 4, "Stk")]),
            m("Rosmarinkartoffeln, Brokkoli", 40, [("Kartoffeln", 1000, "g"), ("Brokkoli", 2, "Stk"), ("Rosmarin", 1, "Bund")]),
            m("Nudel-Brokkoli-Auflauf", 45, [("Penne", 500, "g"), ("Brokkoli", 2, "Stk"), ("Sahne", 200, "ml"), ("Reibekäse", 200, "g")]),
        ]
    }
}

public func formatMinutes(_ m: Int) -> String { "\(m / 60)h \(m % 60)m" }

// MARK: - Colours

public enum Palette {
    static let rgb: [(Double, Double, Double)] = [
        (0.50, 0.70, 1.00), // blue
        (0.62, 0.84, 0.60), // green
        (0.72, 0.64, 1.00), // purple
        (0.95, 0.79, 0.47), // amber
        (0.46, 0.84, 0.81), // teal
        (1.00, 0.62, 0.55), // coral
        (0.96, 0.60, 0.83), // pink
    ]

    public static var count: Int { rgb.count }

    public static func color(_ index: Int) -> Color {
        let c = rgb[((index % rgb.count) + rgb.count) % rgb.count]
        return Color(red: c.0, green: c.1, blue: c.2)
    }

    public static let flame = Color(red: 1.0, green: 0.54, blue: 0.24)
    public static let freeze = Color(red: 0.55, green: 0.80, blue: 1.0)
}

// MARK: - Days

public enum DayKey {
    public static let shortNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    public static let longNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        c.timeZone = .current
        return c
    }

    public static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func date(fromKey key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// 1 = Monday ... 7 = Sunday
    public static func isoWeekday(_ date: Date) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7 + 1
    }

    /// "2026-W48"
    public static func weekKey(_ date: Date) -> String {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = .current
        let c = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    /// Monday of the week the date is in
    public static func monday(of date: Date) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -(isoWeekday(start) - 1), to: start) ?? start
    }

    /// 0 = empty, 1...4 = increasing intensity
    public static func level(_ minutes: Int?) -> Int {
        guard let m = minutes else { return 0 }
        if m < 15 { return 1 }
        if m < 30 { return 2 }
        if m < 60 { return 3 }
        return 4
    }
}

// MARK: - Storage (shared with the widget through an App Group)

public enum Store {
    public static let baseID = "dev.nielsheiden.heatmap.data"

    /// xtool prefixes IDs with "XTL-<id>." when signing with a free Apple ID,
    /// so the real App Group ID is derived from our own bundle ID at runtime.
    public static var groupID: String {
        let first = (Bundle.main.bundleIdentifier ?? "").split(separator: ".").first.map(String.init) ?? ""
        return first.hasPrefix("XTL-") ? "group.\(first).\(baseID)" : "group.\(baseID)"
    }

    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("habits.json")
    }

    public static var fileURL: URL {
        if let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            return dir.appendingPathComponent("habits.json")
        }
        return documentsURL
    }

    private static func read(_ url: URL) -> AppData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppData.self, from: data)
    }

    public static func load() -> AppData? {
        if let d = read(fileURL) { return d }
        // Builds without the App Group saved into the app's own Documents folder
        if documentsURL != fileURL, let d = read(documentsURL) {
            save(d)
            return d
        }
        return nil
    }

    public static func save(_ appData: AppData) {
        if let data = try? JSONEncoder().encode(appData) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

public extension Notification.Name {
    /// Posted when data was changed outside the open screens (e.g. a notification button).
    static let heatmapDataChanged = Notification.Name("heatmapDataChanged")
}
