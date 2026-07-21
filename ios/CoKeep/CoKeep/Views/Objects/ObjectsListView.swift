import SwiftUI
import PhotosUI

struct ObjectsListView: View {
    @Binding var deepLinkObjectId: String?
    @Binding var deepLinkTodoItemId: String?
    @State private var objects: [SharedObject] = []
    @State private var loading = true
    @State private var showCreate = false
    @State private var error: String?
    @State private var appear = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.background.ignoresSafeArea()

                if loading {
                    ProgressView()
                } else if objects.isEmpty {
                    EmptyObjectsView { showCreate = true }
                        .opacity(appear ? 1 : 0)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(Array(objects.enumerated()), id: \.element.id) { index, object in
                                NavigationLink(value: object) {
                                    ObjectRow(object: object)
                                }
                                .buttonStyle(.plain)
                                .offset(y: appear ? 0 : 16)
                                .opacity(appear ? 1 : 0)
                                .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(Double(index) * 0.05), value: appear)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("CoKeep")
            .navigationDestination(for: SharedObject.self) { object in
                ObjectDetailView(
                    objectId: object.id,
                    deepLinkTodoItemId: Binding(
                        get: { deepLinkObjectId == object.id ? deepLinkTodoItemId : nil },
                        set: { deepLinkTodoItemId = $0 }
                    )
                )
                .onDisappear { Task { await load() } }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateObjectView {
                    showCreate = false
                    Task { await load() }
                }
            }
            .task {
                await load()
                withAnimation { appear = true }
            }
            .refreshable { await load() }
            .onChange(of: deepLinkObjectId) { _, objectId in
                guard let objectId, let object = objects.first(where: { $0.id == objectId }) else { return }
                path = NavigationPath()
                path.append(object)
            }
        }
    }

    private func load() async {
        loading = objects.isEmpty
        defer { loading = false }
        do {
            struct Resp: Codable { let objects: [SharedObject] }
            let resp: Resp = try await APIClient.shared.request("GET", path: "api/objects")
            objects = resp.objects
            await BadgeStore.shared.refresh()
            if let objectId = deepLinkObjectId, let object = objects.first(where: { $0.id == objectId }) {
                path.append(object)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ObjectRow: View {
    let object: SharedObject

    var body: some View {
        HStack(spacing: 14) {
            ObjectImage(url: object.imageUrl, template: object.template)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(object.name)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(object.template == "CABIN" ? L10n.string("template.cabin") : L10n.string("template.generic"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if let count = object.unreadAlertCount, count > 0 {
                AlertBadgeView(count: count)
            }
            Image(systemName: "chevron.right")
                .foregroundStyle(Theme.muted.opacity(0.6))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.cardFill)
                .shadow(color: Theme.ink.opacity(0.06), radius: 10, y: 4)
        )
    }
}

struct ObjectImage: View {
    let url: String?
    let template: String

    var body: some View {
        CachedRemoteImage(url: url.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.accent.opacity(0.35), Theme.accentSoft],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: template == "CABIN" ? "house.lodge.fill" : "square.stack.3d.up.fill")
                .foregroundStyle(Theme.accent)
        }
    }
}

struct EmptyObjectsView: View {
    var onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "house.lodge")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
            Text(L10n.string("objects.emptyTitle"))
                .font(Theme.brandFont(size: 26))
            Text(L10n.string("objects.emptyBody"))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 32)
            Button(L10n.string("objects.create"), action: onCreate)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 40)
                .padding(.top, 8)
        }
    }
}

struct CreateObjectView: View {
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var template = "CABIN"
    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImageData: Data?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                Form {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                objectPhotoPreview
                                PhotosPicker(selection: $photoItem, matching: .images) {
                                    Text(
                                        pickedImageData == nil
                                            ? L10n.string("objects.addPhoto")
                                            : L10n.string("objects.changePhoto")
                                    )
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                }
                                if pickedImageData != nil {
                                    Button(L10n.string("objects.removePhoto"), role: .destructive) {
                                        pickedImageData = nil
                                        photoItem = nil
                                    }
                                    .font(.caption)
                                }
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }

                    Section {
                        TextField(L10n.string("objects.name"), text: $name)
                    }

                    Section(L10n.string("objects.template")) {
                        TemplatePicker(selection: $template)
                    }

                    if let error {
                        Text(error).foregroundStyle(Theme.danger)
                    }
                }
                .scrollContentBackground(.hidden)
                .disabled(loading)
            }
            .navigationTitle(L10n.string("objects.create"))
            .navigationBarTitleDisplayMode(.inline)
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
            .onChange(of: photoItem) { _, item in
                Task { await loadPickedImage(item) }
            }
        }
    }

    @ViewBuilder
    private var objectPhotoPreview: some View {
        Group {
            if let pickedImageData, let uiImage = UIImage(data: pickedImageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ObjectImage(url: nil, template: template)
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func loadPickedImage(_ item: PhotosPickerItem?) async {
        guard let item else {
            pickedImageData = nil
            return
        }
        do {
            pickedImageData = try await item.jpegDataForUpload()
            error = nil
        } catch {
            pickedImageData = nil
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            var imageUrl: String?
            if let pickedImageData {
                imageUrl = try await APIClient.shared.uploadImage(pickedImageData)
            }

            struct Body: Encodable {
                let name: String
                let template: String
                let imageUrl: String?
            }
            struct Resp: Codable { let object: SharedObject }
            let _: Resp = try await APIClient.shared.request(
                "POST",
                path: "api/objects",
                body: Body(name: name, template: template, imageUrl: imageUrl)
            )
            onDone()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct TemplatePicker: View {
    @Binding var selection: String

    var body: some View {
        VStack(spacing: 10) {
            TemplateOption(
                title: L10n.string("template.cabin"),
                subtitle: L10n.string("template.cabinDesc"),
                icon: "house.lodge.fill",
                selected: selection == "CABIN"
            ) { selection = "CABIN" }

            TemplateOption(
                title: L10n.string("template.generic"),
                subtitle: L10n.string("template.genericDesc"),
                icon: "square.stack.3d.up.fill",
                selected: selection == "GENERIC"
            ) { selection = "GENERIC" }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .listRowBackground(Color.clear)
    }
}

struct TemplateOption: View {
    let title: String
    let subtitle: String
    let icon: String
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.accent : Theme.muted)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? Theme.accent : Theme.muted.opacity(0.25), lineWidth: selected ? 2 : 1)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.7)))
            )
        }
        .buttonStyle(.plain)
    }
}
