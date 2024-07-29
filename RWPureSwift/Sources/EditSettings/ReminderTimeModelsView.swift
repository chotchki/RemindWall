import DataModel
import SwiftData
import SwiftUI

public struct ReminderTimeModelsView: View {
    @Environment(\.modelContext) var modelContext
    
    let trackeeId: UUID
    
    @Query private var reminderTimeModels: [ReminderTimeModel]
    
    public init(trackeeId: UUID){
        self.trackeeId = trackeeId
        
        _reminderTimeModels = Query(filter: #Predicate<ReminderTimeModel> { rtm in
            rtm.trackeeId == trackeeId
        })
    }
    
    public var body: some View {
        List {
            ForEach(reminderTimeModels, id: \.id){ reminderTimeModel in
                EditReminderTimeModelView(rtm: reminderTimeModel)
            }
            Button("Add New Reminder"){
                modelContext.insert(ReminderTimeModel(trackeeId: trackeeId))
            }
        }
    }
}
