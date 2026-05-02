import Foundation
import Tagged

public enum BusWindowTag {}
public typealias BusWindow = Tagged<BusWindowTag, String>

extension BusWindow {
    /// Creates a window from a set of active weekdays and a start/end time.
    /// Encoding: "<mask>|<startHour>:<startMinute>-<endHour>:<endMinute>"
    /// Mask is a 7-bit field; bit (DaysOfWeek.rawValue - 1) is set when active.
    public init(
        weekdays: Set<DaysOfWeek>,
        startHour: Int, startMinute: Int,
        endHour: Int, endMinute: Int
    ) {
        var mask = 0
        for day in weekdays {
            mask |= 1 << (day.rawValue - 1)
        }
        self.init(rawValue: "\(mask)|\(startHour):\(startMinute)-\(endHour):\(endMinute)")
    }

    /// Mon–Fri, 06:30 to 09:00.
    public static let `default` = BusWindow(
        weekdays: [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday],
        startHour: 6, startMinute: 30,
        endHour: 9, endMinute: 0
    )

    public var weekdays: Set<DaysOfWeek> {
        var result: Set<DaysOfWeek> = []
        let mask = parsedMask
        for day in DaysOfWeek.allCases where (mask & (1 << (day.rawValue - 1))) != 0 {
            result.insert(day)
        }
        return result
    }

    public var startHour: Int { parsedTime(part: 0, field: 0) ?? 6 }
    public var startMinute: Int { parsedTime(part: 0, field: 1) ?? 30 }
    public var endHour: Int { parsedTime(part: 1, field: 0) ?? 9 }
    public var endMinute: Int { parsedTime(part: 1, field: 1) ?? 0 }

    public var startTotalMinutes: Int { startHour * 60 + startMinute }
    public var endTotalMinutes: Int { endHour * 60 + endMinute }

    public var startTimeDisplay: String { formatTime(hour: startHour, minute: startMinute) }
    public var endTimeDisplay: String { formatTime(hour: endHour, minute: endMinute) }

    /// Returns true when the given date falls on an active weekday and the time-of-day
    /// is within the start/end window (overnight ranges like 22:00–06:00 supported).
    public func isInWindow(date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let mask = parsedMask
        guard (mask & (1 << (weekday - 1))) != 0 else { return false }

        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let current = hour * 60 + minute
        let start = startTotalMinutes
        let end = endTotalMinutes

        if start == end {
            return false
        } else if start < end {
            return current >= start && current < end
        } else {
            return current >= start || current < end
        }
    }

    public func withWeekdays(_ weekdays: Set<DaysOfWeek>) -> BusWindow {
        BusWindow(
            weekdays: weekdays,
            startHour: startHour, startMinute: startMinute,
            endHour: endHour, endMinute: endMinute
        )
    }

    public func withStart(hour: Int, minute: Int) -> BusWindow {
        BusWindow(
            weekdays: weekdays,
            startHour: hour, startMinute: minute,
            endHour: endHour, endMinute: endMinute
        )
    }

    public func withEnd(hour: Int, minute: Int) -> BusWindow {
        BusWindow(
            weekdays: weekdays,
            startHour: startHour, startMinute: startMinute,
            endHour: hour, endMinute: minute
        )
    }

    private var parsedMask: Int {
        let parts = rawValue.split(separator: "|", maxSplits: 1)
        guard parts.count == 2, let mask = Int(parts[0]) else { return 0 }
        return mask & 0b111_1111
    }

    private func parsedTime(part: Int, field: Int) -> Int? {
        let pipeParts = rawValue.split(separator: "|", maxSplits: 1)
        guard pipeParts.count == 2 else { return nil }
        let timeParts = pipeParts[1].split(separator: "-")
        guard timeParts.count == 2 else { return nil }
        let fields = timeParts[part].split(separator: ":")
        guard fields.count == 2 else { return nil }
        return Int(fields[field])
    }

    private func formatTime(hour: Int, minute: Int) -> String {
        let hour12 = hour % 12
        let displayHour = hour12 == 0 ? 12 : hour12
        let period = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }
}
