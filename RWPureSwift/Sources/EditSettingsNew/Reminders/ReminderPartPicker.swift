//
//  TimePicker.swift
//  
//
//  Created by Christopher Hotchkiss on 7/13/24.
//
import AppTypes
import ComposableArchitecture
import SwiftUI

@Reducer
public struct ReminderPartFeature {
    @ObservableState
    public struct State: Equatable {
        @Shared var reminderPart: ReminderPart
        
        public init(_ reminderPart: Shared<ReminderPart>) {
            self._reminderPart = reminderPart
        }
        
        // Computed property for 12-hour display
        var displayHour: Int {
            let hour12 = reminderPart.hour % 12
            return hour12 == 0 ? 12 : hour12
        }
        
        // Computed property for AM/PM
        var isAM: Bool {
            reminderPart.hour < 12
        }
    }
    
    public enum Action {
        case incrementHour
        case decrementHour
        case incrementMinute
        case decrementMinute
        case toggleAMPM
        case setWeekDay(DaysOfWeek)
    }
    
    public init() {}
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .incrementHour:
                state.$reminderPart.hour.withLock{$0 = ($0 + 1) % 24}
                return .none
                
            case .decrementHour:
                state.$reminderPart.hour.withLock{$0 = ($0 - 1 + 24) % 24}
                return .none
                
            case .incrementMinute:
                state.$reminderPart.minute.withLock{$0 = ($0 + 1) % 60}
                return .none
                
            case .decrementMinute:
                state.$reminderPart.minute.withLock{$0 = ($0 - 1 + 60) % 60}
                return .none
                
            case .toggleAMPM:
                if state.isAM {
                    // Switch to PM (add 12 hours)
                    state.$reminderPart.hour.withLock{$0 = ($0 + 12) % 24}
                } else {
                    // Switch to AM (subtract 12 hours)
                    state.$reminderPart.hour.withLock{$0 = ($0 - 12 + 24) % 24}
                }
                return .none
                
            case .setWeekDay(let day):
                state.$reminderPart.weekDay.withLock{$0 = day}
                return .none
            }
        }
    }
}

public struct ReminderPartView: View {
    @Bindable var store: StoreOf<ReminderPartFeature>
    
    public init(store: StoreOf<ReminderPartFeature>) {
        self.store = store
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            Picker("Day of Week", selection: Binding(
                get: { store.reminderPart.weekDay },
                set: { store.send(.setWeekDay($0)) }
            )) {
                ForEach(DaysOfWeek.allCases, id:\.rawValue){day in
                    Text(String(describing:day)).tag(day).frame(minHeight: 60)
                }
            }.pickerStyle(.segmented)
                
            
            // Time Selector
            HStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Hour")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        Button {
                            store.send(.decrementHour)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        
                        Text(String(format: "%02d", store.displayHour))
                            .font(.system(size: 48, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(minWidth: 80)
                        
                        Button {
                            store.send(.incrementHour)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
                
                Text(":")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)
                
                VStack(spacing: 8) {
                    Text("Minute")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        Button {
                            store.send(.decrementMinute)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        
                        Text(String(format: "%02d", store.reminderPart.minute))
                            .font(.system(size: 48, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(minWidth: 80)
                        
                        Button {
                            store.send(.incrementMinute)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
                
                VStack(spacing: 8) {
                    Text("Period")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 12) {
                        Button {
                            store.send(.toggleAMPM)
                        } label: {
                            Text(store.isAM ? "AM" : "PM")
                                .font(.system(size: 32, weight: .semibold, design: .rounded))
                                .frame(minWidth: 80, minHeight: 60)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.accentColor.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    
                }
            }
        }
        .padding()
    }
}

#Preview("Morning") {
    let rp = Shared(value: ReminderPart(weekDay: .Sunday, hour: 2, minute: 3))

    ReminderPartView(store: Store(initialState: ReminderPartFeature.State(rp)) {
        ReminderPartFeature()
    })
}

#Preview("Afternoon") {
    let rp = Shared(value: ReminderPart(weekDay: .Sunday, hour: 14, minute: 3))
    
    ReminderPartView(store: Store(initialState: ReminderPartFeature.State(rp)) {
        ReminderPartFeature()
    })
}
