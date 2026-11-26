import SwiftUI
import Shared

struct ListsView: View {
    @EnvironmentObject var model: AppModel
    @State private var adding = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.data.lists) { list in
                    NavigationLink {
                        ListDetail(listID: list.id)
                    } label: {
                        HStack {
                            Label(list.name, systemImage: list.reusable ? "arrow.counterclockwise" : "checklist")
                            Spacer()
                            let open = list.items.filter { !$0.done }.count
                            Text(list.items.isEmpty ? "Empty" : "\(open) open")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .onDelete { model.data.lists.remove(atOffsets: $0) }
                .onMove { model.data.lists.move(fromOffsets: $0, toOffset: $1) }
            }
            .overlay {
                if model.data.lists.isEmpty {
                    ContentUnavailableView("No lists yet", systemImage: "checklist",
                                           description: Text("Tap + for a packing list, to-dos or anything else."))
                }
            }
            .navigationTitle("Lists")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !model.data.lists.isEmpty { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newName = ""; adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New list")
                }
            }
            .alert("New list", isPresented: $adding) {
                TextField("Name", text: $newName)
                Button("Create") {
                    let n = newName.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { model.data.lists.append(UserList(name: n)) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

struct ListDetail: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let listID: String

    @State private var newItem = ""
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @FocusState private var addFocused: Bool

    private var index: Int? { model.data.lists.firstIndex { $0.id == listID } }

    private func update(_ change: (inout UserList) -> Void) {
        if let i = index { change(&model.data.lists[i]) }
    }

    private func add() {
        let v = newItem.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        update { $0.items.append(ListItem(text: v)) }
        newItem = ""
        addFocused = true
    }

    var body: some View {
        if let i = index {
            let list = model.data.lists[i]
            let open = list.items.filter { !$0.done }
            let done = list.items.filter { $0.done }
            List {
                Section {
                    ForEach(open) { item in
                        CheckRow(text: item.text, checked: false) { toggle(item.id) }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { open[$0].id }
                        update { $0.items.removeAll { ids.contains($0.id) } }
                    }
                    HStack {
                        TextField("Add item", text: $newItem)
                            .focused($addFocused)
                            .submitLabel(.done)
                            .onSubmit(add)
                        if !newItem.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Add", action: add)
                        }
                    }
                }
                if !done.isEmpty {
                    Section {
                        ForEach(done) { item in
                            CheckRow(text: item.text, checked: true) { toggle(item.id) }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { done[$0].id }
                            update { $0.items.removeAll { ids.contains($0.id) } }
                        }
                    } header: {
                        Text("Done")
                    } footer: {
                        if list.reusable {
                            Text("This list is reusable: \"Uncheck all\" in the menu starts it over.")
                        }
                    }
                }
            }
            .navigationTitle(list.name)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if list.reusable {
                            Button { update { l in for j in l.items.indices { l.items[j].done = false } } } label: {
                                Label("Uncheck all", systemImage: "arrow.counterclockwise")
                            }
                        } else {
                            Button { update { $0.items.removeAll { $0.done } } } label: {
                                Label("Clear done items", systemImage: "trash.slash")
                            }
                        }
                        Toggle(isOn: Binding(get: { list.reusable }, set: { v in update { $0.reusable = v } })) {
                            Label("Reusable (packing list)", systemImage: "arrow.counterclockwise")
                        }
                        Button { newName = list.name; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete list", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("List options")
                }
            }
            .alert("Rename list", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Save") {
                    let n = newName.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { update { $0.name = n } }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete \(list.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete list", role: .destructive) {
                    model.data.lists.removeAll { $0.id == listID }
                    dismiss()
                }
            }
        } else {
            Text("This list was deleted.").foregroundStyle(.secondary)
        }
    }

    private func toggle(_ id: String) {
        update { l in
            if let j = l.items.firstIndex(where: { $0.id == id }) { l.items[j].done.toggle() }
        }
    }
}
