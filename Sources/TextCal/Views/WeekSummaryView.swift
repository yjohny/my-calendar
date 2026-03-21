import SwiftUI

/// A text-native week overview: 7 days rendered as a compact, read-only text list.
/// Each day shows its header and a condensed summary of events — like reading a printed week planner.
/// Tapping a day jumps to it in the main scroll view.
struct WeekSummaryView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var weekStart: Date
    let onSelectDate: (Date) -> Void

    init(currentDate: Date, onSelectDate: @escaping (Date) -> Void) {
        // Start the week on Monday
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: currentDate)
        let daysFromMonday = (weekday + 5) % 7  // Monday = 0
        let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: currentDate)!
        _weekStart = State(initialValue: DateFormatting.normalizeToDay(monday))
        self.onSelectDate = onSelectDate
    }

    private var weekDates: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Week navigation
                    HStack {
                        Button {
                            weekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart)!
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.body)
                        }
                        .accessibilityLabel("Previous week")

                        Spacer()

                        Text(weekRangeText)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.medium)

                        Spacer()

                        Button {
                            weekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart)!
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.body)
                        }
                        .accessibilityLabel("Next week")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    ForEach(weekDates, id: \.self) { date in
                        weekDayRow(date: date)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Strings.weekView)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.done) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func weekDayRow(date: Date) -> some View {
        let key = DateFormatting.normalizeToDay(date)
        let isToday = Calendar.current.isDateInToday(date)
        let dayText = store.dayTexts[key] ?? ""
        let lines = condensedLines(from: dayText)
        let unmatchedCount = store.unmatchedEvents(for: date).count

        Button {
            onSelectDate(date)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Day column
                VStack(spacing: 2) {
                    Text(dayOfWeekShort(date))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(isToday ? .bold : .regular)
                        .foregroundStyle(isToday ? Color.accentColor : .primary)
                }
                .frame(width: 36)

                // Events summary
                VStack(alignment: .leading, spacing: 3) {
                    if lines.isEmpty && unmatchedCount == 0 {
                        Text("—")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.quaternary)
                    } else {
                        ForEach(Array(lines.prefix(4).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        if lines.count > 4 {
                            Text("+\(lines.count - 4) more")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        if unmatchedCount > 0 {
                            Text("+\(unmatchedCount) from other apps")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(isToday ? Color.accentColor.opacity(0.06) : Color.clear)

        Divider()
            .padding(.leading, 68)
    }

    /// Extract condensed event summaries from day text
    private func condensedLines(from text: String) -> [String] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []

        for line in lines {
            let parsed = LineParser.parse(line)
            switch parsed {
            case .event(let time, _, let title, _, _, _):
                let h = time.hour ?? 0
                let m = time.minute ?? 0
                let ampm = h >= 12 ? "PM" : "AM"
                let h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h)
                let timeStr = m == 0 ? "\(h12) \(ampm)" : "\(h12):\(String(format: "%02d", m)) \(ampm)"
                result.append("\(timeStr) \(title)")
            case .allDay(let title, _, _, _):
                result.append("★ \(title)")
            default:
                break
            }
        }
        return result
    }

    private static let rangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private var weekRangeText: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart)!
        return "\(Self.rangeFormatter.string(from: weekStart)) – \(Self.rangeFormatter.string(from: end))"
    }

    private func dayOfWeekShort(_ date: Date) -> String {
        Self.weekdayFormatter.string(from: date).uppercased()
    }
}
