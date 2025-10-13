//
//  PhotoKitDependency.swift
//  RWPureSwift
//
//  Created by Christopher Hotchkiss on 10/13/25.
//
import Dependencies
import DependenciesMacros
import Photos

@DependencyClient
public struct PhotoKitAlbums: Sendable {
    public var libraryAccess: @Sendable () -> PHAuthorizationStatus = { .denied }
    public var availibleAlbums: @Sendable () async -> PHFetchResultAssetCollection?
    public var loadAlbumAssets: @Sendable (String) async -> [PHAsset]?
}

extension PhotoKitAlbums: DependencyKey {
    public static var liveValue: Self {
        return Self(
            libraryAccess: {
                return PHPhotoLibrary.authorizationStatus(for: .readWrite)
            },
            availibleAlbums: {
                if PHPhotoLibrary.authorizationStatus(for: .readWrite) != .authorized {
                    return nil
                }
                
                let albums = PHAssetCollection.fetchAssetCollections(
                    with: PHAssetCollectionType.album,
                    subtype: PHAssetCollectionSubtype.any,
                    options: baseFetchOptions())
                return PHFetchResultAssetCollection(fetchResult: albums)
            },
            loadAlbumAssets: {albumId in
                if PHPhotoLibrary.authorizationStatus(for: .readWrite) != .authorized {
                    return nil
                }
                
                let result = await Task {
                    guard let fetchAlbumObj = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumId], options: baseFetchOptions()).firstObject else {
                        return nil as [PHAsset]?
                    }
                    
                    let fetchResult = PHAsset.fetchAssets(in: fetchAlbumObj, options: albumContentsFetchOptions())
                    
                    // The caching image manager demands an array so we can't leverage the fetchresult
                    var contents: [PHAsset] = []
                    fetchResult.enumerateObjects({ obj, _, _ in
                        contents.append(obj)
                    })
                    contents.shuffle()
                    
                    return contents
                }.value

                return result
            }
        )

    }
}

extension PhotoKitAlbums: TestDependencyKey {
    public static let testValue = Self()
}

extension DependencyValues {
  public var photoKitAlbums: PhotoKitAlbums {
    get { self[PhotoKitAlbums.self] }
    set { self[PhotoKitAlbums.self] = newValue }
  }
}
