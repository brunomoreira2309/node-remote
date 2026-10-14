import Foundation

/// Samsung Tizen (2016+) local remote protocol: a token-authorized WebSocket on
/// port 8002 for keys and text, plus the TV's REST API on port 8001 for device and app status.
enum SamsungProtocol {
    static var clientName: String { AppInfo.name }
    enum ChannelEvent: Equatable { case connected(token: String?), unauthorized, timedOut, other }
    struct DeviceInfo: Equatable { let name: String; let model: String; let mac: String?; let powerOn: Bool; let firmware: String }

    static func channelURL(host: String, token: String?) -> URL? {
        guard TVHost.local(host) else { return nil }
        var components = URLComponents()
        components.scheme = "wss"; components.host = host; components.port = 8002
        components.path = "/api/v2/channels/samsung.remote.control"
        var items = [URLQueryItem(name: "name", value: Data(clientName.utf8).base64EncodedString())]
        if let token, validToken(token) { items.append(URLQueryItem(name: "token", value: token)) }
        components.queryItems = items
        return components.url
    }
    static func restURL(host: String, _ path: String = "") -> URL? {
        guard TVHost.local(host) else { return nil }
        return URL(string: "http://\(host):8001/api/v2/\(path)")
    }
    static func validToken(_ token: String) -> Bool {
        (1...64).contains(token.count) && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
    /// App IDs are interpolated into a URL path, so only Tizen's own ID characters pass.
    static func validAppID(_ id: String) -> Bool {
        (1...64).contains(id.count) && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-") }
    }
    static func keyCode(_ key: RemoteKey) -> String {
        switch key {
        case .up: return "KEY_UP"
        case .down: return "KEY_DOWN"
        case .left: return "KEY_LEFT"
        case .right: return "KEY_RIGHT"
        case .ok: return "KEY_ENTER"
        case .back: return "KEY_RETURN"
        case .exit: return "KEY_EXIT"
        case .menu: return "KEY_MENU"
        case .home: return "KEY_HOME"
        case .channelUp: return "KEY_CHUP"
        case .channelDown: return "KEY_CHDOWN"
        case .source: return "KEY_SOURCE"
        }
    }
    static func keyCode(_ command: MediaCommand) -> String {
        switch command {
        case .play: return "KEY_PLAY"
        case .pause: return "KEY_PAUSE"
        case .stop: return "KEY_STOP"
        case .rewind: return "KEY_REWIND"
        case .fastForward: return "KEY_FF"
        }
    }
    private static func remoteControl(_ params: [String: String]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: ["method": "ms.remote.control", "params": params], options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
    static func keyMessage(_ code: String) -> String {
        remoteControl(["Cmd": "Click", "DataOfCmd": code, "Option": "false", "TypeOfRemote": "SendRemoteKey"])
    }
    static func textMessage(_ text: String) -> String {
        remoteControl(["Cmd": Data(text.utf8).base64EncodedString(), "DataOfCmd": "base64", "TypeOfRemote": "SendInputString"])
    }
    static let textEndMessage = remoteControl(["TypeOfRemote": "SendInputEnd"])

    static func parse(_ data: Data) -> ChannelEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let event = object["event"] as? String else { return nil }
        switch event {
        case "ms.channel.connect":
            let token = (object["data"] as? [String: Any])?["token"].flatMap { $0 as? String ?? ($0 as? NSNumber)?.stringValue }
            return .connected(token: token.flatMap { validToken($0) ? $0 : nil })
        case "ms.channel.unauthorized": return .unauthorized
        case "ms.channel.timeOut": return .timedOut
        default: return .other
        }
    }
    static func deviceInfo(_ data: Data) -> DeviceInfo? {
        guard data.count <= 65_536, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let device = object["device"] as? [String: Any], device["type"] as? String == "Samsung SmartTV" else { return nil }
        var name = device["name"] as? String ?? object["name"] as? String ?? "Samsung TV"
        if name.hasPrefix("[TV] ") { name = String(name.dropFirst(5)) }
        let mac = (device["wifiMac"] as? String)?.lowercased()
        let validMAC = mac.flatMap { value -> String? in
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            return parts.count == 6 && parts.allSatisfy({ $0.count == 2 && UInt8($0, radix: 16) != nil }) ? value : nil
        }
        let firmware = device["firmwareVersion"] as? String ?? ""
        return DeviceInfo(name: name, model: device["modelName"] as? String ?? "", mac: validMAC,
                          powerOn: (device["PowerState"] as? String ?? "on").lowercased() == "on",
                          firmware: firmware == "Unknown" ? "" : firmware)
    }
    struct AppStatus { let id: String; let name: String; let visible: Bool }
    static func appStatus(_ data: Data) -> AppStatus? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let id = object["id"] as? String else { return nil }
        return AppStatus(id: id, name: object["name"] as? String ?? id, visible: object["visible"] as? Bool ?? false)
    }
}

/// Never follows a redirect away from the TV's local REST API.
private final class SamsungHTTPDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor final class SamsungConnection: TVController {
    let host: String
    private let session: URLSession
    private let http: URLSession
    private let trust: TVCertificateTrust
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var installed: [TVApp] = []
    private var renderingControl: URL?
    var onPairing: (() -> Void)?
    var onDisconnect: ((Error) -> Void)?
    var onEvent: ((String, String) -> Void)?
    var onPointerState: ((Bool) -> Void)?
    var onCertificateTrust: (@MainActor (String, String) async -> Bool)?
    init(host: String) {
        self.host = host
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        trust = TVCertificateTrust(host: host, port: 8002)
        session = URLSession(configuration: configuration, delegate: trust, delegateQueue: nil)
        let rest = URLSessionConfiguration.ephemeral
        rest.timeoutIntervalForRequest = 4
        http = URLSession(configuration: rest, delegate: SamsungHTTPDelegate(), delegateQueue: nil)
    }

    func connect(allowFirstUseTrust: Bool) async throws {
        guard TVHost.local(host) else { throw RemoteError.message("Digite o IPv4 local da TV.") }
        let pairingHost = host
        let saved = await Task.detached(priority: .userInitiated) {
            (PairingKey.read(pairingHost), TVCertificatePin.read(pairingHost))
        }.value
        let storedToken = saved.0.flatMap { SamsungProtocol.validToken($0) ? $0 : nil }, storedPin = saved.1
        let confirmation = onCertificateTrust
        guard storedPin != nil || (allowFirstUseTrust && confirmation != nil) else {
            throw RemoteError.message("Esta TV ainda não tem um certificado confiável. Clique em Conectar para confirmar o primeiro pareamento.")
        }
        let approval: (@Sendable (String, String) async -> Bool)?
        if allowFirstUseTrust {
            approval = { host, fingerprint in await confirmation?(host, fingerprint) ?? false }
        } else { approval = nil }
        trust.configure(fingerprint: storedPin, approval: approval)
        guard let url = SamsungProtocol.channelURL(host: host, token: storedToken) else { throw RemoteError.message("Digite o IPv4 local da TV.") }
        try Task.checkCancellation()
        let ws = session.webSocketTask(with: url); socket = ws
        try await trust.open(ws)
        // Without a saved token the TV shows its Allow/Deny prompt now.
        if storedToken == nil { onPairing?() }
        let event = try await channelEvent(ws)
        try Task.checkCancellation()
        guard case let .connected(token) = event else {
            throw RemoteError.message(event == .timedOut
                ? "O pedido expirou na TV. Clique em Conectar e escolha Permitir na tela da TV."
                : "A TV recusou o acesso. Permita o \(AppInfo.name) em Configurações → Geral → Gerenciador de Dispositivos Externos → Gerenciador de Conexão de Dispositivos.")
        }
        guard storedToken != nil || token != nil else { throw RemoteError.message("A TV não forneceu uma chave de pareamento.") }
        if let token, token != storedToken {
            try await Task.detached(priority: .userInitiated) { try PairingKey.save(token, host: pairingHost) }.value
        }
        // First-use trust is durable only after the TV has authorized the client.
        if storedPin == nil, let fingerprint = trust.approvedFingerprint() {
            try await Task.detached(priority: .userInitiated) { try TVCertificatePin.save(fingerprint, host: pairingHost) }.value
        }
        receiver = Task { [weak self] in
            do { while !Task.isCancelled { _ = try await ws.receive() } }
            catch { if !Task.isCancelled { self?.onDisconnect?(error) } }
        }
    }
    private func channelEvent(_ ws: URLSessionWebSocketTask) async throws -> SamsungProtocol.ChannelEvent {
        try await withThrowingTaskGroup(of: SamsungProtocol.ChannelEvent.self) { group in
            group.addTask {
                while true {
                    let data: Data
                    switch try await ws.receive() { case .string(let s): data = Data(s.utf8); case .data(let d): data = d; @unknown default: continue }
                    if let event = SamsungProtocol.parse(data), event != .other { return event }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 60_000_000_000)
                ws.cancel(with: .goingAway, reason: nil)
                throw RemoteError.message("O pareamento expirou. Aceite a conexão na TV e tente de novo.")
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
    }
    func close() {
        receiver?.cancel(); receiver = nil; socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session.invalidateAndCancel(); http.invalidateAndCancel()
    }
    private func send(_ message: String, log detail: String) async throws {
        guard let ws = socket else { throw RemoteError.message("Conecte-se à TV primeiro.") }
        onEvent?("Comando", detail)
        try await ws.send(.string(message))
    }
    private func sendKey(_ code: String) async throws { try await send(SamsungProtocol.keyMessage(code), log: code) }

    private func rest(_ path: String, method: String = "GET") async throws -> (Data, Int) {
        guard let url = SamsungProtocol.restURL(host: host, path) else { throw RemoteError.message("Endereço IP inválido.") }
        var request = URLRequest(url: url); request.httpMethod = method
        let (data, response) = try await http.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
    private func renderingControlURL() async throws -> URL {
        if let renderingControl { return renderingControl }
        let url = try await DLNATransport.discover(host: host, renderer: TVBrand.samsung.mediaRenderer, service: "RenderingControl")
        renderingControl = url
        return url
    }
    private func renderingCommand(_ action: String, _ parameters: [(String, String)] = []) async throws -> String {
        try await DLNATransport.command(try await renderingControlURL(), action: action, parameters: [("Channel", "Master")] + parameters, urn: DLNATransport.renderingURN)
    }

    func details() async -> TVDetails {
        guard let (data, status) = try? await rest(""), status == 200, let info = SamsungProtocol.deviceInfo(data) else { return TVDetails(platform: "Tizen") }
        return TVDetails(model: info.model.isEmpty ? nil : info.model, firmware: info.firmware, platform: "Tizen")
    }
    /// The TV does not list installed apps; each known ID is checked and the TV reports its real name.
    func listApps() async throws -> [TVApp] {
        guard let url = AppResources.bundle.url(forResource: "samsung-apps", withExtension: "json") else { return [] }
        let candidates = try JSONDecoder().decode([TVApp].self, from: Data(contentsOf: url)).filter { SamsungProtocol.validAppID($0.id) }
        var found: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            for app in candidates {
                group.addTask { @MainActor in
                    guard let (data, status) = try? await self.rest("applications/\(app.id)"), status == 200 else { return (app.id, nil) }
                    return (app.id, SamsungProtocol.appStatus(data)?.name ?? app.title)
                }
            }
            for await (id, name) in group { if let name { found[id] = name } }
        }
        installed = candidates.compactMap { app in found[app.id].map { TVApp(id: app.id, title: $0, icon: nil) } }
        return installed
    }
    func listInputs() async -> [TVInput] { [] }
    func readState() async -> TVState {
        var state = TVState()
        if let (data, status) = try? await rest(""), status == 200, let info = SamsungProtocol.deviceInfo(data) { state.powerActive = info.powerOn }
        else { state.powerActive = false }
        if let text = try? await renderingCommand("GetVolume"), let volume = DLNATransport.value("CurrentVolume", in: text).flatMap(Double.init) { state.volume = volume }
        if let text = try? await renderingCommand("GetMute"), let mute = DLNATransport.value("CurrentMute", in: text) { state.muted = mute == "1" || mute.lowercased() == "true" }
        if !installed.isEmpty {
            var visible: SamsungProtocol.AppStatus?
            await withTaskGroup(of: SamsungProtocol.AppStatus?.self) { group in
                for app in installed {
                    group.addTask { @MainActor in
                        guard let (data, status) = try? await self.rest("applications/\(app.id)"), status == 200 else { return nil }
                        return SamsungProtocol.appStatus(data)
                    }
                }
                for await status in group where status?.visible == true { visible = status }
            }
            state.foregroundID = visible?.id ?? ""
            state.foregroundTitle = visible?.name
        }
        return state
    }
    func observeState(_ update: @escaping (TVState) -> Void) async {}
    func foregroundAppID() async throws -> String { await readState().foregroundID ?? "" }
    func press(_ key: RemoteKey) async throws { try await sendKey(SamsungProtocol.keyCode(key)) }
    func move(dx: Int, dy: Int) async throws { throw RemoteError.message("O cursor não está disponível nesta TV.") }
    func click() async throws { try await press(.ok) }
    func checkPointer() async throws {
        guard socket != nil else { throw RemoteError.message("Conecte-se à TV primeiro.") }
        onPointerState?(true)
    }
    func launch(_ appID: String) async throws {
        guard SamsungProtocol.validAppID(appID) else { throw RemoteError.message("Este app não pode ser aberto nesta TV.") }
        onEvent?("Comando", "Abrir " + appID)
        let (_, status) = try await rest("applications/\(appID)", method: "POST")
        guard (200...299).contains(status) else { throw RemoteError.message("A TV não abriu o app (\(status)).") }
    }
    func closeApp(_ appID: String) async throws { throw RemoteError.message("Esta TV não fecha apps pelo Mac.") }
    func setVolume(_ value: Int) async throws {
        _ = try await renderingCommand("SetVolume", [("DesiredVolume", String(min(100, max(0, value))))])
    }
    func stepVolume(up: Bool) async throws { try await sendKey(up ? "KEY_VOLUP" : "KEY_VOLDOWN") }
    func toggleMute(current: Bool) async throws { try await sendKey("KEY_MUTE") }
    func switchInput(_ id: String) async throws { throw RemoteError.message("Use o botão Fonte para trocar a entrada desta TV.") }
    func media(_ command: MediaCommand) async throws { try await sendKey(SamsungProtocol.keyCode(command)) }
    // Record that text was sent, never the text itself.
    func insertText(_ text: String) async throws {
        try await send(SamsungProtocol.textMessage(text), log: "SendInputString")
        try await send(SamsungProtocol.textEndMessage, log: "SendInputEnd")
    }
    func sendEnter() async throws { try await sendKey("KEY_ENTER") }
    func turnOff() async throws { try await sendKey("KEY_POWER") }
    func readPicture() async -> [String: Int] { [:] }
    func writePicture(_ settings: [String: Int]) async throws { throw RemoteError.message("Os ajustes de imagem não estão disponíveis nesta TV.") }
    func setPictureMode(_ mode: String) async throws { throw RemoteError.message("O modo de imagem não está disponível nesta TV.") }
    /// Tested on a 2020 Tizen TV: DIAL launches are refused (403) and deep-link metadata is ignored,
    /// so only the YouTube app itself can be opened over the local network.
    func openYouTube(videoID: String) async throws -> Bool {
        try await launch("111299001912")
        return false
    }

    /// Finds Samsung TVs by asking each address of the Mac's local /24 networks for its device description.
    nonisolated static func discover() async -> [TVDevice] {
        let hosts = LocalNetwork.neighbors()
        guard !hosts.isEmpty else { return [] }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.5
        let probe = URLSession(configuration: configuration, delegate: SamsungHTTPDelegate(), delegateQueue: nil)
        defer { probe.invalidateAndCancel() }
        return await withTaskGroup(of: TVDevice?.self) { group in
            for host in hosts {
                group.addTask {
                    guard let url = SamsungProtocol.restURL(host: host), let (data, response) = try? await probe.data(from: url),
                          (response as? HTTPURLResponse)?.statusCode == 200, let info = SamsungProtocol.deviceInfo(data) else { return nil }
                    return TVDevice(host: host, name: info.name, model: info.model, mac: info.mac, brand: .samsung)
                }
            }
            var devices: [TVDevice] = []
            for await device in group { if let device { devices.append(device) } }
            return devices
        }
    }
}
