//From: https://en.wikipedia.org/wiki/Ken_Burns_effect
import PhotoKitAsync
import SwiftUI

struct KenBurnsPanView: View {
    let assetType: AssetType
    let size: CGSize
    
    @State private var align : Alignment  = .topLeading
    
    var body: some View {
        VStack{
            switch assetType {
            case .loading:
                ProgressView()
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
                LivePhotoView(livephoto: pHLivePhoto).aspectRatio(contentMode: .fill)
                #else
                Text("Live photos not supported on this platform")
                #endif
            case .errorPhoto:
                ContentUnavailableView("Error Loading", image: "photo")
            }
        }
        .frame(width: size.width, height: size.height, alignment: align).clipped()
        .background(Color.red)
        .onAppear {
            withAnimation(.linear(duration: 10)) {
                self.align = .bottomTrailing
            }
        }
        .onChange(of: assetType){
            self.align = .topLeading
            withAnimation(.linear(duration: 10)) {
                self.align = .bottomTrailing
            }
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
