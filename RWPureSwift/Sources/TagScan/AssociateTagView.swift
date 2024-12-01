import CryptoTokenKit
import SwiftUI

public struct AssociateTagView: View {
    enum ScanState: Equatable {
        case idle
        case scanning
    }
    
    @Environment(\.modelContext) var modelContext
        
    @Binding var associatedTag: String?
    
    @State var readerState: ScanState = .idle
    @State private var scanTask: Task<Void, Never>?
    
    public init(associatedTag: Binding<String?>) {
        self._associatedTag = associatedTag
    }
    
    public var body: some View {
        VStack{
            HStack{
                Image(systemName: "sensor.tag.radiowaves.forward")
                if let associatedTag {
                    Text("Tag ID: \(associatedTag)")
                } else {
                    Text("No Configured Tag")
                }
            }
            Divider()
            switch readerState {
            case .idle:
                Button(action: startScanning) {
                    Text("Start Scanning")
                }
            case .scanning:
                Button(action: requestCancel){
                    Text("Cancel Scanning")
                }
            }
        }.padding()
            .background(.tertiary)
            .cornerRadius(15)
    }
    
    func startScanning() {
        readerState = .scanning
        
        if let scanTask {
            scanTask.cancel()
        }
        
        scanTask = Task {
            let tagId = await ReaderUtils.getNextTag()
            associatedTag = tagId?.hexa
            readerState = .idle
        }
    }
    
    func requestCancel() {
        scanTask?.cancel()
        readerState = .idle
    }
}

#Preview("No Tag") {
    @Previewable @State var associatedTag: String? = nil
    return AssociateTagView(associatedTag: $associatedTag)
}

#Preview("Existing Tag") {
    @Previewable @State var associatedTag: String? = "0:0:0"
    return AssociateTagView(associatedTag: $associatedTag)
}
