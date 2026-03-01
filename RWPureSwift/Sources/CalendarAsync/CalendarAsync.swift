//
//  CalendarAsync.swift
//  RWPureSwift
//
//  Created by Christopher Hotchkiss on 2/25/26.
//

import AppTypes
@preconcurrency import EventKit
import Dependencies
import DependenciesMacros
#if canImport(UIKit)
import UIKit
#endif


@DependencyClient
public struct CalendarAsync: Sendable {
    public var calendarAccess: @Sendable () -> EKAuthorizationStatus = { .notDetermined }
    public var openCalendarSettings: @Sendable () async -> () = {}
    public var requestAccess: @Sendable () async throws -> Bool = { false }
    public var getCalendars: @Sendable () -> [EKCalendar] = { [] }
    public var getActiveEvent: @Sendable (CalendarId, Date) -> EKEvent?
    public var getNextEvent: @Sendable (CalendarId, Date) -> EKEvent?
}

extension CalendarAsync: DependencyKey {
    public static var liveValue: Self {
        nonisolated(unsafe) let store = EKEventStore()
        return Self(
            calendarAccess: {
                return EKEventStore.authorizationStatus(for: .event)
            },
            openCalendarSettings: {
                @Dependency(\.fireAndForget) var fireAndForget
                await fireAndForget { @MainActor in
                    #if canImport(UIKit)
                    #if targetEnvironment(macCatalyst)
                    let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                    await UIApplication.shared.open(URL(string: url)!)
                    #else
                    let url = UIApplication.openSettingsURLString
                    UIApplication.shared.open(URL(string: url)!)
                    #endif
                    #endif
                }
            },
            requestAccess: {
                return try await store.requestFullAccessToEvents()
            }, getCalendars: {
                return store.calendars(for: .event)
            }, getActiveEvent: {
                calendarId, currentTime in
                
                guard let calendar = store.calendar(withIdentifier: calendarId.rawValue) else {
                    return nil
                }
                
                let startDate = Date(timeInterval: TimeInterval(-60*60*24), since: currentTime)
                let endDate = Date(timeInterval: TimeInterval(60*60*24), since: currentTime)
                
                let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: [calendar])
                let events = store.events(matching: predicate)
                
                for e in events {
                    if e.startDate <= currentTime && e.endDate >= currentTime{
                        return e
                    }
                }
                
                return nil
            }, getNextEvent: {
                calendarId, currentTime in
                
                guard let calendar = store.calendar(withIdentifier: calendarId.rawValue) else {
                    return nil
                }
                
                //Look for events within the next hour
                let startDate = Date(timeInterval: TimeInterval(1), since: currentTime)
                let endDate = Date(timeInterval: TimeInterval(60*60), since: currentTime)
                
                
                let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: [calendar])
                let events = store.events(matching: predicate)
                
                var nextEvent: EKEvent? = nil
                for e in events{
                    if e.startDate < currentTime {
                        continue
                    }
                    
                    if nextEvent == nil {
                        nextEvent = e
                    } else if nextEvent!.startDate > e.startDate {
                        nextEvent = e
                    }
                }
                return nextEvent
            }
        )
    }
}

extension CalendarAsync: TestDependencyKey {
    public static let testValue = Self()

    public static var previewValue: Self {
        return Self(
            calendarAccess: {
                return .fullAccess
            },
            openCalendarSettings: {},
            requestAccess: {
                return true
            }, getCalendars: {
                return []
            }, getActiveEvent: {
                cal, date in
                return nil
            }, getNextEvent: {
                cal, date in
                return nil
            }
        )
    }
}

extension DependencyValues {
  public var calendarAsync: CalendarAsync {
    get { self[CalendarAsync.self] }
    set { self[CalendarAsync.self] = newValue }
  }
}
