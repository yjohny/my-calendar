import SwiftUI

struct SyntaxHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    syntaxSection("Timed Events", examples: [
                        ("9:00 AM - Team standup", "Basic event with time"),
                        ("2 PM - Lunch", "Time without minutes"),
                        ("14:30 - Meeting", "24-hour format"),
                    ])

                    syntaxSection("Time Ranges", examples: [
                        ("9:00-10:30 AM - Design review", "Shared AM/PM"),
                        ("11:00 AM-1:00 PM - Workshop", "Spanning AM to PM"),
                    ])

                    syntaxSection("All-Day Events", examples: [
                        ("* Sarah's birthday", "Star marks all-day"),
                        ("* Company holiday", nil),
                    ])

                    syntaxSection("Notes", examples: [
                        ("  Bring laptop and charger", "Indent 2 spaces under an event"),
                        ("Had a productive morning.", "Plain text = journal entry"),
                    ])

                    syntaxSection("Calendar Override", examples: [
                        ("[Work] 9:00 AM - Standup", "Add to Work calendar"),
                        ("[Personal] * Birthday", "All-day on Personal calendar"),
                        ("3:00 PM - Meeting", "Uses your default calendar"),
                    ])

                    syntaxSection("Repeating Events", examples: [
                        ("9:00 AM - Standup (every weekday)", "Mon–Fri"),
                        ("* Take vitamins (daily)", "Every day"),
                        ("2:00 PM - Sync (every Tuesday)", "Weekly on a day"),
                        ("10:00 AM - Review (every 2 weeks)", "Biweekly"),
                        ("* Rent due (monthly 1st)", "Monthly on a date"),
                        ("* Anniversary (yearly)", "Once a year"),
                    ])

                    repeatBehaviorSection()
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Syntax Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func syntaxSection(_ title: String, examples: [(String, String?)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(examples.enumerated()), id: \.offset) { _, example in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(example.0)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                        if let description = example.1 {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func repeatBehaviorSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How Repeating Works")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                bulletPoint("Type a repeating event once — it auto-appears on matching dates")
                bulletPoint("Repeating events show slightly faded to distinguish from typed text")
                bulletPoint("Long-press a repeated event to skip one day or stop all future occurrences")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
