import SwiftUI

/// A circular clock dial for setting screen-off and screen-on times,
/// inspired by the iPhone Health app's Sleep Schedule interface.
struct ClockDialView: View {
    let startHour: Int      // 0-23
    let startMinute: Int    // 0-59
    let endHour: Int        // 0-23
    let endMinute: Int      // 0-59

    let onStartTimeChanged: (_ hour: Int, _ minute: Int) -> Void
    let onEndTimeChanged: (_ hour: Int, _ minute: Int) -> Void
    let onBothTimesChanged: (_ startHour: Int, _ startMinute: Int, _ endHour: Int, _ endMinute: Int) -> Void

    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var isDraggingArc = false
    @State private var dragStartAngle: Double = 0
    @State private var originalStartTotalMinutes: Int = 0
    @State private var originalEndTotalMinutes: Int = 0
    @State private var previousStartAngle: Double = 0
    @State private var previousEndAngle: Double = 0

    private let trackWidth: CGFloat = 36

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = size / 2 - 30

            ZStack {
                // Background track
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: trackWidth)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)

                // Hour tick marks
                ForEach(0..<12, id: \.self) { tick in
                    let angle = Double(tick) * 30.0
                    let isMajor = tick % 3 == 0
                    tickMark(angle: angle, radius: radius, center: center, isMajor: isMajor)
                }

                // Hour number labels
                ForEach(0..<12, id: \.self) { tick in
                    let hour = tick == 0 ? 12 : tick
                    let labelRadius = radius - trackWidth / 2 - 16
                    let radians = (Double(tick) * 30.0 - 90.0) * .pi / 180.0
                    Text("\(hour)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .position(
                            x: center.x + labelRadius * cos(radians),
                            y: center.y + labelRadius * sin(radians)
                        )
                }

                // Colored arc between start and end
                ScreenOffArc(
                    startAngleDeg: timeToAngle(hour: startHour, minute: startMinute),
                    endAngleDeg: timeToAngle(hour: endHour, minute: endMinute)
                )
                .stroke(Color.indigo.opacity(0.35), style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
                .frame(width: radius * 2, height: radius * 2)
                .position(center)
                .contentShape(
                    ScreenOffArc(
                        startAngleDeg: timeToAngle(hour: startHour, minute: startMinute),
                        endAngleDeg: timeToAngle(hour: endHour, minute: endMinute)
                    )
                )
                .gesture(arcDragGesture(center: center))
                .accessibilityHidden(true)

                // Start handle (moon - screen off)
                handleView(
                    systemName: "moon.fill",
                    color: .indigo,
                    angle: timeToAngle(hour: startHour, minute: startMinute),
                    center: center,
                    radius: radius,
                    isDragging: isDraggingStart
                )
                .gesture(startHandleDragGesture(center: center))
                .accessibilityElement()
                .accessibilityLabel("Screen off time")
                .accessibilityValue(formatAccessibilityTime(hour: startHour, minute: startMinute))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment:
                        onStartTimeChanged((startHour + 1) % 24, startMinute)
                    case .decrement:
                        onStartTimeChanged((startHour - 1 + 24) % 24, startMinute)
                    @unknown default:
                        break
                    }
                }

                // End handle (sun - screen on)
                handleView(
                    systemName: "sun.max.fill",
                    color: .orange,
                    angle: timeToAngle(hour: endHour, minute: endMinute),
                    center: center,
                    radius: radius,
                    isDragging: isDraggingEnd
                )
                .gesture(endHandleDragGesture(center: center))
                .accessibilityElement()
                .accessibilityLabel("Screen on time")
                .accessibilityValue(formatAccessibilityTime(hour: endHour, minute: endMinute))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment:
                        onEndTimeChanged((endHour + 1) % 24, endMinute)
                    case .decrement:
                        onEndTimeChanged((endHour - 1 + 24) % 24, endMinute)
                    @unknown default:
                        break
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    // MARK: - Handle View

    @ViewBuilder
    private func handleView(
        systemName: String,
        color: Color,
        angle: Double,
        center: CGPoint,
        radius: CGFloat,
        isDragging: Bool
    ) -> some View {
        let radians = (angle - 90.0) * .pi / 180.0
        let x = center.x + radius * cos(radians)
        let y = center.y + radius * sin(radians)

        Circle()
            .fill(color)
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: systemName)
                    .foregroundStyle(.white)
                    .font(.system(size: 18))
            )
            .shadow(color: color.opacity(0.3), radius: isDragging ? 8 : 4)
            .scaleEffect(isDragging ? 1.15 : 1.0)
            .position(x: x, y: y)
            .animation(.easeOut(duration: 0.15), value: isDragging)
    }

    // MARK: - Tick Marks

    @ViewBuilder
    private func tickMark(angle: Double, radius: CGFloat, center: CGPoint, isMajor: Bool) -> some View {
        let length: CGFloat = isMajor ? 8 : 4
        let radians = (angle - 90.0) * .pi / 180.0
        let outerRadius = radius + trackWidth / 2 - 2
        let innerRadius = outerRadius - length

        Path { path in
            path.move(to: CGPoint(
                x: center.x + innerRadius * cos(radians),
                y: center.y + innerRadius * sin(radians)
            ))
            path.addLine(to: CGPoint(
                x: center.x + outerRadius * cos(radians),
                y: center.y + outerRadius * sin(radians)
            ))
        }
        .stroke(Color.gray.opacity(0.4), lineWidth: isMajor ? 2 : 1)
    }

    // MARK: - Angle / Time Conversion

    /// Converts 24-hour time to angle on a 12-hour clock face.
    /// 0 degrees = 12 o'clock (top), increasing clockwise.
    private func timeToAngle(hour: Int, minute: Int) -> Double {
        let hour12 = Double(hour % 12)
        let minuteFraction = Double(minute) / 60.0
        return (hour12 + minuteFraction) * 30.0
    }

    /// Converts angle to 12-hour time, snapped to 5-minute increments.
    private func angleToTime(angle: Double) -> (hour12: Int, minute: Int) {
        let normalized = ((angle.truncatingRemainder(dividingBy: 360.0)) + 360.0)
            .truncatingRemainder(dividingBy: 360.0)
        let totalMinutes = normalized / 360.0 * 720.0
        let snapped = Int((totalMinutes / 5.0).rounded()) * 5
        let hour12 = (snapped / 60) % 12
        let minute = snapped % 60
        return (hour12, minute)
    }

    /// Converts a point to angle relative to center.
    /// 0 = 12 o'clock (top), increasing clockwise.
    private func pointToAngle(point: CGPoint, center: CGPoint) -> Double {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let radians = atan2(dx, -dy)
        var degrees = radians * 180.0 / .pi
        if degrees < 0 { degrees += 360.0 }
        return degrees
    }

    /// Detects if dragging from one angle to another crosses the 12 o'clock position.
    private func crossesTwelve(from oldAngle: Double, to newAngle: Double) -> Bool {
        let threshold = 30.0
        let crossCW = oldAngle > (360.0 - threshold) && newAngle < threshold
        let crossCCW = oldAngle < threshold && newAngle > (360.0 - threshold)
        return crossCW || crossCCW
    }

    /// Adjusts a 24-hour value when dragging crosses the 12 o'clock boundary.
    private func adjustedHour24(currentHour24: Int, crossed: Bool, newHour12: Int) -> Int {
        var isAM = currentHour24 < 12
        if crossed { isAM.toggle() }
        if isAM {
            return newHour12 == 0 ? 0 : newHour12  // hour12 of 0 means 12 on the clock = 0 in 24h AM
        } else {
            return newHour12 == 0 ? 12 : newHour12 + 12  // hour12 of 0 means 12 on the clock = 12 in 24h PM
        }
    }

    private func formatAccessibilityTime(hour: Int, minute: Int) -> String {
        let h12 = hour % 12
        let displayHour = h12 == 0 ? 12 : h12
        let period = hour < 12 ? "AM" : "PM"
        return "\(displayHour) \(String(format: "%02d", minute)) \(period)"
    }

    // MARK: - Drag Gestures

    private func startHandleDragGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDraggingStart {
                    isDraggingStart = true
                    previousStartAngle = timeToAngle(hour: startHour, minute: startMinute)
                }
                let angle = pointToAngle(point: value.location, center: center)
                let crossed = crossesTwelve(from: previousStartAngle, to: angle)
                let (hour12, minute) = angleToTime(angle: angle)
                let newHour24 = adjustedHour24(currentHour24: startHour, crossed: crossed, newHour12: hour12)
                previousStartAngle = angle
                onStartTimeChanged(newHour24, minute)
            }
            .onEnded { _ in
                isDraggingStart = false
            }
    }

    private func endHandleDragGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDraggingEnd {
                    isDraggingEnd = true
                    previousEndAngle = timeToAngle(hour: endHour, minute: endMinute)
                }
                let angle = pointToAngle(point: value.location, center: center)
                let crossed = crossesTwelve(from: previousEndAngle, to: angle)
                let (hour12, minute) = angleToTime(angle: angle)
                let newHour24 = adjustedHour24(currentHour24: endHour, crossed: crossed, newHour12: hour12)
                previousEndAngle = angle
                onEndTimeChanged(newHour24, minute)
            }
            .onEnded { _ in
                isDraggingEnd = false
            }
    }

    private func arcDragGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if !isDraggingArc {
                    isDraggingArc = true
                    dragStartAngle = pointToAngle(point: value.startLocation, center: center)
                    originalStartTotalMinutes = startHour * 60 + startMinute
                    originalEndTotalMinutes = endHour * 60 + endMinute
                }
                let currentAngle = pointToAngle(point: value.location, center: center)
                var angleDelta = currentAngle - dragStartAngle
                // Handle wrapping around 360/0
                if angleDelta > 180 { angleDelta -= 360 }
                if angleDelta < -180 { angleDelta += 360 }
                let minuteDelta = Int((angleDelta / 360.0 * 720.0).rounded())
                let newStartTotal = ((originalStartTotalMinutes + minuteDelta) % 1440 + 1440) % 1440
                let newEndTotal = ((originalEndTotalMinutes + minuteDelta) % 1440 + 1440) % 1440
                // Snap to 5 minutes
                let snappedStart = (newStartTotal / 5) * 5
                let snappedEnd = (newEndTotal / 5) * 5
                onBothTimesChanged(
                    snappedStart / 60, snappedStart % 60,
                    snappedEnd / 60, snappedEnd % 60
                )
            }
            .onEnded { _ in
                isDraggingArc = false
            }
    }
}

// MARK: - Arc Shape

/// A shape that draws a clockwise arc from a start angle to an end angle
/// on a 12-hour clock face (0 degrees = 12 o'clock, clockwise).
struct ScreenOffArc: Shape {
    var startAngleDeg: Double
    var endAngleDeg: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startAngleDeg, endAngleDeg) }
        set { startAngleDeg = newValue.first; endAngleDeg = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        // Convert from "0=top, clockwise" to SwiftUI angles "0=right, clockwise"
        let start = Angle(degrees: startAngleDeg - 90.0)
        let end = Angle(degrees: endAngleDeg - 90.0)

        var path = Path()
        // clockwise: false in SwiftUI's flipped coordinate system draws clockwise visually
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        return path
    }
}

// MARK: - Preview

#Preview("Clock Dial - Default Schedule") {
    ClockDialView(
        startHour: 22,
        startMinute: 0,
        endHour: 6,
        endMinute: 0,
        onStartTimeChanged: { _, _ in },
        onEndTimeChanged: { _, _ in },
        onBothTimesChanged: { _, _, _, _ in }
    )
    .frame(width: 320, height: 320)
    .padding()
}

#Preview("Clock Dial - Short Period") {
    ClockDialView(
        startHour: 23,
        startMinute: 30,
        endHour: 5,
        endMinute: 0,
        onStartTimeChanged: { _, _ in },
        onEndTimeChanged: { _, _ in },
        onBothTimesChanged: { _, _, _, _ in }
    )
    .frame(width: 320, height: 320)
    .padding()
}
