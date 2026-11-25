import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications
import Shared

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var notificationsDenied = false
    @State private var confirmRestore = false
    @State private var showRestorePicker = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                if notificationsDenied {
                    Section {
                        Button("Notifications are off for this app. Open iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }

                Section {
                    Toggle("Evening habit reminder", isOn: $model.data.settings.remindHabits)
                    if model.data.settings.remindHabits {
                        DatePicker("At", selection: timeBinding($model.data.settings.habitNudgeMinutes), displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Habits")
                } footer: {
                    Text("Only lists habits still open that day. Press and hold the notification to tick them off without opening the app.")
                }

                Section {
                    DatePicker("Decide by", selection: timeBinding($model.data.settings.foodDeadlineMinutes), displayedComponents: .hourAndMinute)
                    Picker("Usual cooking time", selection: $model.data.settings.usualCookMinutes) {
                        Text("10 min").tag(10)
                        Text("20 min").tag(20)
                        Text("30 min").tag(30)
                        Text("Any").tag(999)
                    }
                    Toggle("Reminder at that time", isOn: $model.data.settings.remindFood)
                } header: {
                    Text("Food")
                } footer: {
                    Text("If you haven't chosen tonight's meal by then, the app's pick stays. Its picks stay within your usual cooking time. The reminder says what's for dinner and what you still need to buy.")
                }

                Section {
                    ShareLink(item: backupFile(), preview: SharePreview("Heatmap backup")) {
                        Text("Export backup")
                    }
                    Button("Restore backup") { confirmRestore = true }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Everything is stored only on this iPhone. Export a backup now and then, for example to iCloud Drive.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Restoring replaces everything in the app with the backup.", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("Choose backup file", role: .destructive) { showRestorePicker = true }
            }
            .fileImporter(isPresented: $showRestorePicker, allowedContentTypes: [.json]) { result in
                restore(result)
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .task {
                let s = await UNUserNotificationCenter.current().notificationSettings()
                notificationsDenied = s.authorizationStatus == .denied
            }
        }
    }

    private func backupFile() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Heatmap backup \(DayKey.key(Date())).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(model.data) { try? data.write(to: url, options: .atomic) }
        return url
    }

    private func restore(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              var decoded = try? JSONDecoder().decode(AppData.self, from: data),
              !decoded.habits.isEmpty else {
            message = "That file isn't a Heatmap backup."
            return
        }
        decoded.migrate()
        decoded.ensureAutoPicks()
        model.data = decoded
        message = "Backup restored."
    }
}
