//
//  SwiftUIView.swift
//  
//
//  Created by Christopher Hotchkiss on 7/13/24.
//

import SwiftUI

struct TimePicker: View {
    @Binding var selectedTime: DateComponents
    
    private var calendar: Calendar
    @State private var internalTime: Date
    
    public init(calendar: Calendar, selectedTime: Binding<DateComponents>) {
        self.calendar = calendar
        self._selectedTime = selectedTime
        
        guard let hour = selectedTime.wrappedValue.hour, let minute = selectedTime.wrappedValue.minute else {
            self.internalTime = Date.now
            return
        }
        
        var iTime = Date.now

        iTime = calendar.date(bySetting: .hour, value: hour, of: iTime) ?? iTime
        iTime = calendar.date(bySetting: .minute, value: minute, of: iTime) ?? iTime
        self.internalTime = iTime
    }
    
    var body: some View {
        DatePicker("Reminder Day of Week and Time", selection: $internalTime,
                   displayedComponents: .hourAndMinute)
            .pickerStyle(.wheel)
            .labelsHidden()
            .onSubmit {
                let components = calendar.dateComponents([.hour, .minute], from: internalTime)
                if let hour = components.hour {
                    selectedTime.hour = hour
                }
                if let minute = components.minute {
                    selectedTime.minute = minute
                }
            }
    }
}

#Preview {
    @Environment(\.calendar) var calendar
    @State var d = DateComponents()
    return TimePicker(calendar: calendar, selectedTime: $d)
}
