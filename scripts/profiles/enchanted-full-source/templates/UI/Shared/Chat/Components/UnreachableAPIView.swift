//
//  UnreachableAPIView.swift
//  Enchanted
//

import SwiftUI
import QuillUI

struct UnreachableAPIView: View {
    var body: some View {
        QuillChatUnreachableBanner {
            Settings()
        }
    }
}
