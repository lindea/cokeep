import SwiftUI
import PhotosUI

struct ObjectDetailView: View {
    let objectId: String
    @Binding var deepLinkTodoItemId: String?
    @State private var object: SharedObject?
    @State private var selectedTab = 0
    @State private var showInvite = false
    @State private var photoItem: PhotosPickerItem?
    @State private var uploadingImage = false

    init(objectId: String, deepLinkTodoItemId: Binding<String?> = .constant(nil)) {
        self.objectId = objectId
        self._deepLinkTodoItemId = deepLinkTodoItemId
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if let object {
                VStack(spacing: 0) {
                    header(object)

                    Picker("", selection: $selectedTab) {
                        Text(L10n.string("object.todos")).tag(0)
                        Text(L10n.string("object.costs")).tag(1)
                        Text(L10n.string("object.reports")).tag(2)
                        Text(L10n.string("object.people")).tag(3)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    TabView(selection: $selectedTab) {
                        TodoListsView(objectId: objectId, deepLinkTodoItemId: $deepLinkTodoItemId)
                            .tag(0)
                        CostsView(objectId: objectId)
                            .tag(1)
                        ReportsView(objectId: objectId)
                            .tag(2)
                        MembersView(object: object) {
                            Task { await load() }
                        }
                        .tag(3)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showInvite = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showInvite) {
            InviteUserView(objectId: objectId)
        }
        .onChange(of: photoItem) { _, item in
            Task { await updateImage(item) }
        }
        .task { await load() }
        .onChange(of: deepLinkTodoItemId) { _, itemId in
            if itemId != nil {
                selectedTab = 0
            }
        }
    }

    @ViewBuilder
    private func header(_ object: SharedObject) -> some View {
        HStack(spacing: 14) {
            objectHeaderImage(object)
            VStack(alignment: .leading, spacing: 2) {
                Text(object.name)
                    .font(Theme.brandFont(size: 24))
                    .foregroundStyle(Theme.ink)
                Text(object.template == "CABIN" ? L10n.string("template.cabin") : L10n.string("template.generic"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func objectHeaderImage(_ object: SharedObject) -> some View {
        let imageView = ObjectImage(url: object.imageUrl, template: object.template)
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if uploadingImage {
                    ProgressView()
                }
            }

        if object.role == "OWNER" {
            imageView
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Circle().fill(Theme.accent))
                        .offset(x: 4, y: 4)
                }
                .overlay {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Color.clear
                    }
                }
                .contextMenu {
                    if object.imageUrl != nil {
                        Button(L10n.string("objects.removePhoto"), role: .destructive) {
                            Task { await setImageUrl(nil) }
                        }
                    }
                }
        } else {
            imageView
        }
    }

    private func updateImage(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        uploadingImage = true
        defer {
            uploadingImage = false
            photoItem = nil
        }
        do {
            let url = try await APIClient.shared.uploadImage(data)
            await setImageUrl(url)
        } catch {
            // keep previous image
        }
    }

    private func setImageUrl(_ url: String?) async {
        struct Body: Encodable {
            let imageUrl: String?
        }
        struct Resp: Codable { let object: SharedObject }
        do {
            let resp: Resp = try await APIClient.shared.request(
                "PATCH",
                path: "api/objects/\(objectId)",
                body: Body(imageUrl: url)
            )
            var updated = resp.object
            updated.role = object?.role ?? updated.role
            updated.members = object?.members ?? updated.members
            object = updated
        } catch {
            // keep previous
        }
    }

    private func load() async {
        do {
            struct Resp: Codable { let object: SharedObject }
            let resp: Resp = try await APIClient.shared.request("GET", path: "api/objects/\(objectId)")
            object = resp.object
        } catch {
            // keep previous
        }
    }
}

struct MembersView: View {
    let object: SharedObject
    var onChange: () -> Void
    @EnvironmentObject private var session: SessionStore
    @State private var error: String?

    var body: some View {
        List {
            if let members = object.members {
                ForEach(members) { member in
                    HStack(spacing: 12) {
                        AvatarView(user: member.user, size: 40)
                        VStack(alignment: .leading) {
                            Text(member.user.displayName).font(.headline)
                            Text(member.role == "OWNER" ? L10n.string("role.owner") : L10n.string("role.member"))
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if object.role == "OWNER", member.user.id != session.user?.id {
                            Button(L10n.string("members.remove"), role: .destructive) {
                                Task { await remove(member.user.id) }
                            }
                            .font(.caption)
                        }
                    }
                }
            }

            Section {
                Button(L10n.string("members.leave"), role: .destructive) {
                    Task { await leave() }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func remove(_ userId: String) async {
        struct Ok: Codable { let ok: Bool? }
        do {
            let _: Ok = try await APIClient.shared.request(
                "DELETE",
                path: "api/objects/\(object.id)/members/\(userId)"
            )
            onChange()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func leave() async {
        struct Ok: Codable { let ok: Bool? }
        do {
            let _: Ok = try await APIClient.shared.request(
                "POST",
                path: "api/objects/\(object.id)/leave"
            )
            onChange()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

import SwiftUI
import ContactsUI

struct InviteUserView: View {
    let objectId: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @State private var country = CountryCode.common[0]
    @State private var phone = ""
    @State private var message: String?
    @State private var error: String?
    @State private var loading = false
    @State private var showContacts = false
    @State private var objectName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                Form {
                    Section(L10n.string("invite.phoneSection")) {
                        Picker(L10n.string("auth.country"), selection: $country) {
                            ForEach(CountryCode.common) { c in
                                Text("\(c.flag) \(c.code)").tag(c)
                            }
                        }
                        TextField(L10n.string("auth.phonePlaceholder"), text: $phone)
                            .keyboardType(.phonePad)

                        Button {
                            showContacts = true
                        } label: {
                            Label(L10n.string("invite.fromContacts"), systemImage: "person.crop.circle.badge.plus")
                        }
                    }

                    if let message {
                        Text(message).foregroundStyle(Theme.accent)
                    }
                    if let error {
                        Text(error).foregroundStyle(Theme.danger)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(L10n.string("invite.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("invite.send")) {
                        Task { await send() }
                    }
                    .disabled(phone.isEmpty || loading)
                }
            }
            .sheet(isPresented: $showContacts) {
                ContactPhonePicker { selected in
                    phone = selected
                    showContacts = false
                }
            }
            .task { await loadObjectName() }
        }
    }

    private func loadObjectName() async {
        do {
            struct Resp: Codable { let object: SharedObject }
            let resp: Resp = try await APIClient.shared.request("GET", path: "api/objects/\(objectId)")
            objectName = resp.object.name
        } catch {}
    }

    private func send() async {
        loading = true
        defer { loading = false }
        do {
            struct Body: Encodable {
                let phone: String
                let countryCode: String
            }
            struct Resp: Codable {
                struct InviteResult: Codable {
                    let recipientExists: Bool
                    let inviteUrl: String?
                }
                let invite: InviteResult
            }
            let resp: Resp = try await APIClient.shared.request(
                "POST",
                path: "api/invites/objects/\(objectId)/invites",
                body: Body(phone: phone, countryCode: country.code)
            )
            if resp.invite.recipientExists {
                message = L10n.string("invite.sentPush")
            } else if let inviteUrl = resp.invite.inviteUrl {
                let inviterName = session.user?.firstName ?? L10n.string("invite.someone")
                let body = L10n.inviteSmsBody(
                    inviterName: inviterName,
                    objectName: objectName.isEmpty ? L10n.string("invite.objectFallback") : objectName,
                    link: inviteUrl
                )
                openSms(phone: phone, body: body)
                message = L10n.string("invite.sentSms")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func openSms(phone: String, body: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        var components = URLComponents()
        components.scheme = "sms"
        components.path = digits
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }
}

/// Native contact picker that returns a phone number string.
struct ContactPhonePicker: UIViewControllerRepresentable {
    var onSelect: (String) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: (String) -> Void
        init(onSelect: @escaping (String) -> Void) { self.onSelect = onSelect }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            if let number = contact.phoneNumbers.first?.value.stringValue {
                let digits = number.filter { $0.isNumber || $0 == "+" }
                onSelect(digits)
            }
        }
    }
}

struct PendingInvitesView: View {
    @State private var invites: [Invite] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if loading {
                    ProgressView()
                } else if invites.isEmpty {
                    ContentUnavailableView(
                        L10n.string("invites.empty"),
                        systemImage: "tray",
                        description: Text(L10n.string("invites.emptyBody"))
                    )
                } else {
                    List(invites) { invite in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(invite.object.name).font(.headline)
                            Text(L10n.string("invites.from") + " " + invite.invitedBy.displayName)
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                            HStack {
                                Button(L10n.string("invites.accept")) {
                                    Task { await respond(invite.id, accept: true) }
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                Button(L10n.string("invites.decline")) {
                                    Task { await respond(invite.id, accept: false) }
                                }
                                .buttonStyle(PrimaryButtonStyle(filled: false))
                            }
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(Theme.cardFill)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(L10n.string("tab.invites"))
            .task {
                await load()
                await BadgeStore.shared.markInvitesViewed()
            }
            .refreshable { await load() }
        }
    }

    private func load() async {
        loading = invites.isEmpty
        defer { loading = false }
        do {
            struct Resp: Codable { let invites: [Invite] }
            let resp: Resp = try await APIClient.shared.request("GET", path: "api/invites/pending")
            invites = resp.invites
            await BadgeStore.shared.refresh()
        } catch {}
    }

    private func respond(_ id: String, accept: Bool) async {
        struct Body: Encodable { let accept: Bool }
        struct Ok: Codable { let ok: Bool? }
        do {
            let _: Ok = try await APIClient.shared.request(
                "POST",
                path: "api/invites/\(id)/respond",
                body: Body(accept: accept)
            )
            await load()
            await BadgeStore.shared.refresh()
        } catch {}
    }
}
