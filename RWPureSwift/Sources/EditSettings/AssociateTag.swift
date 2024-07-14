//
//  SwiftUIView.swift
//  
//
//  Created by Christopher Hotchkiss on 7/14/24.
//

import SwiftUI

#if canImport(LibNFCSwift)
import LibNFCSwift

public enum TagReaderState: Equatable {
    case loading
    case noReader
    case waitingForRequest
    case waitingForTag
    case readTag([UInt8])
    case readerError(String)
}

struct AssociateTag: View {
    private var readerDriver = LibNFCActor.shared
    
    @State var readerState: TagReaderState = .loading
    
    @Binding var associatedTag: [UInt8]?
    
    public init(associatedTag: Binding<[UInt8]?>) {
        self._associatedTag = associatedTag
        
        
    }
    
    var body: some View {
        VStack{
            switch readerState {
            case .loading:
                Text("Loading")
            case .noReader:
                Text("No Reader Present")
            case .waitingForRequest:
                Button {
                    self.readerState = .waitingForTag
                    scanTag()
                } label:{
                    Text("Scan Tag")
                }
            case .waitingForTag:
                Text("Waiting for Tag")
            case .readTag(_):
                Button {
                    self.readerState = .waitingForTag
                    scanTag()
                } label: {
                    Text("Rescan Tag")
                }
            case .readerError(let error):
                Text("Reader Error \(error)")
            }
        }.task {
            do {
                let readers = try await readerDriver.list_devices()
                if readers.isEmpty {
                    self.readerState = .noReader
                } else {
                    self.readerState = .waitingForRequest
                }
            } catch {
                self.readerState = .readerError(error.localizedDescription)
            }
        }
    }
    
    private func scanTag(){
        Task {
            do {
                let tag = try await self.readerDriver.findFirstTag(modulation: NFCModulation.iSO14443A(), clock: ContinuousClock(), timeout: 30)
                if !tag.isEmpty {
                    associatedTag = tag
                    readerState = .readTag(tag)
                }
            } catch {
                self.readerState = .readerError(error.localizedDescription)
            }
        }
    }
}



#Preview {
    @State var associatedTag: [UInt8]? = nil
    return AssociateTag(associatedTag: $associatedTag)
}
#endif
