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
                        ReminderTimeModelsView(trackeeId: trackee.id)
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
