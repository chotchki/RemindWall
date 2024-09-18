//
//  SwiftUIView.swift
//  
//
//  Created by Christopher Hotchkiss on 7/14/24.
//

import SwiftUI

#if canImport(LibNFCSwift)
import LibNFCSwift
#endif

#if canImport(CoreNFC)
import CoreNFC
#endif

public struct AssociateTagView: View {
    @Environment(\.modelContext) var modelContext
    
    #if canImport(LibNFCSwift)
    private var readerDriver = LibNFCActor.shared
    #endif
    
    @State var readerState: TagReaderState = .loading
    
    @Binding var associatedTag: String?
    
    public init(associatedTag: Binding<String?>) {
        self._associatedTag = associatedTag
    }
    
    public var body: some View {
        VStack{
            HStack{
                Image(systemName: "sensor.tag.radiowaves.forward")
                if let tag = $associatedTag.wrappedValue {
                    Text("Tag ID: \(tag)")
                } else {
                    Text("No Configured Tag")
                }
            }
            Divider()
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
                Button {
                    self.readerState = .waitingForTag
                    scanTag()
                } label: {
                    Text("Rescan Tag")
                }
            }
        }.padding()
            .background(.tertiary)
            .cornerRadius(15)
        .task {
            do {
                #if canImport(LibNFCSwift)
                let readers = try await readerDriver.list_devices()
                if readers.isEmpty {
                    self.readerState = .noReader
                } else {
                    self.readerState = .waitingForRequest
                }
                #endif
                
                #if canImport(CoreNFC)
                if !NFCReaderSession.readingAvailable {
                    self.readerState = .noReader
                } else {
                    self.readerState = .waitingForRequest
                }
                #endif
                
            } catch {
                self.readerState = .readerError(error.localizedDescription)
            }
        }
    }
    
    @MainActor
    private func scanTag(){
        Task {
            do {
                #if canImport(LibNFCSwift)
                let tag = try await self.readerDriver.findFirstTag(modulation: NFCModulation.iSO14443A(), clock: ContinuousClock(), timeout: 30)
                if !tag.isEmpty {
                    //BUG: If a tag is rescanned under another person, it will throw a fatal swift data error
                    self.associatedTag = tag.hexa
                    try modelContext.save()
                    self.readerState = .readTag(tag)
                }
                return
                #elseif canImport(CoreNFC)
                let stream = NFCTagReaderSessionStream()
                guard let session = NFCTagReaderSession(pollingOption: .iso14443, delegate: stream) else {
                    self.readerState = .readerError("Unable to start reader session")
                    return
                }
                session.begin()
                
                for await tag in stream.stream {
                    self.associatedTag = tag.hexa
                    try modelContext.save()
                    self.readerState = .readTag([UInt8](tag))
                    return
                }
                #endif
            } catch {
                self.readerState = .readerError(error.localizedDescription)
            }
        }
    }
}

#Preview("No Tag") {
    @State var associatedTag: String? = nil
    return AssociateTagView(associatedTag: $associatedTag)
}

#Preview("Existing Tag") {
    @State var associatedTag: String? = "0:0:0"
    return AssociateTagView(associatedTag: $associatedTag)
}
