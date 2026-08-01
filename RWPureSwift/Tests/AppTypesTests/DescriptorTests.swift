import AppTypes
import Testing

@Suite("Descriptor Tests")
struct DescriptorTests {
    @Test("CalendarDescriptor round-trips title and source")
    func calendarRoundTrip() {
        let descriptor = CalendarDescriptor(title: "Family", sourceTitle: "iCloud")
        #expect(descriptor.rawValue == "Family|iCloud")
        #expect(descriptor.title == "Family")
        #expect(descriptor.sourceTitle == "iCloud")
    }

    @Test("CalendarDescriptor splits at the LAST pipe so titles may contain pipes")
    func calendarPipeInTitle() {
        let descriptor = CalendarDescriptor(title: "Work | Personal", sourceTitle: "iCloud")
        #expect(descriptor.title == "Work | Personal")
        #expect(descriptor.sourceTitle == "iCloud")
    }

    @Test("CalendarDescriptor without a pipe reads whole value as title")
    func calendarNoPipe() {
        let descriptor = CalendarDescriptor(rawValue: "LegacyValue")
        #expect(descriptor.title == "LegacyValue")
        #expect(descriptor.sourceTitle == "")
    }

    @Test("noSelection is distinct from a real descriptor")
    func noSelectionDistinct() {
        #expect(CalendarDescriptor.noSelection != CalendarDescriptor(title: "Family", sourceTitle: "iCloud"))
        #expect(CalendarDescriptor.noSelection.title == "")
        #expect(CalendarDescriptor.noSelection.sourceTitle == "")
    }

    @Test("Empty source still round-trips")
    func emptySource() {
        let descriptor = CalendarDescriptor(title: "Local", sourceTitle: "")
        #expect(descriptor.title == "Local")
        #expect(descriptor.sourceTitle == "")
        #expect(descriptor != .noSelection)
    }
}
