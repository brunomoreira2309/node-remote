import Foundation

enum TVBrand: String, CaseIterable, Identifiable, Codable {
    case lg, samsung
    var id: String { rawValue }
    var displayName: String { self == .lg ? "LG" : "Samsung" }
    var platform: String { self == .lg ? "LG · webOS" : "Samsung · Tizen" }
    var defaultName: String { self == .lg ? "LG TV" : "Samsung TV" }
    var pairingHint: String { self == .lg ? "Aceite o “LG Remote App” na TV." : "Na TV, escolha Permitir para o “\(AppInfo.name)”." }
    var capabilities: TVCapabilities {
        switch self {
        case .lg: return [.volumeLevel, .inputList, .pointer, .picture, .closeApps, .videoLinks]
        case .samsung: return [.volumeLevel, .sourceKey]
        }
    }
    /// UPnP description of the TV's own media renderer (port, path).
    var mediaRenderer: (port: Int, path: String) { self == .lg ? (1719, "/") : (9197, "/dmr") }
}

struct TVCapabilities: OptionSet {
    let rawValue: Int
    static let volumeLevel = TVCapabilities(rawValue: 1 << 0)
    static let inputList = TVCapabilities(rawValue: 1 << 1)
    static let pointer = TVCapabilities(rawValue: 1 << 2)
    static let picture = TVCapabilities(rawValue: 1 << 3)
    static let closeApps = TVCapabilities(rawValue: 1 << 4)
    static let sourceKey = TVCapabilities(rawValue: 1 << 5)
    /// Opens a specific YouTube video instead of only the YouTube app.
    static let videoLinks = TVCapabilities(rawValue: 1 << 6)
}

enum RemoteKey: String, CaseIterable {
    case up, down, left, right, ok, back, exit, menu, home, channelUp, channelDown, source
}

enum MediaCommand: String, CaseIterable {
    case play, pause, stop, rewind, fastForward
}

/// Partial readings: nil means the TV did not report that value.
struct TVState {
    var powerActive: Bool?
    var volume: Double?
    var muted: Bool?
    var foregroundID: String?
    var foregroundTitle: String?
}

struct TVDetails {
    var model: String?
    var firmware = ""
    var platform = ""
}

/// One TV connection. Each brand maps these operations to its own local protocol.
@MainActor protocol TVController: AnyObject {
    var host: String { get }
    var onPairing: (() -> Void)? { get set }
    var onDisconnect: ((Error) -> Void)? { get set }
    var onEvent: ((String, String) -> Void)? { get set }
    var onPointerState: ((Bool) -> Void)? { get set }
    var onCertificateTrust: (@MainActor (String, String) async -> Bool)? { get set }
    func connect(allowFirstUseTrust: Bool) async throws
    func close()
    func details() async -> TVDetails
    func listApps() async throws -> [TVApp]
    func listInputs() async -> [TVInput]
    func readState() async -> TVState
    func observeState(_ update: @escaping (TVState) -> Void) async
    func foregroundAppID() async throws -> String
    func press(_ key: RemoteKey) async throws
    func move(dx: Int, dy: Int) async throws
    func click() async throws
    func checkPointer() async throws
    func launch(_ appID: String) async throws
    func closeApp(_ appID: String) async throws
    func setVolume(_ value: Int) async throws
    func stepVolume(up: Bool) async throws
    func toggleMute(current: Bool) async throws
    func switchInput(_ id: String) async throws
    func media(_ command: MediaCommand) async throws
    func insertText(_ text: String) async throws
    func sendEnter() async throws
    func turnOff() async throws
    func readPicture() async -> [String: Int]
    func writePicture(_ settings: [String: Int]) async throws
    func setPictureMode(_ mode: String) async throws
    /// Returns false when the TV could only open the YouTube app, not the video itself.
    func openYouTube(videoID: String) async throws -> Bool
}

enum TVHost {
    nonisolated static func valid(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) && Int($0).map { (0...255).contains($0) } == true }
    }
    nonisolated static func local(_ host: String) -> Bool {
        guard valid(host) else { return false }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        return octets[0] == 10 || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 169 && octets[1] == 254)
    }
}
