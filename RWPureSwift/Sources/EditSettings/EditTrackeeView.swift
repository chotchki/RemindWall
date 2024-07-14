//
//  EditTrackeeView.swift
//  RemindWall2
//
//  Created by Christopher Hotchkiss on 7/4/24.
//
import DataModel
import SwiftUI

struct EditTrackeeView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var trackee: Trackee
    
    var body: some View {
        NavigationStack{
            Form{
                Section {
                    TextField("Name", text: $trackee.name)
                }
                
                Section {
                    List {
                        ForEach($trackee.reminderTimes){ reminderTime in
                            HStack{
                                Picker("Day", selection: reminderTime.components.weekday){
                                    Text("Sunday").tag(1)
                                    Text("Monday").tag(2)
                                    Text("Tuesday").tag(3)
                                    Text("Wednesday").tag(4)
                                    Text("Thursday").tag(5)
                                    Text("Friday").tag(6)
                                    Text("Saturday").tag(7)
                                }
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
            .toolbar(content: {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action:{
                        dismiss()
                    })
                }
            })
    }
}

#Preview {
    @State var trackee = Trackee(
        id: UUID(),
        name: "Bob",
        reminderTimes: []
    )
    return EditTrackeeView(trackee: trackee)
}
