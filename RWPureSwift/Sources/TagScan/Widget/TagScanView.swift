import SwiftUI

struct TagScanView: View {
    @Binding var scanResult: Result<String, TagScanViewError>?
    
    var body: some View {
        VStack{
            if let sr = scanResult {
                switch sr {
                    case let .success(name):
                        VStack{
                            Image(systemName: "checkmark").font(.largeTitle).foregroundColor(Color.green)
                            Text("Thank you, \(name) for taking your meds!").font(.title)
                        }
                        .padding()
                        .background(Color.white)
                    case .failure(.unknownTag):
                        VStack{
                            Image(systemName: "questionmark").font(.largeTitle).foregroundColor(Color.red)
                            Text("Unknown Tag Scanned").font(.title)
                        }
                        .padding()
                        .background(Color.white)
                        .border(Color.red, width:10)
                    case .failure(.wrongScanWindow):
                        VStack{
                            Image(systemName: "clock.badge.exclamationmark").font(.largeTitle).foregroundColor(Color.red)
                            Text("Tag not scannable now, are you taking the right meds?").font(.title)
                        }
                        .padding()
                        .background(Color.white)
                        .border(Color.red, width:10)
                    case .failure(.noDevice):
                        VStack{
                            Image(systemName: "exclamationmark.octagon").font(.largeTitle).foregroundColor(Color.red)
                            Text("No NFC reader found, scans disabled.").font(.title)
                        }
                        .padding()
                        .background(Color.white)
                        .border(Color.red, width:10)
                    case let .failure(.unknown(e)):
                        VStack{
                            Image(systemName: "exclamationmark.octagon").font(.largeTitle).foregroundColor(Color.red)
                            Text("Error: \(e)").font(.title)
                        }
                        .padding()
                        .background(Color.white)
                        .border(Color.red, width:10)
                    }
            } else {
                EmptyView()
            }
        }.id(scanResult)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.5)) {
                scanResult = nil
            }
        }
        .task(id:scanResult) {
            if scanResult != nil{
                try? await Task.sleep(nanoseconds: UInt64(Double(5) * Double(NSEC_PER_SEC)))
                if !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        scanResult = nil
                    }
                }
            }
        }
    }
}

private func prevBuild(_ r:Result<String, TagScanViewError>?) -> any View{
    return ZStack{
        VStack{
            ContentUnavailableView("Underneath", image: "questionmark")
        }.background(Color.blue)
        TagScanView(scanResult: .constant(r))
    }
}

#Preview("no scan") {
    return prevBuild(nil)
}

#Preview("success") {
    return prevBuild(.success("Bob"))
}

#Preview("unknown tag") {
    return prevBuild(.failure(.unknownTag))
}

#Preview("no device") {
    return prevBuild(.failure(.noDevice))
}

#Preview("wrongScanWindow") {
    return prevBuild(.failure(.wrongScanWindow))
}

#Preview("error") {
    return prevBuild(.failure(.unknown("Bork Bork")))
}
