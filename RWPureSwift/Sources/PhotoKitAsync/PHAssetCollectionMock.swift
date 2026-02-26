//
//  PHAssetMock.swift
//  RWPureSwift
//
//  Created by Christopher Hotchkiss on 2/25/26.
//
// Idea from here: https://stackoverflow.com/q/59517411
import Photos

public class PHAssetCollectionMock: PHAssetCollection, @unchecked Sendable {
    private var _localizedTitle: String?
    
    public convenience init(title: String) {
        self.init()
        self._localizedTitle = title
    }
    
    public override var localizedTitle: String? {
        return _localizedTitle
    }
}
