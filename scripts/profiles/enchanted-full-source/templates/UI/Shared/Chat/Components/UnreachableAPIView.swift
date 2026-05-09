//
//  UnreachableAPIView.swift
//  Enchanted
//

import SwiftUI
import QuillUI

struct UnreachableAPIView: View {
    @State var showSettings = false

    var body: some View {
        QuillStatusBanner(
            message: "Quill is unreachable. Plug Quill back in if it's unplugged, or go to Settings and\nupdate your Quill API endpoint.",
            actionTitle: "Settings",
            showsActivity: true
        ) {
            showSettings.toggle()
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 74)
        .sheet(isPresented: $showSettings) {
            Settings()
        }
    }
}
