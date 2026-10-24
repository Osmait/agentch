import AppKit
import SwiftUI

/// Owns the notch panel and opens/closes it as the pointer enters or leaves.
@MainActor
final class NotchWindowController {
    private let store: UsageStore
    private let model: NotchViewModel
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var closeWork: DispatchWorkItem?

    /// Extra room around the expanded panel so the shadow is not clipped.
    private let shadowMargin: CGFloat = 40
    private let panelHeight: CGFloat = 520

    init(store: UsageStore) {
        self.store = store
        let screen = NotchGeometry.preferredScreen() ?? NSScreen.screens[0]
        model = NotchViewModel(geometry: .detect(on: screen))
        panel = NotchPanel(contentRect: .zero)

        let root = NotchView(model: model, store: store)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        layoutPanel()
    }

    /// Debug aid: launch with `--args -pinOpen YES` to keep the panel open.
    private let pinOpen = UserDefaults.standard.bool(forKey: "pinOpen")

    func start() {
        panel.orderFrontRegardless()
        if pinOpen {
            open()
            return
        }

        let onMove: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: onMove) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
            onMove(event)
            return event
        }) {
            monitors.append(local)
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenChanged() }
        }
    }

    // MARK: - Layout

    private func layoutPanel() {
        let frame = model.geometry.screenFrame
        let width = NotchViewModel.expandedWidth + shadowMargin * 2
        panel.setFrame(NSRect(x: frame.midX - width / 2,
                              y: frame.maxY - panelHeight,
                              width: width,
                              height: panelHeight),
                       display: true)
    }

    private func screenChanged() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        model.geometry = .detect(on: screen)
        layoutPanel()
    }

    // MARK: - Hover

    private var expandedRect: NSRect {
        let g = model.geometry
        let height = max(model.contentHeight, g.notchSize.height)
        return NSRect(x: g.screenFrame.midX - NotchViewModel.expandedWidth / 2,
                      y: g.screenFrame.maxY - height,
                      width: NotchViewModel.expandedWidth,
                      height: height)
    }

    private func pointerMoved() {
        let point = NSEvent.mouseLocation
        if model.isOpen {
            if expandedRect.insetBy(dx: -6, dy: -6).contains(point) {
                cancelClose()
            } else {
                scheduleClose()
            }
        } else if model.geometry.notchRect.insetBy(dx: -10, dy: 0).contains(point) {
            open()
        }
    }

    private func open() {
        cancelClose()
        panel.ignoresMouseEvents = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.74)) {
            model.isOpen = true
        }
        store.refreshIfStale()
    }

    private func scheduleClose() {
        guard closeWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.close() }
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func cancelClose() {
        closeWork?.cancel()
        closeWork = nil
    }

    private func close() {
        closeWork = nil
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            model.isOpen = false
        }
        panel.ignoresMouseEvents = true
    }
}
