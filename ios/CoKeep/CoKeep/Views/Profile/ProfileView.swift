import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var message: String?
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                Form {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                if let user = session.user {
                                    AvatarView(user: user, size: 88)
                                }
                                PhotosPicker(selection: $photoItem, matching: .images) {
                                    Text(L10n.string("profile.changePhoto"))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }

                    Section(L10n.string("profile.details")) {
                        TextField(L10n.string("auth.firstName"), text: $firstName)
                        TextField(L10n.string("auth.lastName"), text: $lastName)
                        TextField(L10n.string("auth.email"), text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                    }

                    if let message {
                        Text(message).foregroundStyle(Theme.accent)
                    }
                    if let error {
                        Text(error).foregroundStyle(Theme.danger)
                    }

                    Section {
                        Button(L10n.string("profile.save")) {
                            Task { await save() }
                        }
                        .disabled(saving)

                        Button(L10n.string("profile.signOut"), role: .destructive) {
                            session.logout()
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(L10n.string("tab.profile"))
            .onAppear {
                firstName = session.user?.firstName ?? ""
                lastName = session.user?.lastName ?? ""
                email = session.user?.email ?? ""
            }
            .onChange(of: photoItem) { _, item in
                Task { await uploadAvatar(item) }
            }
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        let previousURL = session.user?.avatarUrl.flatMap(URL.init(string:))
        do {
            let data = try await item.jpegDataForUpload()
            let url = try await APIClient.shared.uploadImage(data)
            try await session.updateProfile(
                firstName: firstName,
                lastName: lastName,
                email: email,
                avatarUrl: url
            )
            if let previousURL {
                await ImageCache.shared.remove(for: previousURL)
            }
            message = L10n.string("profile.saved")
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await session.updateProfile(
                firstName: firstName,
                lastName: lastName,
                email: email,
                avatarUrl: session.user?.avatarUrl
            )
            message = L10n.string("profile.saved")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct AvatarView: View {
    let user: User
    var size: CGFloat = 40

    var body: some View {
        CachedRemoteImage(url: user.avatarUrl.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            initials
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: some View {
        ZStack {
            Circle().fill(Theme.accentSoft)
            Text(user.initials)
                .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accent)
        }
    }
}
