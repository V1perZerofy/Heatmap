import SwiftUI
import UIKit
import Shared

struct EditTarget: Identifiable {
    let id = UUID()
    let habit: Habit?
}

struct DayTarget: Identifiable {
    let id = UUID()
    let habitID: String
    let day: Date
}

struct HabitsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var router: Router

    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var editing: EditTarget?
    @State private var dayEdit: DayTarget?
    @State private var reorder = false
    @State private var showSettings = false
    @State private var deleting: Habit?

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.data.habits.isEmpty {
                        Text("Add a habit to start your first heatmap.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    ForEach(model.data.habits) { habit in
                        HabitCard(
                            habit: habit,
                            year: year,
                            onEdit: { editing = EditTarget(habit: habit) },
                            onTimer: {
                                if timer.session == nil { timer.start(habit) }
                                router.showTimer = true
                            },
                            onDone: {
                                if !model.toggleToday(habit.id) { dayEdit = DayTarget(habitID: habit.id, day: Date()) }
                            },
                            onDay: { day in dayEdit = DayTarget(habitID: habit.id, day: day) }
                        )
                        .contextMenu {
                            Button { editing = EditTarget(habit: habit) } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) { deleting = habit } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    Button {
                        editing = EditTarget(habit: nil)
                    } label: {
                        Label("Add habit", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 30)
            }
            .navigationTitle("Habits")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                        Button { reorder = true } label: { Label("Edit habits", systemImage: "list.bullet") }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Button { year -= 1 } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Previous year")
                        Text(String(year)).font(.headline).monospacedDigit()
                        Button { year += 1 } label: { Image(systemName: "chevron.right") }
                            .disabled(year >= currentYear)
                            .accessibilityLabel("Next year")
                    }
                }
            }
            .sheet(item: $editing) { target in HabitEditor(original: target.habit) }
            .sheet(item: $dayEdit) { target in
                DayEditor(habitID: target.habitID, day: target.day).presentationDetents([.height(340)])
            }
            .sheet(isPresented: $reorder) { ReorderSheet() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .confirmationDialog("Delete \(deleting?.name ?? "habit") and its whole history?",
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let h = deleting { model.delete(h.id) }
                    deleting = nil
                }
            }
        }
    }
}

struct HabitCard: View {
    let habit: Habit
    let year: Int
    let onEdit: () -> Void
    let onTimer: () -> Void
    let onDone: () -> Void
    let onDay: (Date) -> Void

    var body: some View {
        let done = habit.isDone(on: Date())
        let streak = habit.streak()
        let scheduledToday = habit.isScheduled(on: Date())
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: onEdit) {
                    Image(systemName: habit.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(habit.color)
                        .frame(width: 44, height: 44)
                        .background(habit.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("Edit \(habit.name)")

                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name).font(.headline).lineLimit(1)
                    HStack(spacing: 8) {
                        Text(formatMinutes(habit.total(inYear: year))).foregroundStyle(.secondary)
                        if streak.days > 0 {
                            Label("\(streak.days)", systemImage: "flame.fill")
                                .foregroundStyle(Palette.flame)
                                .fontWeight(.semibold)
                        }
                        if streak.freezeUsedThisWeek {
                            Image(systemName: "snowflake")
                                .foregroundStyle(Palette.freeze)
                                .accessibilityLabel("Freeze used this week")
                        }
                    }
                    .font(.subheadline)
                }

                Spacer(minLength: 0)

                Button(action: onTimer) {
                    Image(systemName: "play.fill")
                        .foregroundStyle(habit.color)
                        .frame(width: 44, height: 44)
                        .background(habit.color.opacity(0.22), in: Circle())
                }
                .accessibilityLabel("Start focus timer")

                Button(action: onDone) {
                    Label(done ? "Done" : (scheduledToday ? "Today" : "Extra"), systemImage: done ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(done ? habit.color.opacity(0.28) : Color.gray.opacity(0.18), in: Capsule())
                        .foregroundStyle(done ? Color.primary : Color.secondary)
                }
                .sensoryFeedback(.success, trigger: done)
            }
            .buttonStyle(.plain)

            NavigationLink {
                HabitDetail(habitID: habit.id)
            } label: {
                HeatmapView(habit: habit, grid: .year(year), showLabels: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(habit.name) by month")

            if !habit.days.isEmpty || streak.freezeUsedThisWeek {
                Text([habit.days.isEmpty ? nil : habit.scheduleText,
                      streak.freezeUsedThisWeek ? "Freeze used this week" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ReorderSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: Habit?

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.data.habits) { h in
                    HStack {
                        Label(h.name, systemImage: h.symbol).foregroundStyle(h.color)
                        Spacer()
                        Button(role: .destructive) { deleting = h } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete \(h.name)")
                    }
                }
                .onMove { model.data.habits.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit habits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete \(deleting?.name ?? "habit") and its whole history?",
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let h = deleting { model.delete(h.id) }
                    deleting = nil
                }
            }
        }
    }
}

struct HabitEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let original: Habit?

    @State private var name = ""
    @State private var symbol = "star.fill"
    @State private var colorIndex = 0
    @State private var days: Set<Int> = []
    @State private var confirmDelete = false

    static let symbols = [
        "chevron.left.forwardslash.chevron.right", "pianokeys", "character.book.closed", "paintpalette",
        "figure.run", "figure.table.tennis", "book", "dumbbell",
        "brain.head.profile", "music.note", "guitars", "pencil",
        "camera", "leaf", "globe", "star.fill",
        "moon.zzz", "drop", "character.bubble", "figure.walk",
    ]

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Japanese", text: $name)
                }
                Section {
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { d in
                            let on = days.contains(d)
                            Button {
                                if on { days.remove(d) } else { days.insert(d) }
                            } label: {
                                Text(String(DayKey.shortNames[d - 1].prefix(2)))
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .foregroundStyle(on ? Color.black : Color.primary)
                                    .background(on ? Palette.color(colorIndex) : Color.gray.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(DayKey.longNames[d - 1])
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Days")
                } footer: {
                    Text("No days selected means every day. Streaks skip days that aren't selected, and the evening reminder only asks on these days. One missed day per week is forgiven.")
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                        ForEach(Self.symbols, id: \.self) { s in
                            Button { symbol = s } label: {
                                Image(systemName: s)
                                    .font(.system(size: 18))
                                    .frame(width: 44, height: 44)
                                    .background(
                                        symbol == s ? Palette.color(colorIndex).opacity(0.3) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Colour") {
                    HStack {
                        ForEach(0..<Palette.count, id: \.self) { i in
                            Button { colorIndex = i } label: {
                                Circle()
                                    .fill(Palette.color(i))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle().stroke(Color.primary, lineWidth: colorIndex == i ? 2.5 : 0).padding(-4)
                                    )
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 6)
                }
                if original != nil {
                    Section {
                        Button("Delete habit", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(original == nil ? "New habit" : "Edit habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(trimmed.isEmpty)
                }
            }
            .confirmationDialog("Delete this habit and its whole history?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let o = original { model.delete(o.id) }
                    dismiss()
                }
            }
            .onAppear {
                if let o = original {
                    name = o.name
                    symbol = o.symbol
                    colorIndex = o.colorIndex
                    days = Set(o.days)
                } else {
                    colorIndex = model.data.habits.count % Palette.count
                }
            }
        }
    }

    private func save() {
        var h = original ?? Habit(name: trimmed, symbol: symbol, colorIndex: colorIndex)
        h.name = trimmed
        h.symbol = symbol
        h.colorIndex = colorIndex
        h.days = days.count == 7 ? [] : days.sorted()
        model.upsert(h)
        dismiss()
    }
}

struct DayEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let habitID: String
    let day: Date

    @State private var minutes = 0

    var body: some View {
        let habit = model.habit(habitID)
        let existing = habit?.minutes(on: day)
        NavigationStack {
            VStack(spacing: 18) {
                Text(day.formatted(date: .complete, time: .omitted))
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Button { minutes = max(0, minutes - 15) } label: {
                        Image(systemName: "minus").frame(width: 50, height: 40)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("15 minutes less")

                    VStack(spacing: 0) {
                        Text("\(minutes)")
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("minutes").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 110)

                    Button { minutes = min(1440, minutes + 15) } label: {
                        Image(systemName: "plus").frame(width: 50, height: 40)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("15 minutes more")
                }

                Text("0 minutes still counts as done.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    if existing != nil {
                        Button("Clear day", role: .destructive) {
                            model.setMinutes(habitID, day: day, minutes: nil)
                            dismiss()
                        }
                    }
                    Spacer()
                    Button("Save") {
                        model.setMinutes(habitID, day: day, minutes: minutes)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(habit?.color ?? Palette.flame)
                }
            }
            .padding()
            .navigationTitle(habit?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { minutes = existing ?? 0 }
        }
    }
}

struct FocusView: View {
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var confirmDiscard = false

    var body: some View {
        Group {
            if let s = timer.session {
                let color = model.habit(s.habitID)?.color ?? Palette.flame
                let symbol = model.habit(s.habitID)?.symbol ?? "timer"
                VStack(spacing: 28) {
                    Label(s.habitName, systemImage: symbol)
                        .font(.title2.weight(.semibold))

                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let e = timer.elapsed
                        let target = Double(s.targetMinutes * 60)
                        let progress = target > 0 ? min(1, e / target) : e.truncatingRemainder(dividingBy: 3600) / 3600
                        ZStack {
                            Circle().stroke(Color.gray.opacity(0.2), lineWidth: 12)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 4) {
                                Text(clock(e))
                                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                Text(status(elapsed: e, target: target, running: s.running))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 280, height: 280)
                    }

                    Picker("Target", selection: Binding(get: { s.targetMinutes }, set: { timer.setTarget($0) })) {
                        Text("25 min").tag(25)
                        Text("50 min").tag(50)
                        Text("Open").tag(0)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)

                    HStack(spacing: 12) {
                        Button(s.running ? "Pause" : "Resume") {
                            if s.running { timer.pause() } else { timer.resume() }
                        }
                        .buttonStyle(.bordered)

                        Button("Finish and log") {
                            if let result = timer.finish() {
                                model.add(minutes: result.minutes, to: result.habitID)
                            }
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(color)

                        Button("Discard", role: .destructive) { confirmDiscard = true }
                            .buttonStyle(.bordered)
                    }
                    .controlSize(.large)

                    Button("Hide timer") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                .padding()
                .confirmationDialog("Discard this session?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) {
                        timer.discard()
                        dismiss()
                    }
                }
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func clock(_ e: TimeInterval) -> String {
        let s = Int(e)
        let mmss = String(format: "%02d:%02d", (s / 60) % 60, s % 60)
        return s >= 3600 ? "\(s / 3600):\(mmss)" : mmss
    }

    private func status(elapsed: TimeInterval, target: Double, running: Bool) -> String {
        if !running { return "Paused" }
        if target <= 0 { return "Open session" }
        if elapsed >= target { return "Target reached" }
        return "\(Int(ceil((target - elapsed) / 60))) min to go"
    }
}


// MARK: - Habit page with a month calendar

struct HabitDetail: View {
    @EnvironmentObject var model: AppModel
    let habitID: String

    @State private var month = DayKey.calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var dayEdit: DayTarget?

    private let cal = DayKey.calendar

    var body: some View {
        if let h = model.habit(habitID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    statsCard(h)
                    Card { monthGrid(h) }
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("This year").font(.headline)
                            HeatmapView(habit: h, grid: .year(cal.component(.year, from: month)), showLabels: true)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 30)
            }
            .navigationTitle(h.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $dayEdit) { t in
                DayEditor(habitID: t.habitID, day: t.day).presentationDetents([.height(340)])
            }
        } else {
            Text("This habit was deleted.").foregroundStyle(.secondary)
        }
    }

    // MARK: Stats

    private func statsCard(_ h: Habit) -> some View {
        let monthDays = days(in: month)
        let done = monthDays.filter { h.isDone(on: $0) }.count
        let scheduled = monthDays.filter { $0 <= Date() && h.isScheduled(on: $0) }.count
        let minutes = monthDays.reduce(0) { $0 + (h.minutes(on: $1) ?? 0) }
        return HStack(alignment: .top, spacing: 12) {
            stat("\(h.streak().days)", "current streak", Palette.flame)
            stat("\(bestStreak(h))", "best streak", .primary)
            stat("\(done)/\(max(scheduled, done))", "days this month", .primary)
            stat(formatMinutes(minutes), "this month", .primary)
        }
        .padding(.horizontal, 4)
    }

    private func stat(_ value: String, _ caption: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Longest run of done days, skipping days the habit isn't scheduled on.
    private func bestStreak(_ h: Habit) -> Int {
        guard let first = h.log.keys.min(), var day = DayKey.date(fromKey: first) else { return 0 }
        let end = cal.startOfDay(for: Date())
        var best = 0, run = 0
        while day <= end {
            if h.isDone(on: day) {
                run += 1
                best = max(best, run)
            } else if h.isScheduled(on: day) && day < end {
                run = 0
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return best
    }

    // MARK: Month calendar

    private func days(in month: Date) -> [Date] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    private func shift(_ months: Int) {
        guard let m = cal.date(byAdding: .month, value: months, to: month) else { return }
        withAnimation(.easeOut(duration: 0.2)) { month = m }
    }

    private func monthGrid(_ h: Habit) -> some View {
        let list = days(in: month)
        let blanks = list.first.map { DayKey.isoWeekday($0) - 1 } ?? 0
        let today = cal.startOfDay(for: Date())
        let isCurrent = cal.isDate(month, equalTo: today, toGranularity: .month)
        return VStack(spacing: 10) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .disabled(isCurrent)
                    .accessibilityLabel("Next month")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    Text(String(DayKey.shortNames[i].prefix(2)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(0..<blanks, id: \.self) { _ in Color.clear.frame(height: 48) }
                ForEach(list, id: \.self) { day in
                    dayCell(h, day: day, today: today)
                }
            }
            Text("Tap a day to change it. Swipe to switch months.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { v in
                if v.translation.width < -40, !isCurrent { shift(1) }
                if v.translation.width > 40 { shift(-1) }
            }
        )
    }

    private func dayCell(_ h: Habit, day: Date, today: Date) -> some View {
        let minutes = h.minutes(on: day)
        let level = DayKey.level(minutes)
        let future = day > today
        let isToday = cal.isDate(day, inSameDayAs: today)
        let scheduled = h.isScheduled(on: day)
        let spoken = minutes.map { "\($0) minutes" } ?? "not done"
        let label = "\(day.formatted(date: .complete, time: .omitted)), \(spoken)"
        return Button {
            dayEdit = DayTarget(habitID: h.id, day: day)
        } label: {
            VStack(spacing: 1) {
                Text("\(cal.component(.day, from: day))")
                    .font(.subheadline.weight(.semibold))
                Text(minutes.map { $0 > 0 ? "\($0)m" : "done" } ?? " ")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(level >= 3 ? Color.black : (scheduled ? Color.primary : Color.secondary))
            .background(
                level > 0 ? h.color.opacity(0.3 + 0.7 * Double(level) / 4) : Color.gray.opacity(scheduled ? 0.16 : 0.07),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10).stroke(Color.primary, lineWidth: isToday ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
        .disabled(future)
        .opacity(future ? 0.35 : 1)
        .accessibilityLabel(label)
    }
}
