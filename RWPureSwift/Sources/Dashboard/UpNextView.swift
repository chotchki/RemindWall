//
//  SwiftUIView.swift
//  
//
//  Created by Christopher Hotchkiss on 7/20/24.
//

import SwiftUI

struct UpNextView: View {
    var body: some View {
        HStack{
            Text("Up Next:").font(.largeTitle)
            VStack(alignment: .leading){
                Text("🍛").font(.title)
                Text("Dinner in 45min").font(.title).multilineTextAlignment(.leading)
            }
            
        }.padding()
    }
}

#Preview {
    UpNextView()
}
