//
//  TagScanner.swift
//  RW2
//
//  Created by Christopher Hotchkiss on 10/6/25.
//

import AppTypes
import Combine
@preconcurrency import CryptoTokenKit
import Dependencies
import DependenciesMacros


@DependencyClient
public struct TagReaderClient: Sendable {
    public var nextTagId: () async -> ReaderState = {.noTag}
}

extension TagReaderClient: DependencyKey {
    public static var liveValue: Self {
        
        return Self(
            nextTagId: {
                let slotMonitor = SlotMonitor()

                return await slotMonitor.getNextTag()
            })
        }
    public static let previewValue = TagReaderClient(
        nextTagId: {
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
