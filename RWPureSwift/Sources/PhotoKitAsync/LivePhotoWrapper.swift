//
//  LivePhotoWrapper.swift
//  RWPureSwift
//
//  Created by Christopher Hotchkiss on 9/22/24.
//
import Photos

// Technique from here: https://forums.swift.org/t/how-to-use-non-sendable-type-in-async-reducer-code/62069/14
public class LivePhotoWrapper: @unchecked Sendable, Equatable {
    public var value: PHLivePhoto { _value.clone()}
    
    private var _value: PHLivePhoto

    public init(_ value: PHLivePhoto) {
        self._value = value.clone()
    }
    
    public static func == (lhs: LivePhotoWrapper, rhs: LivePhotoWrapper) -> Bool {
        lhs._value == rhs._value
    }
}

extension PHLivePhoto {
    /// Clones itself and returns the result.
    ///
    /// - Returns the clone.
    fileprivate func clone() -> PHLivePhoto {
        copy() as! PHLivePhoto
    }
}
