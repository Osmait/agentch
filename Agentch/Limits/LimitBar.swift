import SwiftUI

/// One limit: label, bar and percentage, with the reset date and time remaining underneath.
struct LimitBar: View {
    let window: UsageWindow
    let color: Color
    let now: Date
    let isOpen: Bool
    let delay: Double

    private static let warning = Color(hex: 0xFF9F0A)
    private static let warningThreshold = 80.0

    private var percent: Double { min(max(window.usedPercent, 0), 100) }
    private var isHot: Bool { percent >= Self.warningThreshold }
    private var barColor: Color { isHot ? Self.warning : color }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(window.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .leading)

                bar

                Text("\(Int(percent.rounded()))%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isHot ? Self.warning : .white)
                    .frame(width: 36, alignment: .trailing)
            }

            HStack {
                if let resetsAt = window.resetsAt {
                    Text("↻ \(LimitFormatting.resetDate(resetsAt))")
                        .foregroundStyle(.white.opacity(0.88))
                } else if window.detail == nil {
                    Text("Not used in this window")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let trailing = window.detail ?? window.resetsAt.map({ LimitFormatting.remaining(until: $0, from: now) }) {
                    Text(trailing)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 10))
            .lineLimit(1)
            .padding(.leading, 54)
        }
    }

    private var bar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [barColor.opacity(0.55), barColor],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * (isOpen ? percent / 100 : 0))
                    .shadow(color: barColor.opacity(0.45), radius: 5)
                    .animation(isOpen ? .spring(response: 0.9, dampingFraction: 0.85).delay(delay)
                                      : .easeIn(duration: 0.15),
                               value: isOpen)
                    .animation(.easeInOut(duration: 0.6), value: percent)
            }
        }
        .frame(height: 6)
    }
}
