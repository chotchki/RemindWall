import DataModel
import SwiftData
import SwiftUI
import LibNFCSwift
import OSLog
import Utility

public struct TagScanView: View {
    let log = Logger()
    @Environment(\.calendar) var calendar
    @Environment(\.modelContext) var modelContext
    
    let timeout: Int = 60
    
    public init(){}
    
    public enum TagScanViewError: Error {
        case unknownTag
        case wrongScanWindow
        case noDevice
        case unknown(String)
    }
    
    @State private var scanResult: Result<(), TagScanViewError>?
    
    public var body: some View {
        VStack{
            if let sr = scanResult {
                VStack {
                    Spacer()
                    switch sr {
                    case .success:
                        Text("Thank you for taking your meds!")
                    case .failure(.unknownTag):
                        Text("Unknown Tag Scanned")
                    case .failure(.wrongScanWindow):
                        Text("Tag not scannable now, are you taking the right meds?")
                    case .failure(.noDevice):
                        Text("No NFC reader found, scans disabled.")
                    case let .failure(.unknown(e)):
                        Text("Unknown failure \(e)")
                    }
                    Spacer()
                }.padding()
                .background(Color.white)
            } else {
                EmptyView()
            }
        }
        .task {
            while !Task.isCancelled {
                do {
                    let tagFound = try await LibNFCActor.shared.findFirstTag(modulation: .iSO14443A(), clock: .continuous, timeout: timeout).hexa
                    
                    log.warning("Found \(tagFound)")
                    
                    let fd = FetchDescriptor<ReminderTimeModel>()
                    let rtms = try modelContext.fetch(fd)
                    
                    let filteredRtms = rtms.filter{
                        $0.associatedTag != nil && $0.associatedTag == tagFound
                    }
                    
                    guard let rtm = filteredRtms.first else {
                        self.scanResult = .failure(.unknownTag)
                        continue
                    }
                    
                    log.warning("Lookup worked")
                    
                    if rtm.isScannable(date: Date.now, calendar: calendar){
                        rtm.lastScan = Date.now
                        try modelContext.save()
                        
                        self.scanResult = .success(())
                        
                    } else {
                        self.scanResult = .failure(.wrongScanWindow)
                    }
                } catch LibNFCError.pollTimeout {
                    //Timeout is fine
                } catch LibNFCError.deviceConnectFailed {
                    self.scanResult = .failure(.noDevice)
                    try? await Task.sleep(nanoseconds: UInt64(Double(timeout) * Double(NSEC_PER_SEC))) //TODO: Change to a minute later
                } catch {
                    // Supress other errors
                    self.scanResult = .failure(.unknown(error.localizedDescription))
                }
            }
        }.onTapGesture {
            self.scanResult = nil //Clear scan
        }
    }
}

#Preview {
    TagScanView()
}
