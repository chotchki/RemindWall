//
//  PHAssetMock.swift
//  RWPureSwift
//
//  Created by Christopher Hotchkiss on 2/25/26.
//
// Idea from here: https://stackoverflow.com/q/59517411
import Dependencies
import Photos


public class PHAssetCollectionMock: PHAssetCollection, @unchecked Sendable {
    @Dependency(\.uuid) var uuid
    
    private var _localizedTitle: String?
    private var _localIdentifier: String = ""
    
    public convenience init(title: String) {
        self.init()
        self._localizedTitle = title
        self._localIdentifier = uuid().uuidString
    }
    
    public override var localIdentifier: String {
        return _localIdentifier
    }
    public override var localizedTitle: String? {
        return _localizedTitle
    }
    
}

/// A testable PHAsset subclass that provides its own identifier,
/// avoiding the internal `"Must have a uuid if no _objectID"` assertion
/// that PHAsset.init() triggers.
///
/// The trick: `mockIdentifier` is a stored property initialized before
/// `super.init()`, and we override both `localIdentifier` and the internal
/// ObjC `-[PHAsset identifier]` method. Because ObjC uses dynamic dispatch,
/// our overrides are called even during `super.init()`.
public class PHAssetMock: PHAsset, @unchecked Sendable {
    private let mockIdentifier: String

    public init(identifier: String = UUID().uuidString) {
        self.mockIdentifier = identifier
        super.init()
    }
    public override var localIdentifier: String {
        return mockIdentifier
    }

    /// Overrides the internal `-[PHAsset identifier]` method to prevent the assertion.
    @objc dynamic var identifier: String {
        return mockIdentifier
    }
}



