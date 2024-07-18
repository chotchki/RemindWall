import DataModel
import SwiftData
import SwiftUI

struct TrackeesView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    
    @Query(sort: \Trackee.name)
    var trackees: [Trackee]
    
    var body: some View {
        List {
            if trackees.isEmpty {
                Text("No trackees configured")
            } else {
                ForEach(trackees, id: \.id){ trackee in
                    NavigationLink {
                        EditTrackeeView(trackee: Bindable(trackee))
                    } label: {
                        HStack {
                            Text(trackee.name)
                            Spacer()
                            Text("Reminder Count - \(trackee.reminderTimes.count)")
                        }
                    }.padding()
                }.onDelete(perform: { offsets in
                    for offset in offsets {
                        let trackee = trackees[offset]
                        modelContext.delete(trackee)
                    }
                })
            }
            Button("Add Trackee", action: {
                modelContext
                    .insert(Trackee(id: UUID(), name: "Unknown", reminderTimes: []))
            })
        }
    }
}

#Preview {
    let container = Trackee.preview
    
    return NavigationStack{
        TrackeesView()
    }.modelContainer(container)
}
