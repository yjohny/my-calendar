import SwiftUI

/// A vertical scrubber track on the right edge for fast date navigation.
/// Drag to fly through the date range; a floating label shows the current month/year.
struct DateScrubber: View {
    let startDate: Date
    let endDate: Date
    let onDateSelected: (Date) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDragging = false
    @State private var dragProgress: CGFloat = 0.5
    @State private var currentLabel = ""
    @State private var lastMonth = -1  // track month for haptic feedback
    @State private var cachedMonthProgresses: [CGFloat] = []
    @State private var hapticGenerator: UIImpactFeedbackGenerator?

    private let calendar = Calendar.current
    private let trackWidth: CGFloat = 32
    private let knobHeight: CGFloat = 40

    private static let labelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()

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
                // Track
                GeometryReader { geo in
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
                                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

                            // Arrow pointing to track
                            Triangle()
                                .fill(Color.accentColor)
                                .frame(width: 8, height: 12)
                        }
                        .position(
                            x: -60,
                            y: dragProgress * (geo.size.height - 80) + 40
                        )
                        .animation(reduceMotion ? nil : .interactiveSpring, value: dragProgress)
                    }

                    // Track content
                    ZStack(alignment: .top) {
                        // Track background
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(.systemGray4))
                            .frame(width: 3)
                            .frame(maxHeight: .infinity)
                            .padding(.vertical, 40)

                        // Month tick marks
                        let usable = geo.size.height - 80
                        ForEach(Array(monthProgresses.enumerated()), id: \.offset) { _, progress in
                            Circle()
                                .fill(Color(.systemGray3))
                                .frame(width: 5, height: 5)
                                .position(x: 1.5, y: progress * usable + 40)
                        }

                        // Drag knob (shown during drag)
                        if isDragging {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor)
                                .frame(width: 6, height: knobHeight)
                                .position(x: 1.5, y: dragProgress * (geo.size.height - 80) + 40)
                                .animation(reduceMotion ? nil : .interactiveSpring, value: dragProgress)
                        }
                    }
                    .frame(width: trackWidth)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isDragging {
                                    // Prepare haptic engine on drag start for lower latency
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.prepare()
                                    hapticGenerator = generator
                                }
                                isDragging = true
                                let usableHeight = geo.size.height - 80
                                let yOffset = value.location.y - 40
                                dragProgress = min(max(yOffset / usableHeight, 0), 1)
                                updateLabel()
                            }
                            .onEnded { _ in
                                onDateSelected(dateAtProgress)
                                lastMonth = -1
                                hapticGenerator = nil
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                                    isDragging = false
                                }
                            }
                    )
                }
                .frame(width: trackWidth)
            }
        }
        .allowsHitTesting(true)
        .onAppear {
            cachedMonthProgresses = computeMonthProgresses()
        }
        .onChange(of: startDate) { _, _ in
            cachedMonthProgresses = computeMonthProgresses()
        }
        .onChange(of: endDate) { _, _ in
            cachedMonthProgresses = computeMonthProgresses()
        }
        .accessibilityElement()
        .accessibilityLabel("Date scrubber")
        .accessibilityValue(currentLabel.isEmpty ? "Drag to navigate dates" : currentLabel)
        .accessibilityHint("Drag up or down to navigate dates")
    }

    private func updateLabel() {
        let date = dateAtProgress
        currentLabel = Self.labelFormatter.string(from: date)

        // Haptic feedback when crossing month boundaries
        let month = calendar.component(.month, from: date)
        if lastMonth != -1 && month != lastMonth {
            hapticGenerator?.impactOccurred()
            hapticGenerator?.prepare()
        }
        lastMonth = month
    }

    /// Normalized month progress values (0...1), cached and rebuilt only when date range changes.
    private var monthProgresses: [CGFloat] {
        cachedMonthProgresses
    }

    private func computeMonthProgresses() -> [CGFloat] {
        let totalDays = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 1
        guard totalDays > 0 else { return [] }

        var progresses: [CGFloat] = []

        var comps = calendar.dateComponents([.year, .month], from: startDate)
        comps.month! += 1
        comps.day = 1
        guard var monthStart = calendar.date(from: comps) else { return progresses }

        while monthStart < endDate {
            let daysFromStart = calendar.dateComponents([.day], from: startDate, to: monthStart).day ?? 0
            progresses.append(CGFloat(daysFromStart) / CGFloat(totalDays))
            guard let next = calendar.date(byAdding: .month, value: 1, to: monthStart) else { break }
            monthStart = next
        }

        return progresses
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
