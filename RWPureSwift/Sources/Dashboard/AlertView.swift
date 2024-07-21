//
//  SwiftUIView.swift
//  
//
//  Created by Christopher Hotchkiss on 7/20/24.
//

import SwiftUI

struct AlertView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Jax you are late for your meds!")
                .font(.custom("Overlay", size: 200, relativeTo: .largeTitle))
                .colorInvert()
                .frame(maxWidth:.infinity).multilineTextAlignment(.center)
            Spacer()
        }.background(Color.red.opacity(0.5))
    }
}

#Preview {
    AlertView()
}
