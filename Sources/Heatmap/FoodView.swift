import SwiftUI
import Shared

struct DayChoice: Identifiable {
    let id = UUID()
    let day: Date
}

struct FoodView: View {
    @EnvironmentObject var model: AppModel
    @State private var chooserDay: DayChoice?
    @State private var shopDays = 1

    var body: some View {
        let now = Date()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TonightCard(now: now)
                    NextDaysCard(now: now) { chooserDay = DayChoice(day: $0) }
                    ShoppingCard(now: now, days: $shopDays)
                    NavigationLink { MealsList() } label: {
                        Card {
                            HStack {
                                Label("Your meals", systemImage: "list.bullet")
                                Spacer()
                                Text("\(model.data.meals.count)").foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    NavigationLink { StorageView() } label: {
                        Card {
                            HStack {
                                Label("Your storage", systemImage: "refrigerator")
                                Spacer()
                                Text("\(model.data.pantry.count)").foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 30)
            }
            .navigationTitle("Food")
            .sheet(item: $chooserDay) { c in
                NavigationStack {
                    ScrollView {
                        MealChooser(day: c.day) { chooserDay = nil }
                            .padding()
                    }
                    .navigationTitle(dayName(c.day, now: now))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { chooserDay = nil } }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

func dayName(_ day: Date, now: Date = Date()) -> String {
    let cal = DayKey.calendar
    if cal.isDate(day, inSameDayAs: now) { return "Tonight" }
    if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(day, inSameDayAs: t) { return "Tomorrow" }
    return DayKey.longNames[DayKey.isoWeekday(day) - 1]
}

// MARK: - Tonight

struct TonightCard: View {
    @EnvironmentObject var model: AppModel
    let now: Date
    @State private var changing = false
    @State private var cooking = false

    var body: some View {
        let deadline = model.data.settings.foodDeadlineMinutes
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        let pastDeadline = (c.hour ?? 0) * 60 + (c.minute ?? 0) >= deadline
        let pick = model.data.pick(for: now)

        Card {
            VStack(alignment: .leading, spacing: 12) {
                if model.data.meals.isEmpty {
                    Text("Tonight").font(.headline)
                    Text("Add a few meals you like under Your meals, then the app can pick for you.")
                        .foregroundStyle(.secondary)
                } else if let pick, (!pick.auto || pastDeadline), !changing {
                    // Decided: by you, or by the app after the deadline
                    Text(pick.auto ? "Tonight, picked for you" : "Tonight").font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    Text(pick.meal.name).font(.title2.weight(.bold))
                    if pick.leftover {
                        Text("Leftovers from yesterday. Just heat it up.").foregroundStyle(.secondary)
                    } else {
                        Text(pick.servings == 2 ? "\(pick.meal.minutes) min, cooking for 2 (tomorrow is leftovers)" : "\(pick.meal.minutes) min")
                            .foregroundStyle(.secondary)
                    }
                    if pick.leftover {
                        Button("Eat something else") { changing = true }
                            .glassButton()
                    } else if pick.cooked {
                        Label("Cooked", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Palette.flame)
                            .fontWeight(.semibold)
                    } else {
                        let missing = model.data.missing(on: now)
                        Text(missing.isEmpty ? "You have everything." : "Still to buy: \(missing.joined(separator: ", "))")
                            .font(.subheadline)
                            .foregroundStyle(missing.isEmpty ? Color.secondary : Palette.flame)
                        HStack {
                            Button("Change") { changing = true }
                                .glassButton()
                            Spacer()
                            Button("Cooked") { cooking = true }
                                .glassButton(prominent: true)
                        }
                    }
                } else {
                    // Not decided yet: choose by time, with the app's pick as the fallback
                    if let pick, !changing {
                        Text("Tonight").font(.headline)
                        Text("Decide by \(formatTime(deadline)). If you don't, it's \(pick.meal.name).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    MealChooser(day: now) { changing = false }
                    if changing {
                        Button("Keep \(pick?.meal.name ?? "it")") { changing = false }
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $cooking) {
            if let pick {
                CookedSheet(day: now, meal: pick.meal)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

/// After cooking: what's used up leaves your storage. Everything starts ticked; untick what's left.
struct CookedSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let day: Date
    let meal: Meal

    @State private var keep: Set<String> = []

    var body: some View {
        let atHome = meal.ingredients.map(\.name).filter { model.data.hasAtHome($0) && !model.data.isAlwaysAtHome($0) }
        NavigationStack {
            List {
                Section {
                    if atHome.isEmpty {
                        Text("None of the ingredients are in your storage, so there's nothing to take out.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(atHome, id: \.self) { name in
                        CheckRow(text: name, checked: !keep.contains(name)) {
                            if keep.contains(name) { keep.remove(name) } else { keep.insert(name) }
                        }
                    }
                } header: {
                    Text("Used up")
                } footer: {
                    Text("Untick what you still have left, like half a pack of pasta.")
                }
            }
            .navigationTitle(meal.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.data.markCooked(on: day, usedUp: atHome.filter { !keep.contains($0) })
                        dismiss()
                    }
                }
            }
        }
    }
}

/// What's at home, grouped like the shop.
struct StorageView: View {
    @EnvironmentObject var model: AppModel
    @State private var newItem = ""

    private func add() {
        model.data.addToPantry(newItem)
        newItem = ""
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Add something you have", text: $newItem)
                        .submitLabel(.done)
                        .onSubmit(add)
                    if !newItem.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Add", action: add)
                    }
                }
            } footer: {
                Text("Things you tick on the shopping list land here, and \"Cooked\" takes out what's used up. Swipe left to remove, right to mark as always at home.")
            }
            let always = model.data.pantry.filter(\.always).sorted { $0.name.lowercased() < $1.name.lowercased() }
            if !always.isEmpty {
                Section {
                    ForEach(always) { item in
                        Text(item.name)
                            .swipeActions {
                                Button("Remove", role: .destructive) { model.data.removeFromPantry(item.name) }
                            }
                            .swipeActions(edge: .leading) {
                                Button("Not always") { model.data.toggleAlways(item.id) }
                            }
                    }
                } header: {
                    Text("Always at home")
                } footer: {
                    Text("Never on the shopping list and never used up. Good for salt, oil, spices.")
                }
            }
            ForEach(Aisle.allCases) { aisle in
                let items = model.data.pantry.filter { $0.aisle == aisle && !$0.always }.sorted { $0.name.lowercased() < $1.name.lowercased() }
                if !items.isEmpty {
                    Section(aisle.title) {
                        ForEach(items) { item in
                            Text(item.name)
                                .swipeActions {
                                    Button("Used up", role: .destructive) { model.data.removeFromPantry(item.name) }
                                }
                                .swipeActions(edge: .leading) {
                                    Button("Always") { model.data.toggleAlways(item.id) }
                                        .tint(Palette.flame)
                                }
                        }
                    }
                }
            }
        }
        .overlay {
            if model.data.pantry.isEmpty {
                ContentUnavailableView("Storage is empty", systemImage: "refrigerator",
                                       description: Text("Add what you have at home, or tick things on the shopping list."))
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle("Your storage")
    }
}

/// "How much time do you have?" then one suggestion, another one, or take it.
struct MealChooser: View {
    @EnvironmentObject var model: AppModel
    let day: Date
    var onDone: () -> Void = {}

    @State private var minutes: Int?
    @State private var suggestion: Meal?
    @State private var seen: Set<String> = []
    @State private var servings = 1

    static let options = [10, 20, 30, 45]

    private func limit(_ m: Int) -> Int? { m >= 45 ? nil : m }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How much time do you have?").font(.headline)
            HStack(spacing: 8) {
                ForEach(Self.options, id: \.self) { m in
                    let on = minutes == m
                    Button { pickTime(m) } label: {
                        Text(m >= 45 ? "45+" : "\(m)")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(on ? Color.black : Color.primary)
                            .glassBackground(on ? Palette.flame : nil, in: RoundedRectangle(cornerRadius: 12),
                                             fallback: on ? Palette.flame : Color.gray.opacity(0.18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(m >= 45 ? "45 minutes or more" : "\(m) minutes")
                }
            }
            .sensoryFeedback(.selection, trigger: minutes)

            Picker("Portions", selection: $servings) {
                Text("For 1").tag(1)
                Text("For 2, leftovers tomorrow").tag(2)
            }
            .pickerStyle(.segmented)

            if let s = suggestion {
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.name).font(.title3.weight(.bold))
                    Text("\(s.minutes) min, \(ingredientLine(s))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Another one") { reroll() }
                        .glassButton()
                    Spacer()
                    Button("Take it") {
                        model.choose(s, for: day, servings: servings)
                        onDone()
                    }
                    .glassButton(prominent: true)
                }
            } else if let m = minutes {
                Text("Nothing fits in \(m) minutes. Add a quicker meal under Your meals.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Menu {
                ForEach(model.data.meals.sorted { $0.minutes < $1.minutes }) { meal in
                    Button("\(meal.name), \(meal.minutes) min") {
                        model.choose(meal, for: day, servings: servings)
                        onDone()
                    }
                }
            } label: {
                Text("I already know what I want")
                    .font(.subheadline)
            }
        }
    }

    private func ingredientLine(_ meal: Meal) -> String {
        meal.ingredients.map { ing -> String in
            let a = ing.amountText(servings: servings)
            return a.isEmpty ? ing.name : "\(ing.name) \(a)"
        }
        .joined(separator: ", ")
    }

    private func pickTime(_ m: Int) {
        minutes = m
        seen = []
        suggestion = model.data.suggest(maxMinutes: limit(m), for: day)
        if let s = suggestion { seen.insert(s.id) }
    }

    private func reroll() {
        guard let m = minutes else { return }
        guard let next = model.data.suggest(maxMinutes: limit(m), for: day, excluding: seen) else { return }
        if seen.contains(next.id) { seen = [next.id] } else { seen.insert(next.id) }
        suggestion = next
    }
}

// MARK: - Next days

struct NextDaysCard: View {
    @EnvironmentObject var model: AppModel
    let now: Date
    let change: (Date) -> Void

    var body: some View {
        let cal = DayKey.calendar
        let days = (1...2).compactMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: now)) }
        Card {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(days, id: \.self) { day in
                    let pick = model.data.pick(for: day)
                    Button { change(day) } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(dayName(day, now: now)).fontWeight(.semibold).frame(width: 96, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pick?.meal.name ?? "Nothing yet")
                                if let pick {
                                    Text(pick.leftover ? "Leftovers" : pick.auto ? "\(pick.meal.minutes) min, picked for you" : pick.servings == 2 ? "\(pick.meal.minutes) min, for 2" : "\(pick.meal.minutes) min")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Shopping

struct ShoppingCard: View {
    @EnvironmentObject var model: AppModel
    let now: Date
    @Binding var days: Int
    @State private var newExtra = ""

    private func addExtra() {
        let v = newExtra.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        if !model.data.extraShopping.contains(where: { $0.name.lowercased() == v.lowercased() }) {
            model.data.extraShopping.append(ExtraItem(name: v))
        }
        newExtra = ""
    }

    var body: some View {
        let items = model.data.shopping(days: days, now: now)
        let extras = model.data.extraShopping
        let done = items.filter { model.data.hasAtHome($0.name) }.count
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Shopping").font(.headline)
                    Spacer()
                    if !items.isEmpty || !extras.isEmpty {
                        Text("\(done) of \(items.count + extras.count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Picker("Shop for", selection: $days) {
                    Text("Tonight").tag(1)
                    Text("Next 3 days").tag(3)
                }
                .pickerStyle(.segmented)

                HStack {
                    TextField("Add something else, e.g. toilet paper", text: $newExtra)
                        .submitLabel(.done)
                        .onSubmit(addExtra)
                    if !newExtra.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Add", action: addExtra)
                    }
                }
                .padding(.vertical, 4)

                if items.isEmpty && extras.isEmpty {
                    Text("Nothing to buy.").foregroundStyle(.secondary)
                }
                ForEach(Aisle.allCases) { aisle in
                    let group = items.filter { $0.aisle == aisle }
                    let extraGroup = extras.filter { $0.aisle == aisle }
                    if !group.isEmpty || !extraGroup.isEmpty {
                        Text(aisle.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(group) { item in
                            let have = model.data.hasAtHome(item.name)
                            CheckRow(text: item.name, checked: have,
                                     detail: item.amountText.isEmpty ? (item.count > 1 ? "×\(item.count)" : nil) : item.amountText) {
                                model.data.setAtHome(item, !have)
                            }
                        }
                        ForEach(extraGroup) { extra in
                            // Ticking a hand-added item takes it off the list
                            CheckRow(text: extra.name, checked: false) {
                                withAnimation { model.data.extraShopping.removeAll { $0.id == extra.id } }
                            }
                        }
                    }
                }
                if !items.isEmpty || !extras.isEmpty {
                    Text("In the order you walk through the shop. Ticked meal ingredients go to your storage; things you added yourself disappear when ticked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Meals

struct MealsList: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List {
            ForEach(model.data.meals.sorted { $0.minutes < $1.minutes }) { meal in
                NavigationLink {
                    MealEditor(original: meal)
                } label: {
                    HStack {
                        Text(meal.name)
                        Spacer()
                        Text("\(meal.minutes) min").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { model.deleteMeal(meal.id) }
                }
            }
        }
        .overlay {
            if model.data.meals.isEmpty {
                ContentUnavailableView("No meals yet", systemImage: "fork.knife", description: Text("Add meals you like, with how long they take."))
            }
        }
        .navigationTitle("Your meals")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { MealEditor(original: nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add meal")
            }
        }
    }
}

struct MealEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let original: Meal?

    @State private var name = ""
    @State private var minutes = 20
    @State private var ingredients: [Ingredient] = []
    @State private var newIngredient = ""
    @State private var loaded = false

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section("Meal") {
                TextField("e.g. Chili con carne", text: $name)
                Stepper(value: $minutes, in: 5...120, step: 5) {
                    Text("\(minutes) min")
                }
            }
            Section {
                ForEach($ingredients) { $ing in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Ingredient", text: $ing.name)
                            Picker("Section", selection: $ing.aisle) {
                                ForEach(Aisle.allCases) { a in Text(a.title).tag(a) }
                            }
                            .labelsHidden()
                        }
                        HStack {
                            TextField("Amount", value: $ing.amount, format: .number)
                                .keyboardType(.decimalPad)
                                .frame(maxWidth: 90)
                            TextField("Unit (g, ml, Stk, Glas)", text: $ing.unit)
                                .textInputAutocapitalization(.never)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                .onDelete { ingredients.remove(atOffsets: $0) }
                HStack {
                    TextField("Add ingredient", text: $newIngredient)
                        .submitLabel(.done)
                        .onSubmit(addIngredient)
                    if !newIngredient.isEmpty {
                        Button("Add", action: addIngredient)
                    }
                }
            } header: {
                Text("Ingredients")
            } footer: {
                Text("Amounts are for one portion; cooking for 2 doubles them. Packs like Glas, Dose or Pck always stay 1. The section decides where it shows up on the shopping list.")
            }
            if let original {
                Section {
                    Button("Delete meal", role: .destructive) {
                        model.deleteMeal(original.id)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(original == nil ? "New meal" : "Edit meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(trimmed.isEmpty)
            }
        }
        .onAppear {
            guard !loaded else { return }
            if let original {
                name = original.name
                minutes = original.minutes
                ingredients = original.ingredients
            }
            loaded = true
        }
    }

    private func addIngredient() {
        let v = newIngredient.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        ingredients.append(Ingredient(name: v))
        newIngredient = ""
    }

    private func save() {
        if !newIngredient.trimmingCharacters(in: .whitespaces).isEmpty { addIngredient() }
        let cleaned = ingredients.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        model.saveMeal(Meal(id: original?.id ?? UUID().uuidString, name: trimmed, minutes: minutes, ingredients: cleaned))
        dismiss()
    }
}
