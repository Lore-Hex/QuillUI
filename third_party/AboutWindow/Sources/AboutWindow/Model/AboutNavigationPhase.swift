//
//  AboutNavigationPhase.swift
//  AboutWindow
//
//  Created by Giorgi Tchelidze on 06.06.25.
//

import SwiftUI

private struct IsDetailPresentedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isAboutDetailPresented: Bool {
        get { self[IsDetailPresentedKey.self] }
        set { self[IsDetailPresentedKey.self] = newValue }
    }
}
