//
//  TimePicker.swift
//  
//
//  Created by Christopher Hotchkiss on 7/13/24.
//

import ComposableArchitecture
import SwiftUI

@Reducer
public struct TimePickerFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        @Shared var hour: Int
        @Shared var minute: Int
        
        public init(hour: Shared<Int>, minute: Shared<Int>) {
            self._hour = hour
            self._minute = minute
        }
        
        // Computed property for 12-hour display
        var displayHour: Int {
            let hour12 = hour % 12
            return hour12 == 0 ? 12 : hour12
        }
        
        // Computed property for AM/PM
        var isAM: Bool {
            hour < 12
        }
    }
    
    public enum Action {
        case incrementHour
        case decrementHour
        case incrementMinute
        case decrementMinute
        case toggleAMPM
    }
    
    public init() {}
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .incrementHour:
                state.$hour.withLock{$0 = ($0 + 1) % 24}
                return .none
                
            case .decrementHour:
                state.$hour.withLock{$0 = ($0 - 1 + 24) % 24}
                return .none
                
            case .incrementMinute:
                state.$minute.withLock{$0 = ($0 + 1) % 60}
                return .none
                
            case .decrementMinute:
                state.$minute.withLock{$0 = ($0 - 1 + 60) % 60}
                return .none
                
            case .toggleAMPM:
                if state.isAM {
                    // Switch to PM (add 12 hours)
                    state.$hour.withLock{$0 = ($0 + 12) % 24}
                } else {
                    // Switch to AM (subtract 12 hours)
                    state.$hour.withLock{$0 = ($0 - 12 + 24) % 24}
                }
                return .none
            }
        }
    }
}

public struct TimePickerView: View {
    let store: StoreOf<TimePickerFeature>
    
    public init(store: StoreOf<TimePickerFeature>) {
        self.store = store
    }
    
    public var body: some View {
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
                    
                    Text(String(format: "%02d", store.minute))
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
        .padding()
    }
}

#Preview("Morning") {
    let hour = Shared(value: 2)
    let min = Shared(value: 10)
    TimePickerView(store: Store(initialState: TimePickerFeature.State(hour: hour, minute: min)) {
        TimePickerFeature()
    })
}

#Preview("Afternoon") {
    let hour = Shared(value: 14)
    let min = Shared(value: 10)
    TimePickerView(store: Store(initialState: TimePickerFeature.State(hour: hour, minute: min)) {
        TimePickerFeature()
    })
}
