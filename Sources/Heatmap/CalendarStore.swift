import SwiftUI
import EventKit
import Shared

/// Reads your iPhone calendars (including ones synced from elsewhere) for the Day tab.
@MainActor
final class CalendarStore: ObservableObject {
    let store = EKEventStore()
    @Published private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var events: [EKEvent] = []
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        reload()
    }

    var hasAccess: Bool { status == .fullAccess }

    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            status = EKEventStore.authorizationStatus(for: .event)
            reload()
        }
    }

    /// Today and the next six days
    func reload() {
        status = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else {
            events = []
            return
        }
        let cal = DayKey.calendar
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 7, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    func events(on day: Date) -> [EKEvent] {
        let cal = DayKey.calendar
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events.filter { $0.startDate < end && $0.endDate > start }
    }
}

/// Apple's own "New Event" screen, so events land in your normal calendar.
struct EventEditor: UIViewControllerRepresentable {
    let store: EKEventStore
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.eventStore = store
        vc.event = EKEvent(eventStore: store)
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }
}
