//
//  PhotoKitDependency.swift
//  RWPureSwift
//
//  Created by Christopher Hotchkiss on 10/13/25.
//
import AppTypes
import Dao
import Dependencies
import DependenciesMacros
import Photos
import UIKit

@DependencyClient
public struct PhotoKitAlbums: Sendable {
    
    
    public var libraryAccess: @Sendable () -> PHAuthorizationStatus = { .denied }
    public var openPhotoSettings: @Sendable () async -> ()
    public var requestAuthorization: @Sendable () async -> ()
    public var availableAlbums: @Sendable () async -> PHFetchResultCollection<PHAssetCollection>?
    public var loadAlbumAssets: @Sendable (AlbumLocalId) async -> [PHAsset]?
}

extension PhotoKitAlbums: DependencyKey {
    
    
    public static var liveValue: Self {
        return Self(
            libraryAccess: {
                return PHPhotoLibrary.authorizationStatus(for: .readWrite)
            },
            openPhotoSettings: {
                @Dependency(\.fireAndForget) var fireAndForget
                await fireAndForget { @MainActor in
                    #if targetEnvironment(macCatalyst)
                    let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos"
                    await UIApplication.shared.open(URL(string: url)!)
                    #else
                    let url = UIApplication.openSettingsURLString
                    UIApplication.shared.open(URL(string: url)!)
                    #endif
                }
            },
            requestAuthorization: {
                await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            },
            availableAlbums: {
                if PHPhotoLibrary.authorizationStatus(for: .readWrite) != .authorized {
                    return nil
                }
                
                let albums = PHAssetCollection.fetchAssetCollections(
                    with: PHAssetCollectionType.album,
                    subtype: PHAssetCollectionSubtype.any,
                    options: baseFetchOptions())
                return PHFetchResultCollection(fetchResult: albums)
            },
            loadAlbumAssets: {albumId in
                if PHPhotoLibrary.authorizationStatus(for: .readWrite) != .authorized {
                    return nil
                }
                
                let result = await Task {
                    guard let fetchAlbumObj = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumId.rawValue], options: baseFetchOptions()).firstObject else {
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
    
    public static var previewValue: Self {
        return Self(
            libraryAccess: {
                return .authorized
            },
            openPhotoSettings: {},
            requestAuthorization: {},
            availableAlbums: {
                let albums = [
                    PHAssetCollectionMock(title: "Day at Park"),
                    PHAssetCollectionMock(title: "Cats")
                ]
                return PHFetchResultCollectionMock<PHAssetCollection>(albums)
            },
            loadAlbumAssets: { _ in
                return [
                    //TODO Add some placeholders
                ]
            }
        )
    }
}

extension DependencyValues {
  public var photoKitAlbums: PhotoKitAlbums {
    get { self[PhotoKitAlbums.self] }
    set { self[PhotoKitAlbums.self] = newValue }
  }
}
