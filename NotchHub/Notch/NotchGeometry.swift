import AppKit

/// Size and position of the physical notch (or a fake one on screens without it).
struct NotchGeometry: Equatable {
    let screenFrame: NSRect
    let notchSize: CGSize

    static func detect(on screen: NSScreen) -> NotchGeometry {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return NotchGeometry(screenFrame: screen.frame,
                                 notchSize: CGSize(width: width, height: screen.safeAreaInsets.top))
        }
        // External displays have no notch: emulate one the height of the menu bar.
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(screenFrame: screen.frame,
                             notchSize: CGSize(width: 200, height: max(menuBarHeight, 24)))
    }

    /// The screen that has a notch, falling back to the main screen.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// Notch rect in screen coordinates, used to detect hover.
    var notchRect: NSRect {
        NSRect(x: screenFrame.midX - notchSize.width / 2,
               y: screenFrame.maxY - notchSize.height,
               width: notchSize.width,
               height: notchSize.height)
    }
}
