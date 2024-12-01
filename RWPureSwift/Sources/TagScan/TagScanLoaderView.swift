import CoreNFC
import CryptoTokenKit
import DataModel
import SwiftData
import SwiftUI
import OSLog
import Utility

public struct TagScanLoaderView: View {
    let log = Logger()
    @Environment(\.calendar) var calendar
    @Environment(\.modelContext) var modelContext
    
    @State private var slotManager: TKSmartCardSlotManager? = TKSmartCardSlotManager.default
    
    let timeout: Int = 60
    
    public init(){}
    
    @State private var scanResult: Result<String, TagScanViewError>?
    
    public var body: some View {
        TagScanView(scanResult: $scanResult)
        .task {
            while !Task.isCancelled {
                let result = await ReaderUtils.getNextTag()
                                
                guard let tagFound = result?.hexa else {
                    //No tag found, that's fine
                    continue
                }
                    
                log.warning("Found \(tagFound)")
                    
                let fd = FetchDescriptor<ReminderTimeModel>()
                guard let rtms = try? modelContext.fetch(fd) else {
                    self.scanResult = .failure(.unknown("Fetch error"))
                    continue
                }
                    
                let filteredRtms = rtms.filter{
                    $0.associatedTag != nil && $0.associatedTag == tagFound
                }
                    
                guard let rtm = filteredRtms.first else {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        self.scanResult = .failure(.unknownTag)
                    }
                    continue
                }
                
                log.warning("Lookup worked")
                    
                if rtm.isScannable(date: Date.now, calendar: calendar){
                    rtm.lastScan = Date.now
                    guard let _ = try? modelContext.save() else {
                        self.scanResult = .failure(.unknown("Unable to save scan"))
                        continue
                    }
                    
                    //Now try to get a name for the pop up
                    guard let trackees = try? modelContext.fetch(FetchDescriptor<Trackee>()) else {
                        self.scanResult = .failure(.unknown("Trackee fetch error"))
                        continue
                    }
                    let foundTrackee = trackees.first(where: {$0.id == rtm.trackeeId})
                    
                    withAnimation(.easeInOut(duration: 0.5)) {
                        self.scanResult = .success(foundTrackee?.name ?? "Name Not Found")
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        self.scanResult = .failure(.wrongScanWindow)
                    }
                }
            }
        }
    }
}
