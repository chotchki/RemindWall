//
//  CalendarPicker.swift
//  RWPureSwift
//
//  Created by Christopher Hotchkiss on 2/14/26.
//

import AppTypes
import CalendarAsync
import ComposableArchitecture
import Dependencies
@preconcurrency import EventKit
import SwiftUI

@Reducer
public struct CalendarPickerFeature {
    @Dependency(\.calendarAsync) var calendarAsync

    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage(CALENDAR_SETTING_KEY)) var selectedCalendar: CalendarId?
        var calendarStatus: EKAuthorizationStatus = .notDetermined
        var availableCalendars: [EKCalendar]?

        public init() {}
    }

    public enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onAppear
        case tapOpenSettings
        case tapAuthorizeAccess
        case authorizationComplete(Bool)
        case loadListComplete([EKCalendar]?)
    }

    public init() {}

    public var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
            case .onAppear:
                state.calendarStatus = calendarAsync.calendarAccess()
                return loadList(state: &state)
            case .tapOpenSettings:
                return .run { [calendarAsync] send in
                    await calendarAsync.openCalendarSettings()
                }
            case .tapAuthorizeAccess:
                return .run { [calendarAsync] send in
                    let granted = try await calendarAsync.requestAccess()
                    await send(.authorizationComplete(granted))
                }
            case let .authorizationComplete(granted):
                state.calendarStatus = calendarAsync.calendarAccess()
                if granted {
                    return loadList(state: &state)
                }
                return .none
            case let .loadListComplete(list):
                state.availableCalendars = list
                return .none
            }
        }
    }

    func loadList(state: inout State) -> Effect<Action> {
        if state.calendarStatus != .fullAccess {
            state.availableCalendars = nil
            return .none
        }

        return .run { [calendarAsync] send in
            let calendars = calendarAsync.getCalendars()
            await send(.loadListComplete(calendars.isEmpty ? nil : calendars))
        }
    }
}

public struct CalendarPickerView: View {
    @Bindable var store: StoreOf<CalendarPickerFeature>

    public init(store: StoreOf<CalendarPickerFeature>) {
        self.store = store
    }

    public var body: some View {
        HStack {
            if store.calendarStatus == .denied {
                Text("In order to use calendar events you will need to allow calendar access in the Settings App.")
                Button("Open Settings Application") {
                    store.send(.tapOpenSettings)
                }
            } else if store.calendarStatus == .restricted {
                Text("In order to use calendar events you will need to allow calendar access from Screen Time.")
                Button("Open Settings Application") {
                    store.send(.tapOpenSettings)
                }
            } else if store.calendarStatus != .fullAccess {
                Button("Authorize Calendar Access") {
                    store.send(.tapAuthorizeAccess)
                }
            } else if store.availableCalendars == nil {
                ContentUnavailableView("No Calendars Found", systemImage: "calendar")
            } else {
                Picker("Calendars", selection: $store.selectedCalendar) {
                    Text("None").tag(nil as CalendarId?)
                    ForEach(store.availableCalendars!, id: \.calendarIdentifier) { calendar in
                        Text(calendar.title).tag(CalendarId(calendar.calendarIdentifier) as CalendarId?)
                    }
                }.pickerStyle(.navigationLink)
            }
        }.onAppear {
            store.send(.onAppear)
        }
    }
}

#Preview {
    let _ = prepareDependencies {
        $0.defaultDatabase = try! $0.appDatabase()
    }

    NavigationStack {
        Form {
            CalendarPickerView(
                store: Store(
                    initialState: CalendarPickerFeature.State()
                ) {
                    CalendarPickerFeature()
                }
            )
        }
    }
}
