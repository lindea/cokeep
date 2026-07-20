import SwiftUI
import PhotosUI

struct CostsView: View {
    let objectId: String
    @State private var costs: [CostEntry] = []
    @State private var showAdd = false

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
                    HStack(alignment: .top, spacing: 12) {
                        AvatarView(user: cost.user, size: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cost.amountDisplay)
                                .font(.system(.headline, design: .rounded))
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
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardFill))
                }
            }
            .padding(16)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showAdd) {
            AddCostView(objectId: objectId) {
                showAdd = false
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

struct AddCostView: View {
    let objectId: String
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var amount = ""
    @State private var description = ""
    @State private var currency = "NOK"
    @State private var photoItem: PhotosPickerItem?
    @State private var receiptUrl: String?
    @State private var error: String?
    @State private var loading = false

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

                if let error {
                    Text(error).foregroundStyle(Theme.danger)
                }
            }
            .navigationTitle(L10n.string("costs.add"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common.save")) {
                        Task { await save() }
                    }
                    .disabled(loading)
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
        guard let value = Double(amount.replacingOccurrences(of: ",", with: ".")), value > 0 else {
            error = L10n.string("costs.invalidAmount")
            return
        }
        loading = true
        defer { loading = false }
        struct Body: Encodable {
            let amountCents: Int
            let currency: String
            let description: String?
            let receiptUrl: String?
        }
        do {
            struct Resp: Codable { let cost: CostEntry }
            let _: Resp = try await APIClient.shared.request(
                "POST",
                path: "api/objects/\(objectId)/costs",
                body: Body(
                    amountCents: Int((value * 100).rounded()),
                    currency: currency,
                    description: description.isEmpty ? nil : description,
                    receiptUrl: receiptUrl
                )
            )
            onDone()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
