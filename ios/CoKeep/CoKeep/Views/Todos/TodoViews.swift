import SwiftUI

struct TodoListsView: View {
    let objectId: String
    @State private var lists: [TodoList] = []
    @State private var showNewList = false
    @State private var newListName = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(lists) { list in
                    TodoListSection(list: list, objectId: objectId) {
                        Task { await load() }
                    }
                }

                Button {
                    showNewList = true
                } label: {
                    Label(L10n.string("todos.newList"), systemImage: "plus")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .task { await load() }
        .refreshable { await load() }
        .alert(L10n.string("todos.newList"), isPresented: $showNewList) {
            TextField(L10n.string("todos.listName"), text: $newListName)
            Button(L10n.string("common.cancel"), role: .cancel) {}
            Button(L10n.string("common.save")) {
                Task { await createList() }
            }
        }
    }

    private func load() async {
        do {
            struct Resp: Codable { let lists: [TodoList] }
            let resp: Resp = try await APIClient.shared.request(
                "GET",
                path: "api/objects/\(objectId)/todo-lists"
            )
            lists = resp.lists
        } catch {}
    }

    private func createList() async {
        struct Body: Encodable { let name: String }
        struct Resp: Codable { let list: TodoListSummary }
        do {
            let _: Resp = try await APIClient.shared.request(
                "POST",
                path: "api/objects/\(objectId)/todo-lists",
                body: Body(name: newListName)
            )
            newListName = ""
            await load()
        } catch {}
    }
}

struct TodoListSection: View {
    let list: TodoList
    let objectId: String
    var onChange: () -> Void
    @State private var showAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.todoListName(list.name))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
            }

            if list.openItems.isEmpty {
                Text(L10n.string("todos.noOpen"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 4)
            } else {
                ForEach(list.openItems) { item in
                    NavigationLink {
                        TodoItemDetailView(itemId: item.id, onChange: onChange)
                    } label: {
                        TodoItemRow(item: item) {
                            Task { await toggleDone(item, done: true) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if !list.doneItems.isEmpty {
                Text(L10n.string("todos.doneSection"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 8)

                ForEach(list.doneItems) { item in
                    NavigationLink {
                        TodoItemDetailView(itemId: item.id, onChange: onChange)
                    } label: {
                        TodoItemRow(item: item, dimmed: true) {
                            Task { await toggleDone(item, done: false) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.cardFill)
        )
        .sheet(isPresented: $showAdd) {
            CreateTodoItemView(listId: list.id, objectId: objectId) {
                showAdd = false
                onChange()
            }
        }
    }

    private func toggleDone(_ item: TodoItem, done: Bool) async {
        struct Body: Encodable { let isDone: Bool }
        struct Resp: Codable { let item: TodoItem }
        do {
            let _: Resp = try await APIClient.shared.request(
                "PATCH",
                path: "api/todo-items/\(item.id)",
                body: Body(isDone: done)
            )
            onChange()
        } catch {}
    }
}

struct TodoItemRow: View {
    let item: TodoItem
    var dimmed = false
    var onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isDone ? Theme.accent : Theme.muted)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .strikethrough(item.isDone)
                    .foregroundStyle(dimmed ? Theme.muted : Theme.ink)
                HStack(spacing: 8) {
                    if let due = item.dueDate {
                        Label(formatDate(due), systemImage: "calendar")
                    }
                    if let minutes = item.totalWorkMinutes, minutes > 0 {
                        Label(formatDuration(minutes), systemImage: "clock")
                    }
                    if let assignee = item.assignee {
                        Label(assignee.firstName, systemImage: "person")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .opacity(dimmed ? 0.75 : 1)
    }
}

struct CreateTodoItemView: View {
    let listId: String
    let objectId: String
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var scheduleType = "ONE_OFF"
    @State private var dueDate = Date()
    @State private var hasDueDate = false
    @State private var recurrence = "MONTHLY"
    @State private var members: [ObjectMember] = []
    @State private var assigneeId: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.string("todos.itemName"), text: $name)
                TextField(L10n.string("todos.description"), text: $description, axis: .vertical)
                    .lineLimit(3...6)

                Picker(L10n.string("todos.schedule"), selection: $scheduleType) {
                    Text(L10n.string("todos.oneOff")).tag("ONE_OFF")
                    Text(L10n.string("todos.recurring")).tag("RECURRING")
                }

                Toggle(L10n.string("todos.hasDueDate"), isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker(L10n.string("todos.dueDate"), selection: $dueDate, displayedComponents: .date)
                }

                if scheduleType == "RECURRING" {
                    Picker(L10n.string("todos.recurrence"), selection: $recurrence) {
                        Text(L10n.string("recurrence.weekly")).tag("WEEKLY")
                        Text(L10n.string("recurrence.biweekly")).tag("BIWEEKLY")
                        Text(L10n.string("recurrence.monthly")).tag("MONTHLY")
                        Text(L10n.string("recurrence.quarterly")).tag("QUARTERLY")
                        Text(L10n.string("recurrence.yearly")).tag("YEARLY")
                    }
                }

                Picker(L10n.string("todos.assignee"), selection: $assigneeId) {
                    Text(L10n.string("todos.unassigned")).tag(String?.none)
                    ForEach(members) { m in
                        Text(m.user.displayName).tag(Optional(m.user.id))
                    }
                }

                if let error {
                    Text(error).foregroundStyle(Theme.danger)
                }
            }
            .navigationTitle(L10n.string("todos.newItem"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common.save")) {
                        Task { await save() }
                    }
                    .disabled(name.isEmpty)
                }
            }
            .task { await loadMembers() }
        }
    }

    private func loadMembers() async {
        do {
            struct Resp: Codable { let object: SharedObject }
            let resp: Resp = try await APIClient.shared.request("GET", path: "api/objects/\(objectId)")
            members = resp.object.members ?? []
        } catch {}
    }

    private func save() async {
        struct Body: Encodable {
            let name: String
            let description: String?
            let scheduleType: String
            let dueDate: String?
            let recurrence: String?
            let assigneeId: String?
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        do {
            struct Resp: Codable { let item: TodoItem }
            let _: Resp = try await APIClient.shared.request(
                "POST",
                path: "api/todo-lists/\(listId)/items",
                body: Body(
                    name: name,
                    description: description.isEmpty ? nil : description,
                    scheduleType: scheduleType,
                    dueDate: hasDueDate ? iso.string(from: dueDate) : nil,
                    recurrence: scheduleType == "RECURRING" ? recurrence : nil,
                    assigneeId: assigneeId
                )
            )
            onDone()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct TodoItemDetailView: View {
    let itemId: String
    var onChange: () -> Void

    @State private var item: TodoItem?
    @State private var showLog = false
    @State private var members: [ObjectMember] = []

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(item.name)
                            .font(Theme.brandFont(size: 28))
                        if let description = item.description, !description.isEmpty {
                            Text(description).foregroundStyle(Theme.muted)
                        }

                        metaRow(item)

                        Button {
                            showLog = true
                        } label: {
                            Label(L10n.string("todos.logWork"), systemImage: "clock.badge.plus")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(L10n.string("todos.workLog"))
                                    .font(.headline)
                                Spacer()
                                Text(formatDuration(item.totalWorkMinutes ?? 0))
                                    .foregroundStyle(Theme.muted)
                            }

                            if let logs = item.logs, !logs.isEmpty {
                                ForEach(logs) { log in
                                    HStack {
                                        AvatarView(user: log.user, size: 32)
                                        VStack(alignment: .leading) {
                                            Text(log.user.displayName).font(.subheadline.weight(.semibold))
                                            Text(formatDuration(log.durationMinutes))
                                                .font(.caption)
                                                .foregroundStyle(Theme.muted)
                                        }
                                        Spacer()
                                    }
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardFill))
                                }
                            } else {
                                Text(L10n.string("todos.noLogs"))
                                    .foregroundStyle(Theme.muted)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding(20)
                }
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showLog) {
            if item != nil {
                LogWorkView(itemId: itemId) {
                    showLog = false
                    Task {
                        await load()
                        onChange()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func metaRow(_ item: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let due = item.dueDate {
                Label(formatDate(due), systemImage: "calendar")
            }
            HStack {
                Text(L10n.string("todos.assignee"))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Menu {
                    Button(L10n.string("todos.unassigned")) {
                        Task { await setAssignee(nil) }
                    }
                    ForEach(members) { m in
                        Button(m.user.displayName) {
                            Task { await setAssignee(m.user.id) }
                        }
                    }
                } label: {
                    Text(item.assignee?.displayName ?? L10n.string("todos.unassigned"))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.cardFill))
    }

    private func load() async {
        do {
            struct Resp: Codable { let item: TodoItem }
            let resp: Resp = try await APIClient.shared.request("GET", path: "api/todo-items/\(itemId)")
            item = resp.item
            if let objectId = resp.item.objectId {
                struct ObjResp: Codable { let object: SharedObject }
                let obj: ObjResp = try await APIClient.shared.request("GET", path: "api/objects/\(objectId)")
                members = obj.object.members ?? []
            }
        } catch {}
    }

    private func setAssignee(_ id: String?) async {
        struct Body: Encodable { let assigneeId: String? }
        struct Resp: Codable { let item: TodoItem }
        do {
            let resp: Resp = try await APIClient.shared.request(
                "PATCH",
                path: "api/todo-items/\(itemId)",
                body: Body(assigneeId: id)
            )
            item = resp.item
            onChange()
        } catch {}
    }
}

struct LogWorkView: View {
    let itemId: String
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var startedAt = Date().addingTimeInterval(-3600)
    @State private var endedAt = Date()
    @State private var note = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(L10n.string("todos.started"), selection: $startedAt)
                DatePicker(L10n.string("todos.ended"), selection: $endedAt)
                TextField(L10n.string("todos.note"), text: $note, axis: .vertical)
                if let error {
                    Text(error).foregroundStyle(Theme.danger)
                }
            }
            .navigationTitle(L10n.string("todos.logWork"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common.save")) {
                        Task { await save() }
                    }
                }
            }
        }
    }

    private func save() async {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        struct Body: Encodable {
            let startedAt: String
            let endedAt: String
            let note: String?
        }
        do {
            struct Resp: Codable {
                let totalWorkMinutes: Int
            }
            let _: Resp = try await APIClient.shared.request(
                "POST",
                path: "api/todo-items/\(itemId)/logs",
                body: Body(
                    startedAt: iso.string(from: startedAt),
                    endedAt: iso.string(from: endedAt),
                    note: note.isEmpty ? nil : note
                )
            )
            onDone()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

func formatDate(_ iso: String) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = parser.date(from: iso)
    if date == nil {
        parser.formatOptions = [.withInternetDateTime]
        date = parser.date(from: iso)
    }
    guard let date else { return iso }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter.string(from: date)
}

func formatDuration(_ minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    if h == 0 { return "\(m)m" }
    return "\(h)h \(m)m"
}
