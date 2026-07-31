import SwiftUI
import PhotosUI

struct TodoListsView: View {
    let objectId: String
    @Binding var deepLinkTodoItemId: String?
    @State private var lists: [TodoList] = []
    @State private var showNewList = false
    @State private var newListName = ""
    @State private var creatingList = false
    @State private var pushedItem: Identified?

    init(objectId: String, deepLinkTodoItemId: Binding<String?> = .constant(nil)) {
        self.objectId = objectId
        self._deepLinkTodoItemId = deepLinkTodoItemId
    }

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
        .sheet(item: $pushedItem) { item in
            NavigationStack {
                TodoItemDetailView(itemId: item.id) {
                    Task { await load() }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.string("common.cancel")) {
                            pushedItem = nil
                        }
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: deepLinkTodoItemId) { _, itemId in
            guard let itemId else { return }
            pushedItem = Identified(id: itemId)
            deepLinkTodoItemId = nil
        }
        .alert(L10n.string("todos.newList"), isPresented: $showNewList) {
            TextField(L10n.string("todos.listName"), text: $newListName)
            Button(L10n.string("common.cancel"), role: .cancel) {}
            Button(L10n.string("common.save")) {
                Task { await createList() }
            }
            .disabled(creatingList || newListName.trimmingCharacters(in: .whitespaces).isEmpty)
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
            if let itemId = deepLinkTodoItemId {
                pushedItem = Identified(id: itemId)
                deepLinkTodoItemId = nil
            }
        } catch {}
    }

    private func createList() async {
        guard !creatingList else { return }
        let name = newListName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        creatingList = true
        defer { creatingList = false }
        struct Body: Encodable { let name: String }
        struct Resp: Codable { let list: TodoListSummary }
        do {
            let _: Resp = try await APIClient.shared.request(
                "POST",
                path: "api/objects/\(objectId)/todo-lists",
                body: Body(name: name)
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
    @State private var confirmDeleteList = false
    @State private var deletingList = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.todoListName(list.name))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let count = list.unreadAlertCount, count > 0 {
                    AlertBadgeView(count: count)
                }
                Spacer()
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
            .contextMenu {
                Button(L10n.string("todos.deleteList"), role: .destructive) {
                    confirmDeleteList = true
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
        .confirmationDialog(
            L10n.string("todos.deleteListConfirm"),
            isPresented: $confirmDeleteList,
            titleVisibility: .visible
        ) {
            Button(L10n.string("common.delete"), role: .destructive) {
                Task { await deleteList() }
            }
            Button(L10n.string("common.cancel"), role: .cancel) {}
        }
        .opacity(deletingList ? 0.5 : 1)
    }

    private func deleteList() async {
        guard !deletingList else { return }
        deletingList = true
        defer { deletingList = false }
        struct Ok: Codable { let ok: Bool? }
        do {
            let _: Ok = try await APIClient.shared.request("DELETE", path: "api/todo-lists/\(list.id)")
            onChange()
        } catch {}
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
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .strikethrough(item.isDone)
                        .foregroundStyle(dimmed ? Theme.muted : Theme.ink)
                    if item.hasUnreadAlert == true {
                        AlertDotView()
                    }
                }
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
    @EnvironmentObject private var session: SessionStore

    @State private var name = ""
    @State private var description = ""
    @State private var scheduleType = "ONE_OFF"
    @State private var dueDate = Date()
    @State private var hasDueDate = false
    @State private var recurrence = "MONTHLY"
    @State private var members: [ObjectMember] = []
    @State private var assigneeId: String?
    @State private var error: String?
    @State private var loading = false

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
            .disabled(loading)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                        .disabled(loading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    BusyToolbarButton(
                        title: L10n.string("common.save"),
                        enabled: !name.trimmingCharacters(in: .whitespaces).isEmpty,
                        loading: loading
                    ) {
                        Task { await save() }
                    }
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
            // Default responsible person to the current user so due pushes have a recipient.
            if assigneeId == nil, let me = session.user?.id,
               members.contains(where: { $0.user.id == me }) {
                assigneeId = me
            }
        } catch {}
    }

    private func save() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        struct Body: Encodable {
            let name: String
            let description: String?
            let scheduleType: String
            let dueDate: String?
            let recurrence: String?
            let assigneeId: String?
        }
        do {
            struct Resp: Codable { let item: TodoItem }
            let _: Resp = try await APIClient.shared.request(
                "POST",
                path: "api/todo-lists/\(listId)/items",
                body: Body(
                    name: name,
                    description: description.isEmpty ? nil : description,
                    scheduleType: scheduleType,
                    dueDate: hasDueDate ? Self.noonUtcISOString(from: dueDate) : nil,
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

    /// Stores date-only due dates as noon UTC of the selected local calendar day.
    private static func noonUtcISOString(from date: Date) -> String {
        let local = Calendar.current.dateComponents([.year, .month, .day], from: date)
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        var parts = DateComponents()
        parts.year = local.year
        parts.month = local.month
        parts.day = local.day
        parts.hour = 12
        let noon = utcCal.date(from: parts) ?? date
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.string(from: noon)
    }
}

struct TodoItemDetailView: View {
    let itemId: String
    var onChange: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var item: TodoItem?
    @State private var showLog = false
    @State private var selectedLog: WorkLogEntry?
    @State private var showEditItem = false
    @State private var showAddPhoto = false
    @State private var selectedPhoto: TodoItemPhoto?
    @State private var members: [ObjectMember] = []
    @State private var confirmDelete = false
    @State private var deleting = false

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
                        .disabled(deleting)

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
                                    Button {
                                        selectedLog = log
                                    } label: {
                                        HStack {
                                            AvatarView(user: log.user, size: 32)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(log.user.displayName).font(.subheadline.weight(.semibold))
                                                Text(formatDuration(log.durationMinutes))
                                                    .font(.caption)
                                                    .foregroundStyle(Theme.muted)
                                                Text(formatLogDateRange(startedAt: log.startedAt, endedAt: log.endedAt))
                                                    .font(.caption2)
                                                    .foregroundStyle(Theme.muted)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(Theme.muted)
                                        }
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardFill))
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                Text(L10n.string("todos.noLogs"))
                                    .foregroundStyle(Theme.muted)
                                    .font(.subheadline)
                            }
                        }

                        if let photos = item.photos, !photos.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label(L10n.string("todos.photos"), systemImage: "photo")
                                        .font(.headline)
                                    Spacer()
                                    Button {
                                        showAddPhoto = true
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(photos) { photo in
                                            Button {
                                                selectedPhoto = photo
                                            } label: {
                                                CachedRemoteImage(url: URL(string: photo.imageUrl)) { image in
                                                    image.resizable().scaledToFill()
                                                } placeholder: {
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(Theme.cardFill)
                                                }
                                                .frame(width: 100, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            HStack {
                                Label(L10n.string("todos.photos"), systemImage: "photo")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.muted)
                                Spacer()
                                Button {
                                    showAddPhoto = true
                                } label: {
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        Button(L10n.string("todos.deleteItem"), role: .destructive) {
                            confirmDelete = true
                        }
                        .disabled(deleting)
                        .padding(.top, 8)
                    }
                    .padding(20)
                }
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditItem = true
                } label: {
                    Text(L10n.string("todos.editItem"))
                }
                .disabled(deleting)
            }
        }
        .task {
            await load()
            await BadgeStore.shared.markTodoViewed(itemId)
            onChange()
        }
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
        .sheet(item: $selectedLog) { log in
            if item != nil {
                WorkLogDetailView(itemId: itemId, log: log) {
                    selectedLog = nil
                    Task {
                        await load()
                        onChange()
                    }
                }
            }
        }
        .sheet(isPresented: $showEditItem) {
            if let item {
                EditTodoItemView(item: item, objectId: item.objectId ?? "") {
                    showEditItem = false
                    Task {
                        await load()
                        onChange()
                    }
                }
            }
        }
        .sheet(isPresented: $showAddPhoto) {
            if item != nil {
                AddTodoPhotoView(itemId: itemId) {
                    showAddPhoto = false
                    Task {
                        await load()
                        onChange()
                    }
                }
            }
        }
        .sheet(item: $selectedPhoto) { photo in
            if item != nil {
                TodoPhotoDetailView(itemId: itemId, photo: photo) {
                    selectedPhoto = nil
                    Task {
                        await load()
                        onChange()
                    }
                }
            }
        }
        .confirmationDialog(
            L10n.string("todos.deleteItemConfirm"),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(L10n.string("common.delete"), role: .destructive) {
                Task { await deleteItem() }
            }
            Button(L10n.string("common.cancel"), role: .cancel) {}
        }
    }

    private func deleteItem() async {
        guard !deleting else { return }
        deleting = true
        defer { deleting = false }
        struct Ok: Codable { let ok: Bool? }
        do {
            let _: Ok = try await APIClient.shared.request("DELETE", path: "api/todo-items/\(itemId)")
            onChange()
            dismiss()
        } catch {}
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

    @State private var startedAt: Date
    @State private var endedAt: Date
    @State private var note = ""
    @State private var error: String?
    @State private var loading = false

    private var canSave: Bool {
        endedAt > startedAt
    }

    init(itemId: String, onDone: @escaping () -> Void) {
        self.itemId = itemId
        self.onDone = onDone
        let start = Date().addingTimeInterval(-3600)
        _startedAt = State(initialValue: start)
        _endedAt = State(initialValue: start.addingTimeInterval(3600))
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(L10n.string("todos.started"), selection: $startedAt)
                    .onChange(of: startedAt) { _, newValue in
                        endedAt = newValue.addingTimeInterval(3600)
                    }
                DatePicker(L10n.string("todos.ended"), selection: $endedAt)

                TextField(L10n.string("todos.note"), text: $note, axis: .vertical)
                if !canSave {
                    Text(L10n.string("todos.endBeforeStart"))
                        .foregroundStyle(Theme.danger)
                }
                if let error {
                    Text(error).foregroundStyle(Theme.danger)
                }
            }
            .navigationTitle(L10n.string("todos.logWork"))
            .disabled(loading)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                        .disabled(loading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    BusyToolbarButton(
                        title: L10n.string("common.save"),
                        enabled: canSave,
                        loading: loading
                    ) {
                        Task { await save() }
                    }
                }
            }
        }
    }

    private func save() async {
        guard !loading, canSave else { return }

        loading = true
        defer { loading = false }
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

struct WorkLogDetailView: View {
    let itemId: String
    let log: WorkLogEntry
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var deleting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        AvatarView(user: log.user, size: 48)
                        VStack(alignment: .leading) {
                            Text(log.user.displayName)
                                .font(.headline)
                            Text(formatDuration(log.durationMinutes))
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Time Range")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                        Text(formatLogDateRange(startedAt: log.startedAt, endedAt: log.endedAt))
                            .font(.body)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.cardFill))

                    if let note = log.note, !note.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.string("todos.note"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.muted)
                            Text(note)
                                .font(.body)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.cardFill))
                    }

                    if session.user?.id == log.user.id {
                        Button {
                            showEdit = true
                        } label: {
                            Label(L10n.string("todos.editLog"), systemImage: "pencil")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(deleting)

                        Button(L10n.string("todos.deleteLog"), role: .destructive) {
                            confirmDelete = true
                        }
                        .disabled(deleting)
                        .padding(.top, 8)
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L10n.string("todos.workLog"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                        .disabled(deleting)
                }
            }
            .sheet(isPresented: $showEdit) {
                EditWorkLogView(itemId: itemId, log: log) {
                    showEdit = false
                    onDone()
                }
            }
            .confirmationDialog(
                L10n.string("todos.deleteLogConfirm"),
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button(L10n.string("common.delete"), role: .destructive) {
                    Task { await deleteLog() }
                }
                Button(L10n.string("common.cancel"), role: .cancel) {}
            }
        }
    }

    private func deleteLog() async {
        guard !deleting else { return }
        deleting = true
        defer { deleting = false }
        struct Ok: Codable { let ok: Bool? }
        do {
            let _: Ok = try await APIClient.shared.request("DELETE", path: "api/work-logs/\(log.id)")
            onDone()
            dismiss()
        } catch {}
    }
}

struct EditWorkLogView: View {
    let itemId: String
    let log: WorkLogEntry
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var startedAt: Date
    @State private var endedAt: Date
    @State private var note: String
    @State private var error: String?
    @State private var loading = false

    private var canSave: Bool {
        endedAt > startedAt
    }

    init(itemId: String, log: WorkLogEntry, onDone: @escaping () -> Void) {
        self.itemId = itemId
        self.log = log
        self.onDone = onDone
        _startedAt = State(initialValue: parseISODate(log.startedAt) ?? Date())
        _endedAt = State(initialValue: parseISODate(log.endedAt) ?? Date())
        _note = State(initialValue: log.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(L10n.string("todos.started"), selection: $startedAt)
                DatePicker(L10n.string("todos.ended"), selection: $endedAt)
                TextField(L10n.string("todos.note"), text: $note, axis: .vertical)
                if !canSave {
                    Text(L10n.string("todos.endBeforeStart"))
                        .foregroundStyle(Theme.danger)
                }
                if let error {
                    Text(error).foregroundStyle(Theme.danger)
                }
            }
            .navigationTitle(L10n.string("todos.editLog"))
            .disabled(loading)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                        .disabled(loading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    BusyToolbarButton(
                        title: L10n.string("common.save"),
                        enabled: canSave,
                        loading: loading
                    ) {
                        Task { await save() }
                    }
                }
            }
        }
    }

    private func save() async {
        guard !loading, canSave else { return }

        loading = true
        defer { loading = false }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        struct Body: Encodable {
            let startedAt: String
            let endedAt: String
            let note: String?
        }
        do {
            struct Resp: Codable {
                struct Log: Codable {
                    let id: String
                }
                let log: Log
            }
            let _: Resp = try await APIClient.shared.request(
                "PATCH",
                path: "api/work-logs/\(log.id)",
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

struct EditTodoItemView: View {
    let item: TodoItem
    let objectId: String
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var name: String
    @State private var description: String
    @State private var scheduleType: String
    @State private var dueDate: Date
    @State private var hasDueDate: Bool
    @State private var recurrence: String
    @State private var members: [ObjectMember] = []
    @State private var assigneeId: String?
    @State private var error: String?
    @State private var loading = false

    init(item: TodoItem, objectId: String, onDone: @escaping () -> Void) {
        self.item = item
        self.objectId = objectId
        self.onDone = onDone
        _name = State(initialValue: item.name)
        _description = State(initialValue: item.description ?? "")
        _scheduleType = State(initialValue: item.scheduleType)
        _hasDueDate = State(initialValue: item.dueDate != nil)
        _dueDate = State(initialValue: parseISODate(item.dueDate ?? "") ?? Date())
        _recurrence = State(initialValue: item.recurrence ?? "MONTHLY")
        _assigneeId = State(initialValue: item.assigneeId)
    }

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
            .navigationTitle(L10n.string("todos.editItem"))
            .disabled(loading)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                        .disabled(loading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    BusyToolbarButton(
                        title: L10n.string("common.save"),
                        enabled: !name.trimmingCharacters(in: .whitespaces).isEmpty,
                        loading: loading
                    ) {
                        Task { await save() }
                    }
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
        guard !loading else { return }
        loading = true
        defer { loading = false }
        struct Body: Encodable {
            let name: String
            let description: String?
            let scheduleType: String
            let dueDate: String?
            let recurrence: String?
            let assigneeId: String?
        }
        do {
            struct Resp: Codable { let item: TodoItem }
            let _: Resp = try await APIClient.shared.request(
                "PATCH",
                path: "api/todo-items/\(item.id)",
                body: Body(
                    name: name,
                    description: description.isEmpty ? nil : description,
                    scheduleType: scheduleType,
                    dueDate: hasDueDate ? noonUtcISOString(from: dueDate) : nil,
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

    private func noonUtcISOString(from date: Date) -> String {
        let local = Calendar.current.dateComponents([.year, .month, .day], from: date)
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        var parts = DateComponents()
        parts.year = local.year
        parts.month = local.month
        parts.day = local.day
        parts.hour = 12
        let noon = utcCal.date(from: parts) ?? date
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.string(from: noon)
    }
}

struct AddTodoPhotoView: View {
    let itemId: String
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedItem: PhotosPickerItem?
    @State private var caption = ""
    @State private var uploading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(L10n.string("todos.addPhoto"), systemImage: "photo.on.rectangle")
                }
                
                if selectedItem != nil {
                    TextField(L10n.string("todos.photoCaption"), text: $caption, axis: .vertical)
                        .lineLimit(2...4)
                }
                
                if let error {
                    Text(error).foregroundStyle(Theme.danger)
                }
            }
            .navigationTitle(L10n.string("todos.addPhoto"))
            .disabled(uploading)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                        .disabled(uploading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    BusyToolbarButton(
                        title: L10n.string("common.save"),
                        enabled: selectedItem != nil,
                        loading: uploading
                    ) {
                        Task { await save() }
                    }
                }
            }
        }
    }

    private func save() async {
        guard !uploading, let item = selectedItem else { return }
        uploading = true
        defer { uploading = false }

        do {
            let jpegData = try await item.jpegDataForUpload()
            let imageUrl = try await APIClient.shared.uploadImage(jpegData, filename: "photo.jpg")

            struct Body: Encodable {
                let imageUrl: String
                let caption: String?
            }
            struct Resp: Codable {
                struct Photo: Codable { let id: String }
                let photo: Photo
            }
            let _: Resp = try await APIClient.shared.request(
                "POST",
                path: "api/todo-items/\(itemId)/photos",
                body: Body(
                    imageUrl: imageUrl,
                    caption: caption.isEmpty ? nil : caption
                )
            )
            onDone()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct TodoPhotoDetailView: View {
    let itemId: String
    let photo: TodoItemPhoto
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var confirmDelete = false
    @State private var deleting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    CachedRemoteImage(url: URL(string: photo.imageUrl)) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    if let caption = photo.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                    }
                    
                    Button(L10n.string("todos.deletePhoto"), role: .destructive) {
                        confirmDelete = true
                    }
                    .disabled(deleting)
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L10n.string("todos.photos"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                        .disabled(deleting)
                }
            }
            .confirmationDialog(
                L10n.string("todos.deletePhotoConfirm"),
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button(L10n.string("common.delete"), role: .destructive) {
                    Task { await deletePhoto() }
                }
                Button(L10n.string("common.cancel"), role: .cancel) {}
            }
        }
    }

    private func deletePhoto() async {
        guard !deleting else { return }
        deleting = true
        defer { deleting = false }
        struct Ok: Codable { let ok: Bool? }
        do {
            let _: Ok = try await APIClient.shared.request("DELETE", path: "api/todo-item-photos/\(photo.id)")
            onDone()
            dismiss()
        } catch {}
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

func formatLogDateRange(startedAt: String, endedAt: String) -> String {
    guard let start = parseISODate(startedAt),
          let end = parseISODate(endedAt) else {
        return "\(startedAt) - \(endedAt)"
    }
    
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .none
    
    let timeFormatter = DateFormatter()
    timeFormatter.dateStyle = .none
    timeFormatter.timeStyle = .short
    
    let calendar = Calendar.current
    let isSameDay = calendar.isDate(start, inSameDayAs: end)
    
    if isSameDay {
        return "\(dateFormatter.string(from: start)) • \(timeFormatter.string(from: start)) - \(timeFormatter.string(from: end))"
    } else {
        return "\(dateFormatter.string(from: start)) \(timeFormatter.string(from: start)) - \(dateFormatter.string(from: end)) \(timeFormatter.string(from: end))"
    }
}

func parseISODate(_ iso: String) -> Date? {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = parser.date(from: iso)
    if date == nil {
        parser.formatOptions = [.withInternetDateTime]
        date = parser.date(from: iso)
    }
    return date
}

private struct Identified: Identifiable, Hashable {
    let id: String
}
