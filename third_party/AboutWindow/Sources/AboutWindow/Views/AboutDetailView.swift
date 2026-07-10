//
//  AboutDetailView.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 21/01/2023.
//

import SwiftUI

public struct AboutDetailView<Content: View>: View {

    @Environment(\.isAboutDetailPresented)
    private var isDetail

    @Environment(\.aboutWindowNavigation)
    private var aboutWindowNavigation

    @EnvironmentObject var namespaceWrapper: NamespaceWrapper

    var title: String

    @ViewBuilder var content: Content

    let smallTitlebarHeight: CGFloat = 28
    let mediumTitlebarHeight: CGFloat = 113
    let largeTitlebarHeight: CGFloat = 231

    var maxScrollOffset: CGFloat {
        smallTitlebarHeight - mediumTitlebarHeight
    }

    var currentOffset: CGFloat {
        getScrollAdjustedValue(
            minValue: 22,
            maxValue: 14,
            minOffset: 0,
            maxOffset: maxScrollOffset
        )
    }

    @State private var scrollOffset: CGFloat = 0

    public init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack {
            Spacer(minLength: smallTitlebarHeight + 1)
            TrackableScrollView(showIndicators: false, contentOffset: $scrollOffset) {
                Spacer(minLength: mediumTitlebarHeight - smallTitlebarHeight - 1 + 8)
                content
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .matchedGeometryEffect(
                id: AboutNamespaceID.scrollView,
                in: namespaceWrapper.namespace,
                properties: .position,
                anchor: .top
            )
            .blur(radius: isDetail ? 0 : 10)
            .opacity(isDetail ? 1 : 0)
            .clipShape(Rectangle())
        }

        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .matchedGeometryEffect(id: AboutNamespaceID.appIcon, in: namespaceWrapper.namespace)
                .frame(
                    width: getScrollAdjustedValue(
                        minValue: 48,
                        maxValue: 0,
                        minOffset: 0,
                        maxOffset: maxScrollOffset
                    ),
                    height: getScrollAdjustedValue(
                        minValue: 48,
                        maxValue: 0,
                        minOffset: 0,
                        maxOffset: maxScrollOffset
                    )
                )
                .opacity(
                    getScrollAdjustedValue(
                        minValue: 1,
                        maxValue: 0,
                        minOffset: 0,
                        maxOffset: maxScrollOffset
                    )
                )
                .padding(.top, getScrollAdjustedValue(
                    minValue: smallTitlebarHeight,
                    maxValue: 0,
                    minOffset: 0,
                    maxOffset: maxScrollOffset
                ))
                .padding(.bottom, getScrollAdjustedValue(
                    minValue: 5,
                    maxValue: 0,
                    minOffset: 0,
                    maxOffset: maxScrollOffset
                ))

            Button {
                aboutWindowNavigation?.pop()
            } label: {
                    Text(title)
                        .foregroundColor(.primary)
                        .font(.system(
                            size: getScrollAdjustedValue(
                                minValue: 20,
                                maxValue: 14,
                                minOffset: 0,
                                maxOffset: maxScrollOffset
                            ),
                            weight: .bold
                        ))

                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minHeight: smallTitlebarHeight)
                    .padding(.horizontal, 13)
                    .overlay(alignment: .leading) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.secondary)
                            .padding(.trailing)
                    }
                    .contentShape(Rectangle())
                    .matchedGeometryEffect(
                        id: AboutNamespaceID.title,
                        in: namespaceWrapper.namespace,
                        properties: .position,
                        anchor: .center
                    )
                    .blur(radius: isDetail ? 0 : 10)
                    .opacity(isDetail ? 1 : 0)
            }
            .buttonStyle(.plain)

            Divider()
                .opacity(getScrollAdjustedValue(
                    minValue: 0,
                    maxValue: 1,
                    minOffset: 0,
                    maxOffset: maxScrollOffset
                ))
        }
        .padding(0)
        .frame(maxWidth: .infinity)
        .matchedGeometryEffect(
            id: AboutNamespaceID.titleBar,
            in: namespaceWrapper.namespace,
            properties: .position,
            anchor: .bottom
        )
    }

    func getScrollAdjustedValue(
        minValue: CGFloat,
        maxValue: CGFloat,
        minOffset: CGFloat,
        maxOffset: CGFloat
    ) -> CGFloat {
        let currentOffset = scrollOffset
        let threshold: CGFloat = 1.0

        /// Prevents unnecessary view updates if the scroll offset is below the threshold
        if abs(currentOffset) < threshold {
            return minValue
        }

        let valueRange = maxValue - minValue
        let offsetRange = maxOffset - minOffset

        let percentage = (currentOffset - minOffset) / offsetRange
        let value = minValue + (valueRange * percentage)

        if currentOffset <= maxOffset {
            return maxValue
        }
        if value < 0 {
            return 0
        }
        return value
    }
}
