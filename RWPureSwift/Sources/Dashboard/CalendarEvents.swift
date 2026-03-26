import AppTypes
import CalendarAsync
import ComposableArchitecture
import Dependencies
import Foundation
import Utility

@Reducer
public struct CalendarEventsFeature: Sendable {
    @Dependency(\.calendarAsync) var calendarAsync
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now

    static let refreshInterval = Duration.seconds(5)

    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage(CALENDAR_SETTING_KEY)) var selectedCalendar: CalendarId?

        public var currentEventTitle: String?
        public var nextEventTitle: String?
        public var nextEventTimeUntil: String?
        public var nextEventLeadingEmoji: String?

        public init() {}
    }

    public enum Action: Equatable {
        case startMonitoring
        case tick
        case _eventsLoaded(
            currentTitle: String?,
            nextTitle: String?,
            nextTimeUntil: String?,
            nextLeadingEmoji: String?
        )
    }

    enum CancelID { case calendarLoop }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startMonitoring:
                return .run { send in
                    await send(.tick)
                    for await _ in self.clock.timer(interval: Self.refreshInterval) {
                        await send(.tick)
                    }
                }
                .cancellable(id: CancelID.calendarLoop, cancelInFlight: true)

            case .tick:
                guard let calendarId = state.selectedCalendar else {
                    return .send(._eventsLoaded(
                        currentTitle: nil,
                        nextTitle: nil,
                        nextTimeUntil: nil,
                        nextLeadingEmoji: nil
                    ))
                }
                return .run { [calendarAsync, now] send in
                    let currentEvent = calendarAsync.getActiveEvent(calendarId, now)
                    let nextEvent = calendarAsync.getNextEvent(calendarId, now)

                    let currentTitle = currentEvent?.title

                    var nextTitle: String?
                    var nextTimeUntil: String?
                    var nextLeadingEmoji: String?

                    if let next = nextEvent {
                        let formatter = DateComponentsFormatter()
                        formatter.unitsStyle = .brief
                        formatter.allowedUnits = [.hour, .minute]
                        nextTimeUntil = formatter.string(from: now, to: next.startDate)

                        if let title = next.title, let first = title.first, first.isSimpleEmoji {
                            nextLeadingEmoji = String(first)
                            nextTitle = String(title.dropFirst(1))
                        } else {
                            nextTitle = next.title
                        }
                    }

                    await send(._eventsLoaded(
                        currentTitle: currentTitle,
                        nextTitle: nextTitle,
                        nextTimeUntil: nextTimeUntil,
                        nextLeadingEmoji: nextLeadingEmoji
                    ))
                }

            case let ._eventsLoaded(currentTitle, nextTitle, nextTimeUntil, nextLeadingEmoji):
                state.currentEventTitle = currentTitle
                state.nextEventTitle = nextTitle
                state.nextEventTimeUntil = nextTimeUntil
                state.nextEventLeadingEmoji = nextLeadingEmoji
                return .none
            }
        }
    }
}
