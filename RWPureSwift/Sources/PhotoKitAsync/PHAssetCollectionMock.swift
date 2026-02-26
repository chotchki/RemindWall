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
