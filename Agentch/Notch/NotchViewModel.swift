import Foundation
import Observation

@MainActor
@Observable
final class NotchViewModel {
    var isOpen = false
    var geometry: NotchGeometry
    /// Height of the expanded content, measured by the view.
    var contentHeight: CGFloat = 0

    static let expandedWidth: CGFloat = 540

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }
}
