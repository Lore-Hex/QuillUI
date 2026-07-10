//
//  NamespaceWrapper.swift
//  AboutWindow
//
//  Created by Khan Winter on 6/6/25.
//

import SwiftUI
import Combine

public final class NamespaceWrapper: ObservableObject {
    public let namespace: Namespace.ID

    init(namespace: Namespace.ID) {
        self.namespace = namespace
    }
}
