//
//  SidebarButton.swift
//  Enchanted
//

import SwiftUI
import QuillUI

struct SidebarButton: View {
    var title: String
    var image: String
    var onClick: () -> ()

    var body: some View {
        QuillSidebarNavigationButton(title: title, systemImage: image, action: onClick)
    }
}
