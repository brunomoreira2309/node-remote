import Foundation

enum SceneStep: Codable, Equatable, Hashable {
    /// The title travels with the ID so a scene made on one TV finds the same app on another brand.
    case openApp(id: String, title: String)
    case volume(Int)
    case sleepTimer(minutes: Int)
    case pictureMode(String)
    case powerOff
}

/// When a scene runs by itself. Weekdays use Calendar numbering: 1 is Sunday, 7 is Saturday.
struct SceneSchedule: Codable, Equatable {
    var hour: Int
    var minute: Int
    var weekdays: [Int]
    var tvHost: String
    var enabled = true
    static let dayLetters = ["D", "S", "T", "Q", "Q", "S", "S"]
    func isDue(at date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        return enabled && weekdays.contains(parts.weekday ?? 0) && parts.hour == hour && parts.minute == minute
    }
    var summary: String {
        let days = weekdays.sorted()
        let label = days == [2, 3, 4, 5, 6] ? "dias úteis" : days == [1, 7] ? "fim de semana" : days.count == 7 ? "todo dia" : days.map { SceneSchedule.dayLetters[$0 - 1] }.joined(separator: " ")
        return String(format: "%02d:%02d · %@", hour, minute, label)
    }
}

struct TVScene: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var symbol: String
    var steps: [SceneStep]
    var schedule: SceneSchedule?
}

enum SceneLibrary {
    static let symbols = ["film", "moon.zzz", "gamecontroller", "music.note", "sportscourt", "figure.child", "popcorn", "sparkles"]
    /// webOS picture mode identifiers with their names in the TV's own menus.
    static let pictureModes: [(id: String, label: String)] = [
        ("cinema", "Cinema"), ("filmMaker", "Filmmaker"), ("normal", "Padrão"), ("vivid", "Vívido"), ("game", "Jogo"), ("eco", "Econômico"),
    ]
    static let defaults = [
        TVScene(name: "Cinema", symbol: "film", steps: [.openApp(id: "netflix", title: "Netflix"), .volume(25), .pictureMode("cinema")]),
        TVScene(name: "Dormir", symbol: "moon.zzz", steps: [.volume(10), .sleepTimer(minutes: 30)]),
    ]
    static func load(_ store: UserDefaults = .standard) -> [TVScene] {
        guard let data = store.data(forKey: "tv.scenes"), let scenes = try? JSONDecoder().decode([TVScene].self, from: data) else { return defaults }
        return scenes
    }
    static func save(_ scenes: [TVScene], _ store: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(scenes) { store.set(data, forKey: "tv.scenes") }
    }
    /// The same app ID, or else an app whose name starts with the saved name ("Spotify - Music…").
    static func resolve(id: String, title: String, in apps: [TVApp]) -> TVApp? {
        if let exact = apps.first(where: { $0.id == id }) { return exact }
        let name = title.lowercased()
        guard !name.isEmpty else { return nil }
        return apps.first { $0.title.lowercased().hasPrefix(name) } ?? apps.first { name.hasPrefix($0.title.lowercased()) }
    }
    static func label(_ step: SceneStep) -> String {
        switch step {
        case .openApp(_, let title): return "Abrir \(title)"
        case .volume(let value): return "Volume \(value)"
        case .sleepTimer(let minutes): return "Desligar em \(SleepTimer.duration(minutes))"
        case .pictureMode(let mode): return "Imagem \(pictureModes.first { $0.id == mode }?.label ?? mode)"
        case .powerOff: return "Desligar a TV"
        }
    }
}
