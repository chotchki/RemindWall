//
//  PhotoKitAssets.swift
//  RWPureSwift
//
//  Created by Christopher Hotchkiss on 10/13/25.
//

import Dependencies
import DependenciesMacros
import Photos

@DependencyClient
public struct PhotoKitAssets: Sendable {
    public var loadAsset: @Sendable (PHAsset, CGSize) async -> AssetType = { _, _ in
            .errorPhoto(PHAsset())
    }
    public var startCaching: @Sendable (PHAsset, CGSize) -> Void
    public var unloadCache: @Sendable (PHAsset, CGSize) -> Void
}

extension PhotoKitAssets: DependencyKey {
    public static var liveValue: Self {
        let cache = PHCachingImageManager()
        return Self(
            loadAsset: {
                asset, viewSize in
                
                if asset.mediaSubtypes.contains(PHAssetMediaSubtype.photoLive){
                    return await withCheckedContinuation({ continuation in
                        cache.requestLivePhoto(for: asset, targetSize: viewSize, contentMode: getContentMode(), options: livePhotoRequestOptions(), resultHandler: { livephoto, _ in
                            if let lp = livephoto {
                                continuation.resume(returning: .livePhoto(lp))
                            } else {
                                continuation.resume(returning: .errorPhoto(asset))
                            }
                        })
                    })
                } else if asset.mediaType == PHAssetMediaType.image {
                    return await withCheckedContinuation({ continuation in
                        cache.requestImage(for: asset, targetSize: viewSize, contentMode: getContentMode(), options: imageRequestOptions(), resultHandler: {
                                imageloaded, _ in
                                    if let il = imageloaded {
                                        continuation.resume(returning: .staticImage(il))
                                    } else {
                                        continuation.resume(returning: .errorPhoto(asset))
                                    }
                            })
                    })
                } else {
                    return AssetType.errorPhoto(asset)
                }
            },
            startCaching: {
                asset, viewSize in
                cache.startCachingImages(for: [asset], targetSize: viewSize, contentMode: getContentMode(), options: imageRequestOptions())
            },
            unloadCache: {
                asset, viewSize in
                cache.stopCachingImages(for: [asset], targetSize: viewSize, contentMode: getContentMode(), options: imageRequestOptions())
            }
        )
    }
}


extension PhotoKitAssets: TestDependencyKey {
    public static let testValue = Self()
}

extension DependencyValues {
  public var photoKitAssets: PhotoKitAssets {
    get { self[PhotoKitAssets.self] }
    set { self[PhotoKitAssets.self] = newValue }
  }
}
