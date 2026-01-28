//
//  TagScanner.swift
//  RW2
//
//  Created by Christopher Hotchkiss on 10/6/25.
//

import Combine
@preconcurrency import CryptoTokenKit
import Deadline
import Dependencies
import DependenciesMacros
import TagTypes
import Tagged


@DependencyClient
public struct TagReaderClient: Sendable {
    public var slotNames: @Sendable () -> [SlotName] = { [] }
    public var nextTagId: @Sendable (SlotName, Duration) async -> ReaderState = {_,_ in .noTag}
    
    public typealias SlotName = Tagged<TagReaderClient, String>
}

extension TagReaderClient: DependencyKey {
    public static var liveValue: Self {
        let slotManager = TKSmartCardSlotManager.default
        return Self(
            slotNames: { slotManager?.slotNames.map{ SlotName($0)} ?? [] },
            nextTagId: {
                slotName, timeout in
                
                guard let slot = await slotManager?.getSlot(withName: slotName.rawValue) else {
                    return .readerError("couldn't get slot")
                }
                
                let slotMonitor = SlotMonitor(slot:slot)
                
                do {
                    return try await deadline(until: .now + timeout){
                        return await slotMonitor.getNextTag()
                    }
                } catch {
                    return .noTag
                }
            })
        }
    public static let previewValue = TagReaderClient(
        slotNames: { ["previewSlot"] },
        nextTagId: {
            _,_ in
                .noTag
        }
    )
}

extension TagReaderClient: TestDependencyKey {
    public static let testValue = Self()
}

extension DependencyValues {
  public var tagReaderClient: TagReaderClient {
    get { self[TagReaderClient.self] }
    set { self[TagReaderClient.self] = newValue }
  }
}

extension TKTokenWatcher {
    typealias AsyncValues<T> = AsyncPublisher<AnyPublisher<T, Never>>
    func observeKey<T>(at path: KeyPath<TKTokenWatcher, T>) -> AsyncValues<T> {
        return self.publisher(for: path, options: [.initial, .new])
            .eraseToAnyPublisher()
            .values
    }
}
