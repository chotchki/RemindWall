import PhotosUI
import SwiftUI

public struct AssetLoaderView: View {
    let imageManager: PHCachingImageManager

    @State var viewModel: AssetLoaderViewModel
    
    public init(imageManager: PHCachingImageManager, asset: PHAsset, viewSize: CGSize) {
        self.imageManager = imageManager
        
        self.viewModel = AssetLoaderViewModel(asset: asset, viewSize: viewSize)
    }
    
    public var body: some View {
        VStack {
            switch viewModel.assetType {
            case .loading:
                ProgressView()
            case let .staticImage(ui):
                Image(uiImage: ui)
            case let .livePhoto(ph):
                LivePhotoView(livephoto: ph)
            case .errorPhoto:
                Text("Unable to load image")
            }
        }.frame(width:viewModel.viewSize.width, height: viewModel.viewSize.width)
        .task {
            await viewModel.load(imageManager: imageManager)
        }
        .onDisappear(perform: {
            imageManager.stopCachingImages(for: [viewModel.asset], targetSize: viewModel.viewSize, contentMode: getContentMode(), options: imageRequestOptions())
        })
    }
}
