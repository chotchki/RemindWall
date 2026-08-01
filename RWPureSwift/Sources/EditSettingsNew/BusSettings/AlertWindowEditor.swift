import AppTypes
import SwiftUI

/// The one window editor every alert surface shares (TR1.4 review decision):
/// start/end time pickers plus weekday pills. Pure view - the owning feature
/// supplies the window and receives the edits.
public struct AlertWindowEditorView: View {
    let window: AlertWindow
    let onSetStart: (_ hour: Int, _ minute: Int) -> Void
    let onSetEnd: (_ hour: Int, _ minute: Int) -> Void
    let onToggleWeekday: (DaysOfWeek) -> Void

    public init(
        window: AlertWindow,
        onSetStart: @escaping (_ hour: Int, _ minute: Int) -> Void,
        onSetEnd: @escaping (_ hour: Int, _ minute: Int) -> Void,
        onToggleWeekday: @escaping (DaysOfWeek) -> Void
    ) {
        self.window = window
        self.onSetStart = onSetStart
        self.onSetEnd = onSetEnd
        self.onToggleWeekday = onToggleWeekday
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker(
                "Start",
                selection: Binding(
                    get: { time(hour: window.startHour, minute: window.startMinute) },
                    set: { newDate in
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                        onSetStart(comps.hour ?? 0, comps.minute ?? 0)
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            DatePicker(
                "End",
                selection: Binding(
                    get: { time(hour: window.endHour, minute: window.endMinute) },
                    set: { newDate in
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                        onSetEnd(comps.hour ?? 0, comps.minute ?? 0)
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            HStack {
                ForEach(DaysOfWeek.allCases, id: \.rawValue) { day in
                    Button {
                        onToggleWeekday(day)
                    } label: {
                        Text(initial(day))
                            .font(.callout)
                            .frame(width: 32, height: 32)
                            .background(window.weekdays.contains(day) ? Color.accentColor : Color.gray.opacity(0.2))
                            .foregroundStyle(window.weekdays.contains(day) ? Color.white : Color.primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(describing: day))
                    .accessibilityValue(window.weekdays.contains(day) ? "active" : "inactive")
                }
            }
        }
    }

    private func time(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func initial(_ day: DaysOfWeek) -> String {
        switch day {
        case .Sunday: return "S"
        case .Monday: return "M"
        case .Tuesday: return "T"
        case .Wednesday: return "W"
        case .Thursday: return "T"
        case .Friday: return "F"
        case .Saturday: return "S"
        }
    }
}
