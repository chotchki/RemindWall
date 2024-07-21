@preconcurrency import EventKit

@MainActor
public class GlobalEventStore {
    public static let shared = GlobalEventStore()
    
    public let eventStore = EKEventStore()
    
    public init(){}
    
    public func requestAccess() async throws -> Bool {
        return try await eventStore.requestFullAccessToEvents()
    }
    
    public func getCalendars() -> [EKCalendar] {
        return eventStore.calendars(for: .event)
    }
    
    public static func getActiveEvent(calendarId: String, currentTime: Date) -> EKEvent? {
        guard let calendar = shared.eventStore.calendar(withIdentifier: calendarId) else {
            return nil
        }
        
        let startDate = Date(timeInterval: TimeInterval(-60*60*24), since: currentTime)
        let endDate = Date(timeInterval: TimeInterval(60*60*24), since: currentTime)
        
        let predicate = shared.eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: [calendar])
        let events = shared.eventStore.events(matching: predicate)
        
        for e in events {
            if e.startDate <= currentTime && e.endDate >= currentTime{
                return e
            }
        }
        
        return nil
    }
}
