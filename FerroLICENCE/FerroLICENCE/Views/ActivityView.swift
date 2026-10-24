import GitHubKit
import Register
import SwiftUI

/// Screen 11: the register's history as sentences, grouped by day, each with
/// its pull request on GitHub.
struct ActivityView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all, licence, revocation, key
        var id: String { rawValue }
        /// The pull request label it keeps; `nil` keeps everything.
        var label: String? { self == .all ? nil : rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .all: "All"
            case .licence: "Licences"
            case .revocation: "Revocations"
            case .key: "Keys"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var filter = Filter.all

    var shown: [Merged] {
        model.activity.filter { m in
            (filter.label.map { m.labels.contains($0) } ?? true) && (search.isEmpty || m.title.localizedStandardContains(search))
        }
    }

    var days: [(day: Date, items: [Merged])] {
        Dictionary(grouping: shown) { Calendar.current.startOfDay(for: $0.mergedAt) }
            .map { ($0.key, $0.value.sorted { $0.mergedAt > $1.mergedAt }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        List {
            ForEach(days, id: \.day) { group in
                SwiftUI.Section {
                    ForEach(group.items) { ActivityRow(merged: $0) }
                } header: {
                    dayTitle(group.day)
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if shown.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView(
                        "No Activity", systemImage: "clock.arrow.circlepath",
                        description: Text("Every licence, revocation and key recorded shows here."))
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search Activity")
        .toolbar {
            ToolbarItem {
                Picker("Filter", systemImage: "line.3.horizontal.decrease", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .help("Show only licences, revocations or keys")
            }
        }
    }

    func dayTitle(_ day: Date) -> Text {
        if Calendar.current.isDateInToday(day) { return Text("Today") }
        if Calendar.current.isDateInYesterday(day) { return Text("Yesterday") }
        let thisYear = Calendar.current.isDate(day, equalTo: .now, toGranularity: .year)
        return Text(day, format: .dateTime.day().month(.wide).year(thisYear ? .omitted : .defaultDigits))
    }
}

struct ActivityRow: View {
    let merged: Merged
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(merged.mergedAt.formatted(date: .omitted, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 64, alignment: .trailing)
            Image(systemName: symbol.name)
                .foregroundStyle(symbol.color)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(activitySentence(merged.title))
                Text("Recorded by \(model.person(merged.author))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            PullRequestLink(number: merged.number, url: merged.url)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .onTapGesture { open() }
    }

    var symbol: (name: String, color: Color) {
        if merged.labels.contains("revocation") { return ("xmark.octagon.fill", .red) }
        if merged.labels.contains("key") { return ("key.horizontal.fill", .accentColor) }
        return ("checkmark.circle.fill", .green)
    }

    /// A licence row opens its customer.
    func open() {
        guard let entry = model.register.entries.first(where: { merged.records($0.id) }) else { return }
        model.selectedCustomer = entry.customer
        model.section = .customers
    }
}
