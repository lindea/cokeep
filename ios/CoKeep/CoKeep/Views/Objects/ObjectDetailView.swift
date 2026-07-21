import SwiftUI
import PhotosUI
import ContactsUI

struct ObjectDetailView: View {
    let objectId: String
    @Binding var deepLinkTodoItemId: String?
    @State private var object: SharedObject?
    @State private var selectedTab = 0
    @State private var showInvite = false
    @State private var photoItem: PhotosPickerItem?
    @State private var uploadingImage = false
    @State private var imageError: String?

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
                    if let imageError {
                        Text(imageError)
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                    }

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
                    ZStack {
                        Color.black.opacity(0.35)
                        ProgressView().tint(.white)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

        if object.role == "OWNER" {
            PhotosPicker(selection: $photoItem, matching: .images) {
                imageView
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Circle().fill(Theme.accent))
                            .offset(x: 4, y: 4)
                    }
            }
            .disabled(uploadingImage)
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
        guard let item else { return }
        imageError = nil
        uploadingImage = true
        defer {
            uploadingImage = false
            photoItem = nil
        }
        do {
            let data = try await item.jpegDataForUpload()
            let url = try await APIClient.shared.uploadImage(data)
            await setImageUrl(url)
        } catch {
            imageError = error.localizedDescription.isEmpty
                ? L10n.string("objects.photoUploadFailed")
                : error.localizedDescription
        }
    }

    private func setImageUrl(_ url: String?) async {
        struct Body: Encodable {
            let imageUrl: String?
        }
        struct Resp: Codable { let object: SharedObject }
        let previousURL = object?.imageUrl.flatMap(URL.init(string:))
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
            if let previousURL {
                await ImageCache.shared.remove(for: previousURL)
            }
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
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var confirmDeleteObject = false
    @State private var busy = false

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
                            .disabled(busy)
                        }
                    }
                }
            }

            Section {
                Button(L10n.string("members.leave"), role: .destructive) {
                    Task { await leave() }
                }
                .disabled(busy)

                if object.role == "OWNER" {
                    Button(L10n.string("objects.delete"), role: .destructive) {
                        confirmDeleteObject = true
                    }
                    .disabled(busy)
                }
            }

            if let error {
                Text(error).foregroundStyle(Theme.danger)
            }
        }
        .scrollContentBackground(.hidden)
        .confirmationDialog(
            L10n.string("objects.deleteConfirm"),
            isPresented: $confirmDeleteObject,
            titleVisibility: .visible
        ) {
            Button(L10n.string("common.delete"), role: .destructive) {
                Task { await deleteObject() }
            }
            Button(L10n.string("common.cancel"), role: .cancel) {}
        }
    }

    private func remove(_ userId: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
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
        guard !busy else { return }
        busy = true
        defer { busy = false }
        struct Ok: Codable { let ok: Bool? }
        do {
            let _: Ok = try await APIClient.shared.request(
                "POST",
                path: "api/objects/\(object.id)/leave"
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteObject() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        struct Ok: Codable { let ok: Bool? }
        do {
            let _: Ok = try await APIClient.shared.request(
                "DELETE",
                path: "api/objects/\(object.id)"
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

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
    @State private var pendingContactPhone: String?
    @State private var objectName = ""
    /// Non-user invite: explain + share TestFlight, then close.
    @State private var showNotOnCokeepAlert = false
    @State private var pendingShareText: String?
    @State private var pendingShareLink: String?
    @State private var showShareSheet = false

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
                        .disabled(loading)
                    }

                    if let message {
                        Text(message).foregroundStyle(Theme.accent)
                    }
                    if let error {
                        Text(error).foregroundStyle(Theme.danger)
                    }
                }
                .scrollContentBackground(.hidden)
                .disabled(loading)
            }
            .navigationTitle(L10n.string("invite.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                        .disabled(loading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    BusyToolbarButton(
                        title: L10n.string("invite.send"),
                        enabled: !phone.trimmingCharacters(in: .whitespaces).isEmpty,
                        loading: loading
                    ) {
                        Task { await send() }
                    }
                }
            }
            // fullScreenCover avoids the nested-sheet bug where selecting a contact
            // dismisses the invite sheet without applying the phone number.
            .fullScreenCover(isPresented: $showContacts, onDismiss: {
                if let pending = pendingContactPhone {
                    applyContactPhone(pending)
                    pendingContactPhone = nil
                }
            }) {
                ContactPhonePicker(isPresented: $showContacts) { selected in
                    pendingContactPhone = selected
                }
            }
            .alert(
                L10n.string("invite.title"),
                isPresented: $showNotOnCokeepAlert
            ) {
                Button(L10n.string("invite.shareTestFlight")) {
                    showShareSheet = true
                }
                Button(L10n.string("invite.copyLink")) {
                    if let pendingShareLink {
                        UIPasteboard.general.string = pendingShareLink
                    }
                    dismiss()
                }
                Button(L10n.string("common.done"), role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(L10n.string("invite.notOnCokeep"))
            }
            .sheet(isPresented: $showShareSheet, onDismiss: {
                dismiss()
            }) {
                if let pendingShareText {
                    ActivityShareSheet(items: [pendingShareText])
                        .presentationDetents([.medium, .large])
                }
            }
            .task { await loadObjectName() }
        }
    }

    private func applyContactPhone(_ raw: String) {
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        if digits.hasPrefix("+") {
            let sorted = CountryCode.common.sorted { $0.code.count > $1.code.count }
            for code in sorted where digits.hasPrefix(code.code) {
                country = code
                phone = String(digits.dropFirst(code.code.count))
                return
            }
        }
        phone = digits.filter { $0.isNumber }
    }

    private func loadObjectName() async {
        do {
            struct Resp: Codable { let object: SharedObject }
            let resp: Resp = try await APIClient.shared.request("GET", path: "api/objects/\(objectId)")
            objectName = resp.object.name
        } catch {}
    }

    private func send() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        message = nil
        error = nil
        pendingShareText = nil
        pendingShareLink = nil
        do {
            struct Body: Encodable {
                let phone: String
                let countryCode: String
            }
            struct Resp: Codable {
                struct InviteResult: Codable {
                    let recipientExists: Bool
                    let inviteUrl: String?
                    let downloadUrl: String?
                    let openMessages: Bool?
                }
                let invite: InviteResult
            }
            let resp: Resp = try await APIClient.shared.request(
                "POST",
                path: "api/invites/objects/\(objectId)/invites",
                body: Body(phone: phone, countryCode: country.code)
            )
            if resp.invite.recipientExists {
                dismiss()
                return
            }

            let inviterName = session.user?.firstName ?? L10n.string("invite.someone")
            let objectLabel = objectName.isEmpty ? L10n.string("invite.objectFallback") : objectName
            let link = Self.resolveInstallLink(
                downloadUrl: resp.invite.downloadUrl,
                inviteUrl: resp.invite.inviteUrl,
                openMessages: resp.invite.openMessages
            )
            let shareBody = L10n.inviteShareBody(
                inviterName: inviterName,
                objectName: objectLabel,
                link: link
            )

            // Beta default: share TestFlight in-app. After App Store launch, backend can
            // set openMessages=true to restore auto-SMS with the store link.
            if resp.invite.openMessages == true {
                let smsBody = L10n.inviteSmsBody(
                    inviterName: inviterName,
                    objectName: objectLabel,
                    link: link
                )
                openSms(phone: phone, body: smsBody)
                dismiss()
            } else {
                pendingShareLink = link
                pendingShareText = shareBody
                showNotOnCokeepAlert = true
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Public TestFlight join link used while the app is not on the App Store.
    private static let testFlightURL = "https://testflight.apple.com/join/gnRXHXyC"

    private static func resolveInstallLink(
        downloadUrl: String?,
        inviteUrl: String?,
        openMessages: Bool?
    ) -> String {
        let candidates = [downloadUrl, inviteUrl].compactMap { $0 }
        if openMessages == true {
            return candidates.first ?? testFlightURL
        }
        // Share-only (beta): never hand out an App Store URL.
        if let url = candidates.first(where: { !$0.contains("apps.apple.com") }) {
            return url
        }
        return testFlightURL
    }

    private func openSms(phone: String, body: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        let full = digits.hasPrefix("+") ? digits : "\(country.code)\(digits)"
        var components = URLComponents()
        components.scheme = "sms"
        components.path = full
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }
}

/// System share sheet wrapper.
private struct ActivityShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Native contact picker that returns a phone number string.
/// Presented via fullScreenCover (not a nested sheet) so the invite form stays mounted.
/// The picker is presented from a host VC — CNContactPicker does not work well as the
/// root of a SwiftUI fullScreenCover by itself.
struct ContactPhonePicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onSelect: (String) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.backgroundColor = .systemBackground
        return host
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, !context.coordinator.isShowingPicker else { return }

        // Defer until the host is in a window; fullScreenCover can call update before that.
        DispatchQueue.main.async {
            guard context.coordinator.parent.isPresented,
                  !context.coordinator.isShowingPicker,
                  uiViewController.view.window != nil
            else { return }

            context.coordinator.isShowingPicker = true
            let picker = CNContactPickerViewController()
            picker.delegate = context.coordinator
            picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
            picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
            uiViewController.present(picker, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPhonePicker
        var isShowingPicker = false
        init(parent: ContactPhonePicker) { self.parent = parent }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            if let number = contact.phoneNumbers.first?.value.stringValue {
                let digits = number.filter { $0.isNumber || $0 == "+" }
                parent.onSelect(digits)
            }
            close()
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            close()
        }

        private func close() {
            isShowingPicker = false
            parent.isPresented = false
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
