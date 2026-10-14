import Foundation

/// Only the current Mac's preferences supply device details; no TV ships preconfigured.
struct TVConfiguration: Equatable {
    let brand: TVBrand
    let host: String
    let name: String
    let model: String
    let mac: String
    init(defaults: UserDefaults = .standard) {
        brand = defaults.string(forKey: "tv.brand").flatMap(TVBrand.init(rawValue:)) ?? .lg
        host = defaults.string(forKey: "tv.host") ?? ""
        name = defaults.string(forKey: "tv.name") ?? brand.defaultName
        model = defaults.string(forKey: "tv.model") ?? ""
        mac = defaults.string(forKey: "tv.mac") ?? ""
    }
}

/// A TV this Mac has connected to. Pairing secrets stay in the Keychain, keyed by host.
struct SavedTV: Codable, Identifiable, Equatable {
    var id: String { host }
    var brand: TVBrand
    var host: String
    var name: String
    var model: String
    var mac: String
}

enum TVLibrary {
    static func load(_ defaults: UserDefaults = .standard) -> [SavedTV] {
        if let data = defaults.data(forKey: "tv.saved"), let list = try? JSONDecoder().decode([SavedTV].self, from: data) {
            return list.filter { TVHost.local($0.host) }
        }
        // Before multiple TVs, the single configured TV lived in the tv.* keys.
        let legacy = TVConfiguration(defaults: defaults)
        guard TVHost.local(legacy.host) else { return [] }
        return [SavedTV(brand: legacy.brand, host: legacy.host, name: legacy.name, model: legacy.model, mac: legacy.mac)]
    }
    static func save(_ list: [SavedTV], _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: "tv.saved") }
    }
    /// One entry per address: reconnecting updates it in place and keeps the list order.
    static func upsert(_ tv: SavedTV, into list: [SavedTV]) -> [SavedTV] {
        guard TVHost.local(tv.host) else { return list }
        var result = list
        if let index = result.firstIndex(where: { $0.host == tv.host }) { result[index] = tv } else { result.append(tv) }
        return result
    }
}
