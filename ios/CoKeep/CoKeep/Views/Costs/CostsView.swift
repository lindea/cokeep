import SwiftUI
import PhotosUI

struct CostsView: View {
    let objectId: String
    @EnvironmentObject private var session: SessionStore
    @State private var costs: [CostEntry] = []
    @State private var showAdd = false
    @State private var selectedCost: CostEntry?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Button {
                    showAdd = true
                } label: {
                    Label(L10n.string("costs.add"), systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.bottom, 4)

                ForEach(costs) { cost in
                    Button {
                        selectedCost = cost
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            AvatarView(user: cost.user, size: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cost.amountDisplay)
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(.primary)
                                if let description = cost.description {
                                    Text(description).foregroundStyle(Theme.muted).font(.subheadline)
                                }
                                if let todo = cost.todoItemName {
                                    Text(todo).font(.caption).foregroundStyle(Theme.accent)
                                }
                                Text(formatDate(cost.spentAt))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            if let receipt = cost.receiptUrl, let url = URL(string: receipt) {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Color.gray.opacity(0.2)
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardFill))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showAdd) {
            CostFormView(objectId: objectId, cost: nil) {
                showAdd = false
                Task { await load() }
            }
        }
        .sheet(item: $selectedCost) { cost in
            CostDetailView(objectId: objectId, cost: cost) {
                selectedCost = nil
                Task { await load() }
            }
        }
    }

    private func load() async {
        do {
            struct Resp: Codable { let costs: [CostEntry] }
            let resp: Resp = try await APIClient.shared.request(
                "GET",
                path: "api/objects/\(objectId)/costs"
            )
            costs = resp.costs
        } catch {}
    }
}

struct CostDetailView: View {
    let objectId: String
    let cost: CostEntry
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var deleting = false

    private var isOwner: Bool {
        session.user?.id == cost.user.id
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        AvatarView(user: cost.user, size: 48)
                        VStack(alignment: .leading) {
                            Text(cost.user.displayName)
                                .font(.headline)
                            Text(cost.amountDisplay)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        Spacer()
                    }

                    detailCard(title: L10n.string("costs.date"), value: formatDate(cost.spentAt))

                    if let description = cost.description, !description.isEmpty {
                        detailCard(title: L10n.string("costs.description"), value: description)
                    }

                    if let todo = cost.todoItemName {
                        detailCard(title: L10n.string("costs.linkedTodo"), value: todo)
                    }

                    if let receipt = cost.receiptUrl, let url = URL(string: receipt) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.string("costs.receipt"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.muted)
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                ProgressView()
                                    .frame(maxWidth: .infinity, minHeight: 160)
                            }
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.cardFill))
                    }

                    if isOwner {
                        Button {
                            showEdit = true
                        } label: {
                            Label(L10n.string("costs.edit"), systemImage: "pencil")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(deleting)

                        Button(L10n.string("costs.delete"), role: .destructive) {
                            confirmDelete = true
                        }
                        .disabled(deleting)
                        .padding(.top, 8)
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L10n.string("costs.detail"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                        .disabled(deleting)
                }
            }
            .sheet(isPresented: $showEdit) {
                CostFormView(objectId: objectId, cost: cost) {
                    showEdit = false
                    onDone()
                }
            }
            .confirmationDialog(
                L10n.string("costs.deleteConfirm"),
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button(L10n.string("common.delete"), role: .destructive) {
                    Task { await deleteCost() }
                }
                Button(L10n.string("common.cancel"), role: .cancel) {}
            }
        }
    }

    private func detailCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.cardFill))
    }

    private func deleteCost() async {
        guard !deleting else { return }
        deleting = true
        defer { deleting = false }
        struct Ok: Codable { let ok: Bool? }
        do {
            let _: Ok = try await APIClient.shared.request("DELETE", path: "api/costs/\(cost.id)")
            onDone()
            dismiss()
        } catch {}
    }
}

struct CostFormView: View {
    let objectId: String
    let cost: CostEntry?
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var amount: String
    @State private var description: String
    @State private var currency: String
    @State private var spentAt: Date
    @State private var photoItem: PhotosPickerItem?
    @State private var receiptUrl: String?
    @State private var error: String?
    @State private var loading = false

    private var isEditing: Bool { cost != nil }

    init(objectId: String, cost: CostEntry?, onDone: @escaping () -> Void) {
        self.objectId = objectId
        self.cost = cost
        self.onDone = onDone
        if let cost {
            let value = Double(cost.amountCents) / 100.0
            _amount = State(initialValue: String(format: "%.2f", value))
            _description = State(initialValue: cost.description ?? "")
            _currency = State(initialValue: cost.currency)
            _spentAt = State(initialValue: parseISODate(cost.spentAt) ?? Date())
            _receiptUrl = State(initialValue: cost.receiptUrl)
        } else {
            _amount = State(initialValue: "")
            _description = State(initialValue: "")
            _currency = State(initialValue: "NOK")
            _spentAt = State(initialValue: Date())
            _receiptUrl = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.string("costs.amount"), text: $amount)
                    .keyboardType(.decimalPad)
                Picker(L10n.string("costs.currency"), selection: $currency) {
                    Text("NOK").tag("NOK")
                    Text("USD").tag("USD")
                    Text("EUR").tag("EUR")
                    Text("SEK").tag("SEK")
                }
                DatePicker(L10n.string("costs.date"), selection: $spentAt, displayedComponents: .date)
                TextField(L10n.string("costs.description"), text: $description)

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(
                        receiptUrl == nil ? L10n.string("costs.addReceipt") : L10n.string("costs.receiptAdded"),
                        systemImage: "doc.viewfinder"
                    )
                }
                .onChange(of: photoItem) { _, item in
                    Task { await upload(item) }
                }

                if receiptUrl != nil {
                    Button(L10n.string("costs.removeReceipt"), role: .destructive) {
                        receiptUrl = nil
                        photoItem = nil
                    }
                }

                if let error {
                    Text(error).foregroundStyle(Theme.danger)
                }
            }
            .navigationTitle(isEditing ? L10n.string("costs.edit") : L10n.string("costs.add"))
            .disabled(loading)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                        .disabled(loading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    BusyToolbarButton(
                        title: L10n.string("common.save"),
                        loading: loading
                    ) {
                        Task { await save() }
                    }
                }
            }
        }
    }

    private func upload(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            let data = try await item.jpegDataForUpload()
            receiptUrl = try await APIClient.shared.uploadImage(data)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        guard !loading else { return }
        guard let value = Double(amount.replacingOccurrences(of: ",", with: ".")), value > 0 else {
            error = L10n.string("costs.invalidAmount")
            return
        }
        loading = true
        defer { loading = false }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        struct Body: Encodable {
            let amountCents: Int
            let currency: String
            let description: String?
            let receiptUrl: String?
            let spentAt: String
            let encodeNullReceipt: Bool

            enum CodingKeys: String, CodingKey {
                case amountCents, currency, description, receiptUrl, spentAt
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(amountCents, forKey: .amountCents)
                try container.encode(currency, forKey: .currency)
                try container.encode(description, forKey: .description)
                try container.encode(spentAt, forKey: .spentAt)
                if let receiptUrl {
                    try container.encode(receiptUrl, forKey: .receiptUrl)
                } else if encodeNullReceipt {
                    try container.encodeNil(forKey: .receiptUrl)
                }
            }
        }

        let body = Body(
            amountCents: Int((value * 100).rounded()),
            currency: currency,
            description: description.isEmpty ? nil : description,
            receiptUrl: receiptUrl,
            spentAt: iso.string(from: spentAt),
            encodeNullReceipt: isEditing
        )

        do {
            struct Resp: Codable { let cost: CostEntry }
            if let cost {
                let _: Resp = try await APIClient.shared.request(
                    "PATCH",
                    path: "api/costs/\(cost.id)",
                    body: body
                )
            } else {
                let _: Resp = try await APIClient.shared.request(
                    "POST",
                    path: "api/objects/\(objectId)/costs",
                    body: body
                )
            }
            onDone()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
