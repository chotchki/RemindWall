//
//  SwiftUIView.swift
//  
//
//  Created by Christopher Hotchkiss on 7/13/24.
//

import SwiftUI

struct TimePicker: View {
    @Binding var hour: Int
    @Binding var minute: Int
    
    private var calendar: Calendar
    @State private var internalTime: Date
    
    public init(calendar: Calendar, hour: Binding<Int>, minute: Binding<Int>) {
        self.calendar = calendar
        self._hour = hour
        self._minute = minute
        
        var iTime = Date.now

        iTime = calendar.date(bySetting: .hour, value: hour.wrappedValue, of: iTime) ?? iTime
        iTime = calendar.date(bySetting: .minute, value: minute.wrappedValue, of: iTime) ?? iTime
        self.internalTime = iTime
    }
    
    var body: some View {
        DatePicker("Reminder Hour and Minute", selection: $internalTime,
                   displayedComponents: .hourAndMinute)
            .pickerStyle(.wheel)
            .labelsHidden()
            .onChange(of: internalTime) {
                let components = calendar.dateComponents([.hour, .minute], from: internalTime)
                if let hour = components.hour {
                    self.hour = hour
                }
                if let minute = components.minute {
                    self.minute = minute
                }
            }
    }
}

#Preview("Morning") {
    @Previewable @Environment(\.calendar) var calendar
    @Previewable @State var hour = 2
    @Previewable @State var minute = 10
    return TimePicker(calendar: calendar, hour: $hour, minute: $minute)
}

#Preview("Afternoon") {
    @Previewable @Environment(\.calendar) var calendar
    @Previewable @State var hour = 14
    @Previewable @State var minute = 10
    return TimePicker(calendar: calendar, hour: $hour, minute: $minute)
}
