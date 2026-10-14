import Foundation

enum SleepTimer {
    static let presets = [15, 30, 45, 60, 90, 120]
    /// "30 min", "1 h", "1 h 30 min"
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(minutes) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
    /// Countdown for the panel: "27:41", "1:05:00".
    static func clock(_ remaining: TimeInterval) -> String {
        let seconds = max(0, Int(remaining.rounded(.up)))
        let h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
    /// Compact label beside the menu bar icon: whole minutes left, rounded up.
    static func menuBar(_ remaining: TimeInterval) -> String {
        remaining < 60 ? "<1m" : "\(Int((remaining / 60).rounded(.up)))m"
    }
}
