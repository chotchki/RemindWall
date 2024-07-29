import DataModel
import SwiftUI
#if canImport(TagScan)
import TagScan
#endif

public struct EditReminderTimeModelView: View {
    @Environment(\.calendar) var calendar
    
    @Bindable var rtm: ReminderTimeModel
    
    public var body: some View {
        HStack{
            VStack {
                Picker("Day of Week", selection: $rtm.weekDay){
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
                    TimePicker(calendar: calendar, hour: $rtm.hour, minute: $rtm.minute)
                }
                if let ls = rtm.lastScan {
                    Text("Last Scanned: \(ls)")
                } else {
                    Text("Never Scanned")
                }
            }
            
#if canImport(TagScan)
            AssociateTagView(associatedTag: $rtm.associatedTag)
#else
            if let tag = reminderTime.associatedTag? {
                Text("Configured Tag \(tag)")
            } else {
                Text("No Tag Configured")
            }
#endif
        }
    }
}
