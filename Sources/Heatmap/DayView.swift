import SwiftUI
import EventKit
import Shared

/// One line on the timeline: an appointment or a reminder.
struct DayEntry: Identifiable {
    enum Kind {
        case event(EKEvent)
        case reminder(Reminder)
    }
    let id: String
    let sortMinutes: Int
    let kind: Kind
}

struct ReminderTarget: Identifiable {
    let id = UUID()
    let reminder: Reminder?
}

struct DayView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var calendar: CalendarStore

    @State private var editing: ReminderTarget?
    @State private var addingEvent = false
    @State private var showComing = false
    @State private var showMissed = false

    var body: some View {
        let now = Date()
        let cal = DayKey.calendar
        let upcoming = (1...6).compactMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: now)) }
        let missed = model.data.missedReminders(now: now)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if calendar.status == .notDetermined {
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Show your calendar here").font(.headline)
                                Text("Your appointments appear next to your reminders, so today is in one place.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Button("Allow calendar access") { calendar.requestAccess() }
                                    .glassButton(prominent: true)
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Today").font(.headline).padding(.bottom, 4)
                            Timeline(day: now, entries: entries(on: now), isToday: true) { editing = ReminderTarget(reminder: $0) }
                        }
                    }

                    if !missed.isEmpty {
                        Card {
                            DisclosureGroup(isExpanded: $showMissed) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(missed) { r in
                                        MissedRow(reminder: r) { editing = ReminderTarget(reminder: r) }
                                    }
                                }
                                .padding(.top, 8)
                            } label: {
                                Text("Missed (\(missed.count))").fontWeight(.semibold).foregroundStyle(.primary)
                            }
                        }
                    }

                    Card {
                        DisclosureGroup(isExpanded: $showComing) {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(upcoming, id: \.self) { day in
                                    let list = entries(on: day)
                                    if !list.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(day.formatted(.dateTime.weekday(.wide).day().month()))
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                            Timeline(day: day, entries: list, isToday: false) { editing = ReminderTarget(reminder: $0) }
                                        }
                                    }
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            Text("Coming up").fontWeight(.semibold).foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 30)
            }
            .navigationTitle("Day")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { editing = ReminderTarget(reminder: nil) } label: { Label("Reminder", systemImage: "bell") }
                        Button { addingEvent = true } label: { Label("Calendar event", systemImage: "calendar") }
                            .disabled(!calendar.hasAccess)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add")
                }
            }
            .sheet(item: $editing) { t in ReminderEditor(original: t.reminder) }
            .sheet(isPresented: $addingEvent) {
                EventEditor(store: calendar.store) {
                    addingEvent = false
                    calendar.reload()
                }
                .ignoresSafeArea()
            }
            .refreshable { calendar.reload() }
        }
    }

    private func entries(on day: Date) -> [DayEntry] {
        let cal = Calendar.current
        var list: [DayEntry] = calendar.events(on: day).map { e in
            let starts = cal.isDate(e.startDate, inSameDayAs: day)
            let m = e.isAllDay || !starts ? -1 : cal.component(.hour, from: e.startDate) * 60 + cal.component(.minute, from: e.startDate)
            return DayEntry(id: "e" + (e.eventIdentifier ?? UUID().uuidString), sortMinutes: m, kind: .event(e))
        }
        list += model.data.reminders(on: day).map { r in
            DayEntry(id: "r" + r.id, sortMinutes: r.minutes, kind: .reminder(r))
        }
        return list.sorted { $0.sortMinutes < $1.sortMinutes }
    }
}

/// Times on the left, appointments and reminders on the right.
struct Timeline: View {
    @EnvironmentObject var model: AppModel
    let day: Date
    let entries: [DayEntry]
    let isToday: Bool
    let edit: (Reminder) -> Void

    var body: some View {
        if entries.isEmpty {
            Text(isToday ? "Nothing planned. Tap + to add a reminder." : "Nothing planned.")
                .foregroundStyle(.secondary)
        }
        ForEach(entries) { entry in
            switch entry.kind {
            case .event(let e):
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(entry.sortMinutes < 0 ? "All day" : formatTime(entry.sortMinutes))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 58, alignment: .leading)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(cgColor: e.calendar.cgColor))
                        .frame(width: 4, height: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.title ?? "Event")
                        if let loc = e.location, !loc.isEmpty {
                            Text(loc).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 36)
            case .reminder(let r):
                let done = r.isDone(on: day)
                HStack(alignment: .center, spacing: 12) {
                    Text(formatTime(r.minutes))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 58, alignment: .leading)
                    Button {
                        model.data.setReminderDone(r.id, on: day, !done)
                    } label: {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(done ? Palette.flame : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.success, trigger: done)
                    .accessibilityLabel(done ? "Done" : "Mark done")
                    Button { edit(r) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.title)
                                .strikethrough(done)
                                .foregroundStyle(done ? Color.secondary : Color.primary)
                            if r.aboutDinner, let pick = model.data.pick(for: day) {
                                Text(pick.leftover ? "Leftovers: \(pick.meal.name)" : pick.meal.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 36)
            }
        }
    }
}

struct MissedRow: View {
    @EnvironmentObject var model: AppModel
    let reminder: Reminder
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(reminder.title)
                    Text(reminder.repeatText).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button("Today") {
                if let i = model.data.reminders.firstIndex(where: { $0.id == reminder.id }) {
                    model.data.reminders[i].once = DayKey.key(Date())
                }
            }
            .glassButton()
            Button {
                if let once = reminder.once, let d = DayKey.date(fromKey: once) {
                    model.data.setReminderDone(reminder.id, on: d, true)
                }
            } label: {
                Image(systemName: "checkmark")
            }
            .glassButton()
            .accessibilityLabel("Done")
        }
    }
}

struct ReminderEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let original: Reminder?

    enum Repeat: Hashable { case once, daily, weekdays, custom }

    @State private var title = ""
    @State private var minutes = 9 * 60
    @State private var repeatKind: Repeat = .once
    @State private var date = Date()
    @State private var days: Set<Int> = []
    @State private var aboutDinner = false

    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Call grandma", text: $title)
                    DatePicker("Time", selection: timeBinding($minutes), displayedComponents: .hourAndMinute)
                }
                Section("Repeat") {
                    Picker("Repeat", selection: $repeatKind) {
                        Text("Once").tag(Repeat.once)
                        Text("Daily").tag(Repeat.daily)
                        Text("Weekdays").tag(Repeat.weekdays)
                        Text("Days").tag(Repeat.custom)
                    }
                    .pickerStyle(.segmented)
                    if repeatKind == .once {
                        DatePicker("Day", selection: $date, displayedComponents: .date)
                    }
                    if repeatKind == .custom {
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
                                        .background(on ? Palette.flame : Color.gray.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(DayKey.longNames[d - 1])
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                    }
                }
                Section {
                    Toggle("About dinner", isOn: $aboutDinner)
                } footer: {
                    Text("Adds that day's meal to the notification, like \"Cook: Carbonara, 25 min\".")
                }
                if let original {
                    Section {
                        Button("Delete reminder", role: .destructive) {
                            model.data.reminders.removeAll { $0.id == original.id }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(original == nil ? "New reminder" : "Edit reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmed.isEmpty || (repeatKind == .custom && days.isEmpty))
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let r = original else { return }
        title = r.title
        minutes = r.minutes
        aboutDinner = r.aboutDinner
        if let once = r.once {
            repeatKind = .once
            date = DayKey.date(fromKey: once) ?? Date()
        } else if r.days.isEmpty || r.days.count == 7 {
            repeatKind = .daily
        } else if Set(r.days) == Set([1, 2, 3, 4, 5]) {
            repeatKind = .weekdays
        } else {
            repeatKind = .custom
            days = Set(r.days)
        }
    }

    private func save() {
        var r = original ?? Reminder(title: trimmed, minutes: minutes)
        r.title = trimmed
        r.minutes = minutes
        r.aboutDinner = aboutDinner
        switch repeatKind {
        case .once:
            r.once = DayKey.key(date)
            r.days = []
        case .daily:
            r.once = nil
            r.days = []
        case .weekdays:
            r.once = nil
            r.days = [1, 2, 3, 4, 5]
        case .custom:
            r.once = nil
            r.days = days.sorted()
        }
        if let i = model.data.reminders.firstIndex(where: { $0.id == r.id }) {
            model.data.reminders[i] = r
        } else {
            model.data.reminders.append(r)
        }
        dismiss()
    }
}
