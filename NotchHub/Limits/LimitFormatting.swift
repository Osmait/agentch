import Foundation

enum LimitFormatting {
    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// "Fri Oct 23 13:00"
    static func resetDate(_ date: Date) -> String {
        // APIs report resets like 22:59:59.9; show them as 23:00.
        let rounded = Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded() * 60)
        let text = resetFormatter.string(from: rounded).replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "2h 18m", "47m", "5d"
    static func remaining(until date: Date, from now: Date) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        let minutes = Int(seconds / 60)
        if minutes >= 24 * 60 { return "\(minutes / (24 * 60))d" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(max(minutes, 1))m"
    }

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}
