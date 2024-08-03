import PhotosUI
import SwiftUI
import Utility

public struct AssetLoaderView: View {
    let asset: PHAsset
    let nextAsset: PHAsset?
    
    let viewSize: CGSize
    
    @State private var assetType: AssetType = .loading

    public init(asset: PHAsset, nextAsset: PHAsset?, viewSize: CGSize) {
        self.asset = asset
        self.nextAsset = nextAsset
        
        self.viewSize = viewSize
    }

    public var body: some View {
        VStack {
            switch assetType {
            case .loading:
                ProgressView()
            case let .staticImage(ui):
                Image(uiImage: ui)
            case let .livePhoto(ph):
                LivePhotoView(livephoto: ph)
            case .errorPhoto:
                Text("Unable to load image")
            }
        }.frame(width: viewSize.width, height: viewSize.width)
        .task(id: asset, {
            self.assetType = await PHImageCacheActor.shared.loadAsset(asset: asset, viewSize: viewSize)
            if let nA = nextAsset {
                await PHImageCacheActor.shared.startCaching(asset: nA, viewSize: viewSize)
            }
        }).onDisappear(perform: {
            Task {
                await PHImageCacheActor.shared.unloadCache(asset: asset, viewSize: viewSize)
            }
        })
    }
}
