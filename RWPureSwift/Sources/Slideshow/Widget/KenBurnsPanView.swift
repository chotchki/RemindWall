//From: https://en.wikipedia.org/wiki/Ken_Burns_effect
import PhotoKitAsync
import SwiftUI

struct KenBurnsPanView: View {
    let assetType: AssetType
    let size: CGSize

    @State private var align: Alignment = .center

    /// Pan routes for images that overflow horizontally (landscape photo in portrait/square view)
    private static let horizontalRoutes: [(Alignment, Alignment)] = [
        (.leading, .trailing),
        (.trailing, .leading),
        (.topLeading, .bottomTrailing),
        (.bottomTrailing, .topLeading),
        (.bottomLeading, .topTrailing),
        (.topTrailing, .bottomLeading),
    ]

    /// Pan routes for images that overflow vertically (portrait photo in landscape/square view)
    private static let verticalRoutes: [(Alignment, Alignment)] = [
        (.top, .bottom),
        (.bottom, .top),
        (.topLeading, .bottomTrailing),
        (.bottomTrailing, .topLeading),
        (.topTrailing, .bottomLeading),
        (.bottomLeading, .topTrailing),
    ]

    /// Pan routes for images with similar aspect ratio to the view
    private static let diagonalRoutes: [(Alignment, Alignment)] = [
        (.topLeading, .bottomTrailing),
        (.bottomTrailing, .topLeading),
        (.topTrailing, .bottomLeading),
        (.bottomLeading, .topTrailing),
    ]

    private var imageAspectRatio: CGFloat? {
        switch assetType {
        case .staticImage(let image):
            guard image.size.height > 0 else { return nil }
            return image.size.width / image.size.height
        case .livePhoto(let livePhoto):
            guard livePhoto.size.height > 0 else { return nil }
            return livePhoto.size.width / livePhoto.size.height
        default:
            return nil
        }
    }

    private func pickRoute() -> (start: Alignment, end: Alignment) {
        let viewAspect = size.height > 0 ? size.width / size.height : 1.0
        let routes: [(Alignment, Alignment)]

        if let imgAspect = imageAspectRatio {
            if imgAspect > viewAspect * 1.1 {
                routes = Self.horizontalRoutes
            } else if imgAspect < viewAspect * 0.9 {
                routes = Self.verticalRoutes
            } else {
                routes = Self.diagonalRoutes
            }
        } else {
            routes = Self.diagonalRoutes
        }

        return routes.randomElement()!
    }

    private func startPanAnimation() {
        let route = pickRoute()
        // Use an explicit transaction with no animation to prevent
        // inherited animations (e.g. the parent's opacity transition)
        // from animating the snap to the start position.
        var snap = Transaction()
        snap.animation = nil
        withTransaction(snap) {
            align = route.start
        }
        withAnimation(.easeInOut(duration: 10)) {
            align = route.end
        }
    }

    var body: some View {
        VStack{
            switch assetType {
            case .loading:
                ProgressView()
                    .scaleEffect(2.0)
                    .tint(.white)
            case .staticImage(let uIImage):
                #if canImport(UIKit)
                Image(uiImage: uIImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                #else
                Image(nsImage: uIImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                #endif
            case .livePhoto(let pHLivePhoto):
                #if canImport(UIKit)
                LivePhotoView(livephoto: pHLivePhoto)
                    .frame(width: size.width * 1.3, height: size.height * 1.3)
                #else
                Text("Live photos not supported on this platform")
                #endif
            case .errorPhoto:
                ContentUnavailableView("Error Loading", image: "photo")
            }
        }
        .frame(width: size.width, height: size.height, alignment: align).clipped()
        .background(Color.black)
        .onAppear {
            startPanAnimation()
        }
        .onChange(of: assetType) {
            startPanAnimation()
        }
    }
}

#if canImport(UIKit)
#Preview("Portrait") {
    @Previewable @State var image = AssetType.staticImage(UIImage(named: "PortraitTest", in: Bundle.module, compatibleWith: nil)!)
    
    VStack {
        HStack{
            KenBurnsPanView(assetType: image, size: CGSize(width: 400, height: 600))
        }
    }.background(Color.blue)
    .frame(width: 500, height: 700, alignment: .center)
}

#Preview("Landscape") {
    @Previewable @State var image = AssetType.staticImage(UIImage(named: "LandscapeTest", in: Bundle.module, compatibleWith: nil)!)
    
    VStack {
        HStack{
            KenBurnsPanView(assetType: image, size: CGSize(width: 400, height: 600))
        }
    }.background(Color.blue)
    .frame(width: 500, height: 700, alignment: .center)
}

#Preview("Transition") {
    @Previewable @State var image = AssetType.staticImage(UIImage(named: "LandscapeTest", in: Bundle.module, compatibleWith: nil)!)
    
    VStack {
        HStack{
            KenBurnsPanView(assetType: image, size: CGSize(width: 400, height: 600))
        }
    }.task{
        try? await Task.sleep(for: .seconds(10));
        image = AssetType.staticImage(UIImage(named: "PortraitTest", in: Bundle.module, compatibleWith: nil)!)
    }
    .background(Color.blue)
        .frame(width: 500, height: 700, alignment: .center)
}
#endif
