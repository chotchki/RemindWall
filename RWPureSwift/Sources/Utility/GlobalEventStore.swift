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
}
