//From: https://en.wikipedia.org/wiki/Ken_Burns_effect

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
                Image(uiImage: uIImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .livePhoto(let pHLivePhoto):
                LivePhotoView(livephoto: pHLivePhoto).aspectRatio(contentMode: .fill)
            case .errorPhoto:
                ContentUnavailableView("Error Loading", image: "photo")
            }
        }
        .frame(width: size.width, height: size.height, alignment: align).clipped()
        .background(Color.red)
        .task {
            withAnimation(.linear(duration: 10)) {
                self.align = .bottomTrailing
            }
        }
    }
}

#Preview("Portrait") {
    let image = UIImage(named: "PortraitTest", in: Bundle.module, compatibleWith: nil)
    return VStack {
        //Spacer()
        HStack{
            //Spacer()
            KenBurnsPanView(assetType: .staticImage(image!), size: CGSize(width: 400, height: 600))
        }
    }.background(Color.blue)
    .frame(width: 500, height: 700, alignment: .center)
}

#Preview("Landscape") {
    let image = UIImage(named: "LandscapeTest", in: Bundle.module, compatibleWith: nil)
    return VStack {
        //Spacer()
        HStack{
            //Spacer()
            KenBurnsPanView(assetType: .staticImage(image!), size: CGSize(width: 400, height: 600))
        }
    }.background(Color.blue)
    .frame(width: 500, height: 700, alignment: .center)
}
