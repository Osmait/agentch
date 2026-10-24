import SwiftUI

struct NotchView: View {
    @Bindable var model: NotchViewModel
    let store: UsageStore

    /// Opacity of the black tint over the blur when expanded.
    private let panelOpacity: Double = 0.74

    var body: some View {
        let open = model.isOpen
        let notch = model.geometry.notchSize
        let shape = NotchShape(bottomRadius: open ? 28 : 12)

        ZStack(alignment: .top) {
            LimitsView(store: store, isOpen: open, topInset: notch.height)
                .frame(width: NotchViewModel.expandedWidth)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
                .opacity(open ? 1 : 0)
                .blur(radius: open ? 0 : 10)
                .scaleEffect(open ? 1 : 0.96, anchor: .top)
                .animation(open ? .easeOut(duration: 0.35).delay(0.1) : .easeIn(duration: 0.14), value: open)
        }
        .frame(width: open ? NotchViewModel.expandedWidth : notch.width,
               height: open ? max(model.contentHeight, notch.height) : notch.height,
               alignment: .top)
        .background {
            ZStack {
                VisualEffectView()
                Color.black.opacity(open ? panelOpacity : 1)
            }
        }
        .clipShape(shape)
        .overlay(alignment: .top) {
            // The physical notch stays solid black over the translucent panel.
            NotchShape(bottomRadius: 12)
                .fill(.black)
                .frame(width: notch.width, height: notch.height)
        }
        .shadow(color: .black.opacity(open ? 0.45 : 0), radius: 24, y: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onPreferenceChange(ContentHeightKey.self) { model.contentHeight = $0 }
        .contextMenu {
            Button("Refresh Now") { store.refresh() }
            Divider()
            Button("Quit Notch Hub") { NSApp.terminate(nil) }
        }
        .environment(\.colorScheme, .dark)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
