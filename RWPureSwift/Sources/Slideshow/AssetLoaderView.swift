import PhotosUI
import SwiftUI
import Utility

public struct AssetLoaderView: View {
    @Binding var asset: PHAsset
    let viewSize: CGSize
    
    @State private var assetType: AssetType = .loading

    public init(asset: Binding<PHAsset>, viewSize: CGSize) {
        self._asset = asset
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
        })
    }
}
