//
//  DragAndDrop.swift
//  Enchanted
//

import SwiftUI

struct DragAndDrop: View {
    var cornerRadius: CGFloat = 15

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.grayCustom.opacity(0.12))

            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 25))
                Text("Drop your image here")
                    .font(.title2)
            }
            .foregroundColor(.label)
            .padding(24)
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.grayCustom, style: StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [10]))
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .padding(5)
    }
}
