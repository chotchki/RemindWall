import Foundation
import PhotosUI

//From: https://stackoverflow.com/a/69755543
public class PHFetchResultCollection<T: PHObject>: RandomAccessCollection, Equatable {
    
    public typealias Element = T
    public typealias Index = Int
    
    let fetchResult: PHFetchResult<T>
    
    public var endIndex: Int { fetchResult.count }
    public var startIndex: Int { 0 }
    
    public init() {
        self.fetchResult = PHFetchResult()
    }
    
    public init(fetchResult: PHFetchResult<T>) {
        self.fetchResult = fetchResult
    }
    
    public subscript(position: Int) -> T {
        fetchResult.object(at: fetchResult.count - position - 1)
    }
    
    public static func == (lhs: PHFetchResultCollection<T>, rhs: PHFetchResultCollection<T>) -> Bool {
        return lhs.fetchResult == rhs.fetchResult
    }
}

// Type aliases for convenience and backward compatibility
//public typealias PHFetchResultAssetCollection = PHFetchResultCollection<PHAssetCollection>
//public typealias PHFetchResultAssets = PHFetchResultCollection<PHAsset>

// Mock subclass for testing
public final class PHFetchResultCollectionMock<T: PHObject>: PHFetchResultCollection<T> {
    
    private let mockArray: [T]
    
    public override var endIndex: Int { mockArray.count }
    
    public init(_ array: [T]) {
        self.mockArray = array
        super.init()
    }
    
    public override subscript(position: Int) -> T {
        mockArray[mockArray.count - position - 1]
    }
}

// Convenience type alias for PHAssetCollection mocks
public typealias PHFetchResultAssetCollectionMock = PHFetchResultCollectionMock<PHAssetCollection>
