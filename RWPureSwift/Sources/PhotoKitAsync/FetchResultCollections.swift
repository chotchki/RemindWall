import Foundation
import PhotosUI

//From: https://stackoverflow.com/a/69755543
public struct PHFetchResultCollection: RandomAccessCollection, Equatable {
    
    public typealias Element = PHAsset
    public typealias Index = Int
    
    let fetchResult: PHFetchResult<PHAsset>
    
    public var endIndex: Int { fetchResult.count }
    public var startIndex: Int { 0 }
    
    public init(fetchResult: PHFetchResult<PHAsset>) {
        self.fetchResult = fetchResult
    }
    
    public subscript(position: Int) -> PHAsset {
        fetchResult.object(at: fetchResult.count - position - 1)
    }
}

public struct PHFetchResultAssetCollection: RandomAccessCollection, Equatable {
    
    public typealias Element = PHAssetCollection
    public typealias Index = Int
    
    let fetchResult: PHFetchResult<PHAssetCollection>
    
    public var endIndex: Int { fetchResult.count }
    public var startIndex: Int { 0 }
    
    public init(fetchResult: PHFetchResult<PHAssetCollection>) {
        self.fetchResult = fetchResult
    }
    
    public subscript(position: Int) -> PHAssetCollection {
        fetchResult.object(at: fetchResult.count - position - 1)
    }
}
