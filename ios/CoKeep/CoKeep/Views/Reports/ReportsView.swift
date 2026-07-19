import Charts
import SwiftUI

struct ReportsView: View {
    let objectId: String
    @State private var reportType = 0
    @State private var period = "month"
    @State private var spendings: SpendingsReport?
    @State private var work: WorkReport?
    @State private var customFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customTo = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("", selection: $reportType) {
                    Text(L10n.string("reports.spendings")).tag(0)
                    Text(L10n.string("reports.work")).tag(1)
                }
                .pickerStyle(.segmented)
                .onChange(of: reportType) { _, _ in
                    Task { await load() }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(["week", "month", "quarter", "year", "all", "custom"], id: \.self) { p in
                            PeriodChip(
                                title: L10n.string("period.\(p)"),
                                selected: period == p
                            ) {
                                period = p
                                Task { await load() }
                            }
                        }
                    }
                }

                if period == "custom" {
                    DatePicker(L10n.string("period.from"), selection: $customFrom, displayedComponents: .date)
                    DatePicker(L10n.string("period.to"), selection: $customTo, displayedComponents: .date)
                    Button(L10n.string("reports.apply")) {
                        Task { await load() }
                    }
                    .buttonStyle(PrimaryButtonStyle(filled: false))
                }

                if reportType == 0, let spendings {
                    SpendingsReportView(report: spendings)
                } else if reportType == 1, let work {
                    WorkReportView(report: work)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(16)
        }
        .task { await load() }
    }

    private func load() async {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var query = [URLQueryItem(name: "period", value: period)]
        if period == "custom" {
            query.append(URLQueryItem(name: "from", value: iso.string(from: customFrom)))
            query.append(URLQueryItem(name: "to", value: iso.string(from: customTo)))
        }

        do {
            if reportType == 0 {
                spendings = try await APIClient.shared.request(
                    "GET",
                    path: "api/objects/\(objectId)/reports/spendings",
                    query: query
                )
            } else {
                work = try await APIClient.shared.request(
                    "GET",
                    path: "api/objects/\(objectId)/reports/work",
                    query: query
                )
            }
        } catch {}
    }
}

struct PeriodChip: View {
    let title: String
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(selected ? Theme.accent : Theme.cardFill)
                )
                .foregroundStyle(selected ? .white : Theme.ink)
        }
        .buttonStyle(.plain)
    }
}

struct SpendingsReportView: View {
    let report: SpendingsReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(format: "%.2f %@", Double(report.totalCents) / 100.0, report.currency))
                .font(Theme.brandFont(size: 34))
            Text(L10n.string("reports.totalSpend"))
                .foregroundStyle(Theme.muted)

            if !report.chart.isEmpty {
                Chart(report.chart) { point in
                    BarMark(
                        x: .value("User", point.label),
                        y: .value("Amount", point.value)
                    )
                    .foregroundStyle(Theme.accent)
                }
                .frame(height: 200)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardFill))
            }

            Text(L10n.string("reports.byUser")).font(.headline)
            ForEach(report.byUser) { user in
                HStack {
                    Text("\(user.firstName) \(user.lastName)")
                    Spacer()
                    Text(String(format: "%.2f", Double(user.totalCents) / 100.0))
                        .fontWeight(.semibold)
                }
                .padding(.vertical, 4)
            }

            Text(L10n.string("reports.list")).font(.headline).padding(.top, 8)
            ForEach(report.items) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(item.firstName) \(item.lastName)").font(.subheadline.weight(.semibold))
                        Text(item.description ?? "—").font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(String(format: "%.2f", Double(item.amountCents) / 100.0))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardFill))
            }
        }
    }
}

struct WorkReportView: View {
    let report: WorkReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(formatDuration(report.totalMinutes))
                .font(Theme.brandFont(size: 34))
            Text(L10n.string("reports.totalWork"))
                .foregroundStyle(Theme.muted)

            if !report.chart.isEmpty {
                Chart(report.chart) { point in
                    BarMark(
                        x: .value("User", point.label),
                        y: .value("Hours", point.value)
                    )
                    .foregroundStyle(Theme.warm)
                }
                .frame(height: 200)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardFill))
            }

            Text(L10n.string("reports.byUser")).font(.headline)
            ForEach(report.byUser) { user in
                HStack {
                    Text("\(user.firstName) \(user.lastName)")
                    Spacer()
                    Text(formatDuration(user.totalMinutes)).fontWeight(.semibold)
                }
            }

            Text(L10n.string("reports.list")).font(.headline).padding(.top, 8)
            ForEach(report.items) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.todoItemName).font(.subheadline.weight(.semibold))
                        Text("\(item.firstName) \(item.lastName)")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(formatDuration(item.durationMinutes))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardFill))
            }
        }
    }
}
