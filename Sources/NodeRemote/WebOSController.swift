import Foundation

/// LG webOS (SSAP) mapping of the shared TV operations.
extension WebOSConnection: TVController {
    nonisolated static func buttonName(_ key: RemoteKey) -> String? {
        switch key {
        case .up: return "UP"
        case .down: return "DOWN"
        case .left: return "LEFT"
        case .right: return "RIGHT"
        case .ok: return "ENTER"
        case .back: return "BACK"
        case .exit: return "EXIT"
        case .menu: return "MENU"
        case .home: return "HOME"
        case .channelUp: return "CHANNELUP"
        case .channelDown: return "CHANNELDOWN"
        case .source: return nil
        }
    }
    nonisolated static func volumeState(_ payload: [String: Any]) -> TVState {
        let p = payload["volumeStatus"] as? [String: Any] ?? payload
        var state = TVState()
        state.volume = (p["volume"] as? NSNumber)?.doubleValue
        state.muted = p["muteStatus"] as? Bool ?? p["mute"] as? Bool ?? p["muted"] as? Bool
        return state
    }
    nonisolated static func foregroundState(_ payload: [String: Any]) -> TVState {
        var state = TVState()
        state.foregroundID = payload["appId"] as? String ?? ""
        state.foregroundTitle = payload["title"] as? String
        return state
    }

    func details() async -> TVDetails {
        var details = TVDetails()
        if let system = try? await request("system/getSystemInfo") { details.model = system["modelName"] as? String }
        if let info = try? await request("com.webos.service.update/getCurrentSWInformation") {
            details.firmware = info["major_ver"] as? String ?? ""
            if let minor = info["minor_ver"] as? String { details.firmware += "." + minor }
            if let micro = info["micro_ver"] as? String { details.firmware += "." + micro }
            details.platform = info["product_name"] as? String ?? ""
        }
        return details
    }
    func listApps() async throws -> [TVApp] {
        let result = try await request("com.webos.applicationManager/listLaunchPoints")
        return (result["launchPoints"] as? [[String: Any]] ?? []).compactMap {
            guard let id = $0["id"] as? String, let title = $0["title"] as? String else { return nil }
            return TVApp(id: id, title: title, icon: nil)
        }
    }
    func listInputs() async -> [TVInput] {
        guard let result = try? await request("tv/getExternalInputList") else { return [] }
        return (result["devices"] as? [[String: Any]] ?? []).compactMap {
            guard let id = $0["id"] as? String else { return nil }
            var label = $0["label"] as? String ?? id
            if label.hasPrefix("HDMI"), let children = $0["subList"] as? [[String: Any]],
               let cecName = children.compactMap({ $0["osdName"] as? String }).first, !cecName.isEmpty {
                label = cecName
            }
            return TVInput(id: id, label: label, connected: $0["connected"] as? Bool ?? false, appID: $0["appId"] as? String ?? "")
        }
    }
    func readState() async -> TVState {
        var state = TVState()
        if let answer = try? await request("com.webos.service.tvpower/power/getPowerState") { state.powerActive = (answer["state"] as? String)?.lowercased() == "active" }
        else { state.powerActive = false }
        if let answer = try? await request("audio/getVolume") {
            let volume = Self.volumeState(answer); state.volume = volume.volume; state.muted = volume.muted
        }
        if let answer = try? await request("com.webos.applicationManager/getForegroundAppInfo") {
            let foreground = Self.foregroundState(answer); state.foregroundID = foreground.foregroundID; state.foregroundTitle = foreground.foregroundTitle
        }
        return state
    }
    func observeState(_ update: @escaping (TVState) -> Void) async {
        try? await subscribe("audio/getVolume") { update(Self.volumeState($0)) }
        try? await subscribe("com.webos.applicationManager/getForegroundAppInfo") { update(Self.foregroundState($0)) }
    }
    func foregroundAppID() async throws -> String {
        try await request("com.webos.applicationManager/getForegroundAppInfo")["appId"] as? String ?? ""
    }
    func press(_ key: RemoteKey) async throws {
        guard let name = Self.buttonName(key) else { throw RemoteError.message("Este botão não está disponível nesta TV.") }
        try await button(name)
    }
    func launch(_ appID: String) async throws { _ = try await request("system.launcher/launch", ["id": appID]) }
    func closeApp(_ appID: String) async throws { _ = try await request("system.launcher/close", ["id": appID]) }
    func setVolume(_ value: Int) async throws { _ = try await request("audio/setVolume", ["volume": value]) }
    func stepVolume(up: Bool) async throws { _ = try await request(up ? "audio/volumeUp" : "audio/volumeDown") }
    func toggleMute(current: Bool) async throws { _ = try await request("audio/setMute", ["mute": !current]) }
    func switchInput(_ id: String) async throws { _ = try await request("tv/switchInput", ["inputId": id]) }
    func media(_ command: MediaCommand) async throws { _ = try await request("media.controls/" + command.rawValue) }
    func insertText(_ text: String) async throws { _ = try await request("com.webos.service.ime/insertText", ["text": text, "replace": 0]) }
    func sendEnter() async throws { _ = try await request("com.webos.service.ime/sendEnterKey") }
    func turnOff() async throws { _ = try await request("system/turnOff") }
    func readPicture() async -> [String: Int] {
        guard let result = try? await request("settings/getSystemSettings", ["category": "picture", "keys": ["contrast", "backlight", "brightness", "color"]]),
              let settings = result["settings"] as? [String: Any] else { return [:] }
        return settings.compactMapValues { ($0 as? NSNumber)?.intValue ?? ($0 as? String).flatMap(Int.init) }
    }
    func openYouTube(videoID: String) async throws -> Bool {
        _ = try await request("system.launcher/launch", ["id": "youtube.leanback.v4", "contentId": videoID])
        return true
    }
    func setPictureMode(_ mode: String) async throws {
        _ = try await request("settings/setSystemSettings", ["category": "picture", "settings": ["pictureMode": mode]])
    }
    func writePicture(_ settings: [String: Int]) async throws {
        _ = try await request("settings/setSystemSettings", ["category": "picture", "settings": settings])
    }
}
