import Tagged

public enum ScreenOffScheduleTag {}
public typealias ScreenOffSchedule = Tagged<ScreenOffScheduleTag, String>

extension ScreenOffSchedule {
    /// Creates a schedule from start and end times.
    /// - Parameters:
    ///   - startHour: 0-23
    ///   - startMinute: 0-59
    ///   - endHour: 0-23
    ///   - endMinute: 0-59
    public init(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        self.init(rawValue: "\(startHour):\(startMinute)-\(endHour):\(endMinute)")
    }

    /// Default schedule: 10:00 PM to 6:00 AM
    public static let `default` = ScreenOffSchedule(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0)

    public var startHour: Int {
        let parts = rawValue.split(separator: "-")
        guard parts.count == 2 else { return 22 }
        let timeParts = parts[0].split(separator: ":")
        guard timeParts.count == 2, let hour = Int(timeParts[0]) else { return 22 }
        return hour
    }

    public var startMinute: Int {
        let parts = rawValue.split(separator: "-")
        guard parts.count == 2 else { return 0 }
        let timeParts = parts[0].split(separator: ":")
        guard timeParts.count == 2, let minute = Int(timeParts[1]) else { return 0 }
        return minute
    }

    public var endHour: Int {
        let parts = rawValue.split(separator: "-")
        guard parts.count == 2 else { return 6 }
        let timeParts = parts[1].split(separator: ":")
        guard timeParts.count == 2, let hour = Int(timeParts[0]) else { return 6 }
        return hour
    }

    public var endMinute: Int {
        let parts = rawValue.split(separator: "-")
        guard parts.count == 2 else { return 0 }
        let timeParts = parts[1].split(separator: ":")
        guard timeParts.count == 2, let minute = Int(timeParts[1]) else { return 0 }
        return minute
    }

    /// Formatted display string for the start time (e.g., "10:00 PM")
    public var startTimeDisplay: String {
        formatTime(hour: startHour, minute: startMinute)
    }

    /// Formatted display string for the end time (e.g., "6:00 AM")
    public var endTimeDisplay: String {
        formatTime(hour: endHour, minute: endMinute)
    }

    /// Total minutes from midnight for start time (0-1439)
    public var startTotalMinutes: Int {
        startHour * 60 + startMinute
    }

    /// Total minutes from midnight for end time (0-1439)
    public var endTotalMinutes: Int {
        endHour * 60 + endMinute
    }

    /// Returns `true` when the given time (total minutes from midnight, 0-1439)
    /// falls within the screen-off window.
    ///
    /// Handles overnight schedules where start > end (e.g., 22:00 to 06:00).
    public func isInOffWindow(currentTotalMinutes: Int) -> Bool {
        let start = startTotalMinutes
        let end = endTotalMinutes

        if start == end {
            // Degenerate case: 0-length window, never off
            return false
        } else if start < end {
            // Same-day window (e.g., 02:00 to 14:00)
            return currentTotalMinutes >= start && currentTotalMinutes < end
        } else {
            // Overnight window (e.g., 22:00 to 06:00)
            return currentTotalMinutes >= start || currentTotalMinutes < end
        }
    }

    private func formatTime(hour: Int, minute: Int) -> String {
        let hour12 = hour % 12
        let displayHour = hour12 == 0 ? 12 : hour12
        let period = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }
}
