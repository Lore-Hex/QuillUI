//
//  UnreachableAPIView.swift
//  Enchanted
//

import SwiftUI
import QuillUI

struct UnreachableAPIView: View {
    var body: some View {
        QuillSheetStatusBanner(
            message: "Quill is unreachable. Plug Quill back in if it's unplugged, or go to Settings and\nupdate your Quill API endpoint.",
            actionTitle: "Settings",
            showsActivity: true,
            horizontalPadding: 28,
            topPadding: 10,
            bottomPadding: 74
        ) {
            Settings()
        }
    }
}
