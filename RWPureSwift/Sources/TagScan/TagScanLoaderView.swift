import DataModel
import SwiftData
import SwiftUI
import LibNFCSwift
import OSLog
import Utility

public struct TagScanLoaderView: View {
    let log = Logger()
    @Environment(\.calendar) var calendar
    @Environment(\.modelContext) var modelContext
    
    let timeout: Int = 60
    
    public init(){}
    
    @State private var scanResult: Result<String, TagScanViewError>?
    
    public var body: some View {
        TagScanView(scanResult: $scanResult)
        .task {
            while !Task.isCancelled {
                do {
                    let tagFound = try await LibNFCActor.shared.findFirstTag(modulation: .iSO14443A(), clock: .continuous, timeout: timeout).hexa
                    
                    if Task.isCancelled {
                        return
                    }
                    
                    log.warning("Found \(tagFound)")
                    
                    let fd = FetchDescriptor<ReminderTimeModel>()
                    let rtms = try modelContext.fetch(fd)
                    
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
                        try modelContext.save()
                        
                        //Now try to get a name for the pop up
                        let trackees = try modelContext.fetch(FetchDescriptor<Trackee>())
                        let foundTrackee = trackees.first(where: {$0.id == rtm.trackeeId})
                        
                        withAnimation(.easeInOut(duration: 0.5)) {
                            self.scanResult = .success(foundTrackee?.name ?? "Name Not Found")
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            self.scanResult = .failure(.wrongScanWindow)
                        }
                    }
                } catch LibNFCError.pollTimeout {
                    //Timeout is fine
                } catch LibNFCError.deviceConnectFailed {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        self.scanResult = .failure(.noDevice)
                    }
                    try? await Task.sleep(nanoseconds: UInt64(Double(timeout) * Double(NSEC_PER_SEC))) //TODO: Change to a minute later
                } catch {
                    // Supress other errors
                    withAnimation(.easeInOut(duration: 0.5)) {
                        self.scanResult = .failure(.unknown(error.localizedDescription))
                    }
                }
            }
        }
    }
}
