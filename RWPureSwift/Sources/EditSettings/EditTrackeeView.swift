//
//  EditTrackeeView.swift
//  RemindWall2
//
//  Created by Christopher Hotchkiss on 7/4/24.
//
import DataModel
import SwiftData
import SwiftUI

struct EditTrackeeView: View {
    @Environment(\.calendar) var calendar
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @Bindable var trackee: Trackee
    
    public init(trackee: Bindable<Trackee>) {
        self._trackee = trackee
    }
    
    var body: some View {
        NavigationStack{
            Form{
                Section {
                    TextField("Name", text: $trackee.name)
                } header: {
                    Text("Name")
                }
                
                Section {
                    List {
                        ForEach($trackee.reminderTimes){ reminderTime in
                            HStack{
                                VStack {
                                    Picker("Day of Week", selection: reminderTime.weekDay){
                                        Text("Sunday").tag(1)
                                        Text("Monday").tag(2)
                                        Text("Tuesday").tag(3)
                                        Text("Wednesday").tag(4)
                                        Text("Thursday").tag(5)
                                        Text("Friday").tag(6)
                                        Text("Saturday").tag(7)
                                    }
                                    HStack {
                                        Text("Time of Day")
                                        Spacer()
                                        TimePicker(calendar: calendar, hour: reminderTime.hour, minute: reminderTime.minute)
                                    }
                                }
                                
                                #if canImport(LibNFCSwift)
                                AssociateTag(associatedTag: reminderTime.associatedTag)
                                #else
                                if let tag = reminderTime.associatedTag? {
                                    Text("Configured Tag \(tag.hexa)")
                                } else {
                                    Text("No Tag Configured")
                                }
                                #endif
                            }
                        }
                        Button("Add New Reminder"){
                            trackee.reminderTimes
                                .append(
                                    ReminderTime()
                                )
                        }
                    }
                } header: {
                    Text("Reminder Times")
                }
            }
        }.navigationTitle("Edit Trackee")
    }
}

#Preview {
    let container = Trackee.preview
    
    let first = try! container.mainContext.fetch(FetchDescriptor<Trackee>()).first!
    
    return NavigationStack {
        EditTrackeeView(trackee: Bindable(first))
    }.modelContainer(container)
}
