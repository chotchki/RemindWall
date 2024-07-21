//
//  SwiftUIView.swift
//  
//
//  Created by Christopher Hotchkiss on 7/20/24.
//

import SwiftUI

struct SlideshowView: View {
    var body: some View {
        Image(systemName: "photo")
            .resizable(resizingMode: .stretch)
    }
}

#Preview {
    SlideshowView()
}
