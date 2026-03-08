import SwiftUI

/// A vertical scrubber track on the right edge for fast date navigation.
/// Drag to fly through the date range; a floating label shows the current month/year.
struct DateScrubber: View {
    let startDate: Date
    let endDate: Date
    let onDateSelected: (Date) -> Void

    @State private var isDragging = false
    @State private var dragProgress: CGFloat = 0.5
    @State private var currentLabel = ""

    private let calendar = Calendar.current
    private let trackWidth: CGFloat = 32
    private let knobHeight: CGFloat = 40

    private var dateAtProgress: Date {
        let totalDays = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 1
        let dayOffset = Int(Double(totalDays) * Double(dragProgress))
        return calendar.date(byAdding: .day, value: dayOffset, to: startDate)
            ?? startDate
    }

    var body: some View {
        HStack {
            Spacer()
            ZStack(alignment: .trailing) {
                // Floating month/year label (appears during drag)
                if isDragging {
                    HStack(spacing: 8) {
                        Text(currentLabel)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                        // Arrow pointing to track
                        Triangle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 12)
                    }
                    .offset(x: -trackWidth - 4)
                    .position(x: UIScreen.main.bounds.width / 2, y: dragProgress * UIScreen.main.bounds.height * 0.8 + UIScreen.main.bounds.height * 0.1)
                    .animation(.interactiveSpring, value: dragProgress)
                }

                // Track
                GeometryReader { geo in
                    ZStack(alignment: .top) {
                        // Track background
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(.systemGray4))
                            .frame(width: 3)
                            .frame(maxHeight: .infinity)
                            .padding(.vertical, 40)

                        // Month tick marks
                        ForEach(monthTicks(in: geo.size.height), id: \.offset) { tick in
                            Circle()
                                .fill(Color(.systemGray3))
                                .frame(width: 5, height: 5)
                                .position(x: 1.5, y: tick.offset)
                        }

                        // Drag knob (shown during drag)
                        if isDragging {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor)
                                .frame(width: 6, height: knobHeight)
                                .position(x: 1.5, y: dragProgress * (geo.size.height - 80) + 40)
                                .animation(.interactiveSpring, value: dragProgress)
                        }
                    }
                    .frame(width: trackWidth)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let usableHeight = geo.size.height - 80
                                let yOffset = value.location.y - 40
                                dragProgress = min(max(yOffset / usableHeight, 0), 1)
                                updateLabel()
                            }
                            .onEnded { _ in
                                onDateSelected(dateAtProgress)
                                withAnimation(.easeOut(duration: 0.3)) {
                                    isDragging = false
                                }
                            }
                    )
                }
                .frame(width: trackWidth)
            }
        }
        .allowsHitTesting(true)
    }

    private func updateLabel() {
        let date = dateAtProgress
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        currentLabel = formatter.string(from: date)
    }

    private struct MonthTick: Identifiable {
        let id = UUID()
        let offset: CGFloat
    }

    private func monthTicks(in height: CGFloat) -> [MonthTick] {
        let totalDays = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 1
        guard totalDays > 0 else { return [] }

        var ticks: [MonthTick] = []
        let current = startDate

        // Find first of next month
        var comps = calendar.dateComponents([.year, .month], from: current)
        comps.month! += 1
        comps.day = 1
        guard var monthStart = calendar.date(from: comps) else { return ticks }

        let usableHeight = height - 80

        while monthStart < endDate {
            let daysFromStart = calendar.dateComponents([.day], from: startDate, to: monthStart).day ?? 0
            let progress = CGFloat(daysFromStart) / CGFloat(totalDays)
            let yOffset = progress * usableHeight + 40
            ticks.append(MonthTick(offset: yOffset))

            guard let next = calendar.date(byAdding: .month, value: 1, to: monthStart) else { break }
            monthStart = next
        }

        return ticks
    }
}

/// Small triangle shape for the label arrow
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
