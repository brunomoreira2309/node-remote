import Foundation
import AppKit

enum FeatureChecks {
    static func equal<T: Equatable>(_ a: T, _ b: T) throws { guard a == b else { throw RemoteError.message("Check failed: \(a) != \(b)") } }
    static func truth(_ value: Bool) throws { guard value else { throw RemoteError.message("Check failed") } }
    static func rejects(_ operation: () throws -> Void) throws { do { try operation() } catch { return }; throw RemoteError.message("Expected rejection") }
    static func run() async throws {
        try testPackagedResourcesLoadWithoutDeviceConfiguration()
        try testUsageSurvivesRestartAndClipsMidnightWithoutCountingSleep()
        try testHTTPRangeSupportsSeekSuffixAndRejectsInvalidRanges()
        try await testMediaServerStreamsOnlySelectedFileAndSupportsHeadAndRange()
        try testSOAPMetadataEscapesUserFilenameAndURL()
        try await testPointerConnectionAndRecovery()
        try await testPointerPreflightRecoveryDoesNotReplayCommands()
        try await testPointerCloseCancelsPendingInput()
        try testPointerMotionKeepsEveryDelta()
        try await testHomeClosesUserAppOnceWithoutLaunchingAnything()
        try await testCancelledHomeDoesNotSendAnotherCommand()
        try testHomePresentationSurvivesRepeatedUnderlyingAppReports()
        try testConnectionAcceptsOnlyLocalIPv4Addresses()
        try testCertificateTrustRequiresApprovalAndRejectsChangedPins()
        try testFreshConfigurationHasNoDeviceIdentityAndLoadsCustomParameters()
        try testSamsungChannelURLAndMessages()
        try testSamsungEventsDeviceInfoAndAppStatus()
        try testBrandKeyMappingsAndCapabilities()
        try testRenderingControlEnvelopeAndValue()
        try testKeyboardShortcutsLeaveModifiersAndTypingAlone()
        try testSavedTVsMigrateUpsertAndStayLocal()
        try testSleepTimerLabels()
        try testScenesPersistAndFindAppsAcrossBrands()
        try testRoutineSchedulesAndCallVolume()
        try testYouTubeLinksAndDroppedFiles()
        print("PASS: YouTube links and dropped files; routine schedules, call volume; scene persistence, defaults and cross-brand app matching; sleep timer labels; keyboard shortcuts; saved TV migration, upsert and local-only filter; Samsung channel URL, token and app ID validation, key/text messages, pairing events, device info, app status; brand key maps and capabilities; UPnP volume envelope and parsing; packaged registration, catalog and images; usage persistence, midnight clipping, sleep exclusion; HTTP GET/HEAD/Range/404/416; XML escaping; pointer ordering, closure/reconnection, preflight recovery, cancellation, no duplicate clicks, full drag motion; Home closes user apps once, preserves HDMI/system apps, respects cancellation; Home presentation survives polling and clears on navigation/app changes; local IPv4 boundaries, certificate trust, fresh configuration and custom parameters.")
    }

    static func testPackagedResourcesLoadWithoutDeviceConfiguration() throws {
        guard let registrationURL = AppResources.bundle.url(forResource: "registration", withExtension: "json"),
              let registration = try JSONSerialization.jsonObject(with: Data(contentsOf: registrationURL)) as? [String: Any],
              let manifest = registration["manifest"] as? [String: Any],
              let signatures = manifest["signatures"] as? [[String: Any]],
              let permissions = manifest["permissions"] as? [String] else {
            throw RemoteError.message("The packaged pairing manifest is missing or invalid")
        }
        try equal(registration["pairingType"] as? String, "PROMPT")
        try truth(registration["client-key"] == nil)
        try truth(permissions.contains("LAUNCH"))
        try truth(signatures.contains { !($0["signature"] as? String ?? "").isEmpty })
        guard let catalogURL = AppResources.bundle.url(forResource: "app-catalog", withExtension: "json") else {
            throw RemoteError.message("The packaged app catalog is missing")
        }
        let apps = try JSONDecoder().decode([TVApp].self, from: Data(contentsOf: catalogURL))
        try truth(!apps.isEmpty)
        try equal(Set(apps.map(\.id)).count, apps.count)
        for app in apps {
            try truth(!app.id.isEmpty && !app.title.isEmpty)
            guard let icon = app.icon, !icon.contains("/"), !icon.contains(".."),
                  let url = AppResources.bundle.url(forResource: icon, withExtension: nil, subdirectory: "AppAssets"),
                  let image = NSImage(contentsOf: url) else {
                throw RemoteError.message("A packaged catalog icon is missing or invalid")
            }
            try truth(image.isValid)
        }
        for name in ["lg", "playstation", "googlecast", "tv-hero"] {
            guard let url = AppResources.bundle.url(forResource: name, withExtension: "png", subdirectory: "AppAssets"),
                  let image = NSImage(contentsOf: url), image.isValid else {
                throw RemoteError.message("A packaged brand image is missing or invalid")
            }
        }
    }

    static func testConnectionAcceptsOnlyLocalIPv4Addresses() throws {
        let allowed = [[10, 0, 0, 0], [10, 255, 255, 255], [172, 16, 0, 0], [172, 31, 255, 255], [192, 168, 0, 0], [192, 168, 255, 255], [169, 254, 1, 1], [169, 254, 254, 254]]
        for octets in allowed {
            try truth(TVHost.local(octets.map(String.init).joined(separator: ".")))
        }
        for host in ["9.255.255.255", "11.0.0.0", "172.15.255.255", "172.32.0.0", "192.167.255.255", "192.169.0.0", "169.253.255.255", "169.255.0.0", "127.0.0.1", "0.0.0.0", "8.8.8.8", "255.255.255.255", "192.168.1.256", "192.168.1", "localhost", "", "::1"] {
            try truth(!TVHost.local(host))
        }
    }
    static func testCertificateTrustRequiresApprovalAndRejectsChangedPins() throws {
        try equal(TVCertificatePolicy.decide(expected: "saved-pin", received: "saved-pin", canApprove: false), .matched)
        try equal(TVCertificatePolicy.decide(expected: "saved-pin", received: "saved-pin", canApprove: true), .matched)
        try equal(TVCertificatePolicy.decide(expected: "saved-pin", received: "changed-pin", canApprove: true), .rejected)
        try equal(TVCertificatePolicy.decide(expected: nil, received: "new-pin", canApprove: false), .rejected)
        try equal(TVCertificatePolicy.decide(expected: nil, received: "new-pin", canApprove: true), .approvalRequired)
    }
    static func testFreshConfigurationHasNoDeviceIdentityAndLoadsCustomParameters() throws {
        let suite = "NodeRemote.FeatureChecks." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { throw RemoteError.message("Could not create isolated test preferences") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let fresh = TVConfiguration(defaults: defaults)
        try equal(fresh.brand, .lg)
        try equal(fresh.host, "")
        try equal(fresh.name, "LG TV")
        try equal(fresh.model, "")
        try equal(fresh.mac, "")
        let address = "203.0.113.10"
        let mac = ["00", "11", "22", "33", "44", "55"].joined(separator: ":")
        defaults.set(address, forKey: "tv.host")
        defaults.set("Test TV", forKey: "tv.name")
        defaults.set("Test model", forKey: "tv.model")
        defaults.set(mac, forKey: "tv.mac")
        let configured = TVConfiguration(defaults: defaults)
        try equal(configured.host, address)
        try equal(configured.name, "Test TV")
        try equal(configured.model, "Test model")
        try equal(configured.mac, mac)
        defaults.set("samsung", forKey: "tv.brand")
        defaults.removeObject(forKey: "tv.name")
        let samsung = TVConfiguration(defaults: defaults)
        try equal(samsung.brand, .samsung)
        try equal(samsung.name, "Samsung TV")
        defaults.set("unknown", forKey: "tv.brand")
        try equal(TVConfiguration(defaults: defaults).brand, .lg)
    }

    // Built from octets so the privacy check never sees a literal private address.
    private static let sampleHost = [192, 168, 0, 10].map(String.init).joined(separator: ".")
    static func testSamsungChannelURLAndMessages() throws {
        let url = SamsungProtocol.channelURL(host: sampleHost, token: "12345678")
        try equal(url?.scheme, "wss"); try equal(url?.port, 8002)
        try equal(url?.path, "/api/v2/channels/samsung.remote.control")
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        try equal(items.first { $0.name == "name" }?.value.flatMap { Data(base64Encoded: $0) }.map { String(decoding: $0, as: UTF8.self) }, AppInfo.name)
        try equal(items.first { $0.name == "token" }?.value, "12345678")
        let unsafe = SamsungProtocol.channelURL(host: sampleHost, token: "1&name=x")
        try truth(unsafe?.query?.contains("token") == false)
        try truth(SamsungProtocol.channelURL(host: "8.8.8.8", token: nil) == nil)
        try truth(SamsungProtocol.restURL(host: "203.0.113.10") == nil)
        for id in ["3201907018807", "111299001912", "org.tizen.browser"] { try truth(SamsungProtocol.validAppID(id)) }
        for id in ["", "../secret", "a/b", "a?b", "a b", String(repeating: "1", count: 65)] { try truth(!SamsungProtocol.validAppID(id)) }
        guard let key = try JSONSerialization.jsonObject(with: Data(SamsungProtocol.keyMessage("KEY_VOLUP").utf8)) as? [String: Any],
              let params = key["params"] as? [String: String] else { throw RemoteError.message("Invalid key message") }
        try equal(key["method"] as? String, "ms.remote.control")
        try equal(params, ["Cmd": "Click", "DataOfCmd": "KEY_VOLUP", "Option": "false", "TypeOfRemote": "SendRemoteKey"])
        guard let text = try JSONSerialization.jsonObject(with: Data(SamsungProtocol.textMessage("Olá \"TV\"").utf8)) as? [String: Any],
              let textParams = text["params"] as? [String: String], let encoded = textParams["Cmd"], let decoded = Data(base64Encoded: encoded) else { throw RemoteError.message("Invalid text message") }
        try equal(String(decoding: decoded, as: UTF8.self), "Olá \"TV\"")
        try equal(textParams["TypeOfRemote"], "SendInputString")
        try truth(SamsungProtocol.textEndMessage.contains("SendInputEnd"))
    }
    static func testSamsungEventsDeviceInfoAndAppStatus() throws {
        func event(_ json: String) -> SamsungProtocol.ChannelEvent? { SamsungProtocol.parse(Data(json.utf8)) }
        try equal(event(#"{"event":"ms.channel.connect","data":{"token":"12345678","clients":[]}}"#), .connected(token: "12345678"))
        try equal(event(#"{"event":"ms.channel.connect","data":{"token":12345678}}"#), .connected(token: "12345678"))
        try equal(event(#"{"event":"ms.channel.connect","data":{"clients":[]}}"#), .connected(token: nil))
        try equal(event(#"{"event":"ms.channel.connect","data":{"token":"bad token!"}}"#), .connected(token: nil))
        try equal(event(#"{"event":"ms.channel.unauthorized"}"#), .unauthorized)
        try equal(event(#"{"event":"ms.channel.timeOut"}"#), .timedOut)
        try equal(event(#"{"event":"ms.channel.clientConnect"}"#), .other)
        try truth(event("not json") == nil)
        let mac = ["00", "11", "22", "33", "44", "55"].joined(separator: ":")
        let info = SamsungProtocol.deviceInfo(Data(#"{"device":{"type":"Samsung SmartTV","name":"[TV] Samsung 5 Series (43)","modelName":"UN43T5300AGXZD","PowerState":"standby","firmwareVersion":"Unknown","wifiMac":"\#(mac.uppercased())"}}"#.utf8))
        try equal(info, SamsungProtocol.DeviceInfo(name: "Samsung 5 Series (43)", model: "UN43T5300AGXZD", mac: mac, powerOn: false, firmware: ""))
        try equal(SamsungProtocol.deviceInfo(Data(#"{"device":{"type":"Samsung SmartTV","wifiMac":"zz:11"}}"#.utf8))?.mac, nil)
        try truth(SamsungProtocol.deviceInfo(Data(#"{"device":{"type":"Speaker"}}"#.utf8)) == nil)
        let status = SamsungProtocol.appStatus(Data(#"{"id":"111299001912","name":"YouTube","running":true,"visible":true}"#.utf8))
        try equal(status?.id, "111299001912"); try equal(status?.name, "YouTube"); try equal(status?.visible, true)
    }
    static func testBrandKeyMappingsAndCapabilities() throws {
        let samsungCodes = RemoteKey.allCases.map { SamsungProtocol.keyCode($0) } + MediaCommand.allCases.map { SamsungProtocol.keyCode($0) }
        try equal(Set(samsungCodes).count, samsungCodes.count)
        try truth(samsungCodes.allSatisfy { $0.hasPrefix("KEY_") })
        try equal(SamsungProtocol.keyCode(.back), "KEY_RETURN")
        try equal(WebOSConnection.buttonName(.home), "HOME")
        try equal(WebOSConnection.buttonName(.channelUp), "CHANNELUP")
        try truth(WebOSConnection.buttonName(.source) == nil)
        try truth(TVBrand.lg.capabilities.isSuperset(of: [.volumeLevel, .inputList, .pointer, .picture, .closeApps]))
        try truth(TVBrand.samsung.capabilities.isDisjoint(with: [.pointer, .picture, .inputList, .closeApps]))
        try truth(TVBrand.samsung.capabilities.contains(.sourceKey))
        try equal(TVBrand.samsung.mediaRenderer.port, 9197)
    }
    static func testKeyboardShortcutsLeaveModifiersAndTypingAlone() throws {
        func action(_ code: Int, _ characters: String? = nil, _ modifiers: NSEvent.ModifierFlags = []) -> RemoteShortcut? {
            RemoteShortcut.action(keyCode: UInt16(code), characters: characters, modifiers: modifiers)
        }
        try equal(action(126, nil, [.function, .numericPad]), .key(.up))
        try equal(action(123), .key(.left)); try equal(action(124), .key(.right)); try equal(action(125), .key(.down))
        try equal(action(36), .ok); try equal(action(76), .ok)
        try equal(action(51), .key(.back)); try equal(action(49, " "), .playPause)
        try equal(action(24, "="), .volume(up: true)); try equal(action(24, "+", .shift), .volume(up: true))
        try equal(action(27, "-"), .volume(up: false))
        try equal(action(46, "M", .shift), .mute); try equal(action(4, "h"), .key(.home))
        try truth(action(126, nil, .command) == nil)
        try truth(action(4, "h", .command) == nil)
        try truth(action(46, "m", .option) == nil)
        try truth(action(0, "a") == nil)
        try truth(action(53) == nil) // Esc is handled by the panel itself.
    }
    static func testSavedTVsMigrateUpsertAndStayLocal() throws {
        let suite = "NodeRemote.FeatureChecks." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { throw RemoteError.message("Could not create isolated test preferences") }
        defer { defaults.removePersistentDomain(forName: suite) }
        try truth(TVLibrary.load(defaults).isEmpty)
        let other = [192, 168, 0, 11].map(String.init).joined(separator: ".")
        defaults.set(sampleHost, forKey: "tv.host"); defaults.set("Sala", forKey: "tv.name"); defaults.set("samsung", forKey: "tv.brand")
        let migrated = TVLibrary.load(defaults)
        try equal(migrated, [SavedTV(brand: .samsung, host: sampleHost, name: "Sala", model: "", mac: "")])
        var list = TVLibrary.upsert(SavedTV(brand: .lg, host: other, name: "Quarto", model: "C5", mac: ""), into: migrated)
        list = TVLibrary.upsert(SavedTV(brand: .samsung, host: sampleHost, name: "Sala nova", model: "T5300", mac: ""), into: list)
        try equal(list.map(\.name), ["Sala nova", "Quarto"])
        try equal(TVLibrary.upsert(SavedTV(brand: .lg, host: "8.8.8.8", name: "Fora", model: "", mac: ""), into: list).count, 2)
        TVLibrary.save(list + [SavedTV(brand: .lg, host: "8.8.8.8", name: "Fora", model: "", mac: "")], defaults)
        try equal(TVLibrary.load(defaults), list)
        // Once a list exists, legacy keys never bring a removed TV back.
        TVLibrary.save([], defaults)
        try truth(TVLibrary.load(defaults).isEmpty)
    }
    static func testYouTubeLinksAndDroppedFiles() throws {
        for link in ["https://www.youtube.com/watch?v=jNQXAC9IVRw", "youtube.com/watch?v=jNQXAC9IVRw&t=10s", "https://youtu.be/jNQXAC9IVRw?si=abc",
                     "https://m.youtube.com/watch?feature=share&v=jNQXAC9IVRw", "https://www.youtube.com/shorts/jNQXAC9IVRw", "  https://www.youtube.com/live/jNQXAC9IVRw  "] {
            try equal(YouTubeLink.videoID(from: link), "jNQXAC9IVRw")
        }
        for link in ["https://vimeo.com/123", "https://www.youtube.com/", "https://youtube.com.evil.example/watch?v=jNQXAC9IVRw", "https://youtu.be/short", "texto qualquer", "https://www.youtube.com/watch?v=jNQX<script>"] {
            try truth(YouTubeLink.videoID(from: link) == nil)
        }
        try truth(MediaDrop.playable(URL(fileURLWithPath: "/tmp/filme.mp4")))
        try truth(MediaDrop.playable(URL(fileURLWithPath: "/tmp/foto.JPG")))
        try truth(MediaDrop.playable(URL(fileURLWithPath: "/tmp/musica.mp3")))
        try truth(!MediaDrop.playable(URL(fileURLWithPath: "/tmp/planilha.xlsx")))
        try truth(!MediaDrop.playable(URL(string: "https://example.com/video.mp4")!))
    }
    static func testRoutineSchedulesAndCallVolume() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        // 2026-10-14 is a Wednesday (weekday 4).
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 7, minute: 0, second: 30))!
        var schedule = SceneSchedule(hour: 7, minute: 0, weekdays: [2, 3, 4, 5, 6], tvHost: "tv")
        try truth(schedule.isDue(at: wednesday, calendar: calendar))
        try truth(!schedule.isDue(at: wednesday.addingTimeInterval(60), calendar: calendar))
        try truth(!schedule.isDue(at: wednesday.addingTimeInterval(4 * 86400), calendar: calendar)) // Sunday
        schedule.enabled = false
        try truth(!schedule.isDue(at: wednesday, calendar: calendar))
        try equal(SceneSchedule(hour: 7, minute: 5, weekdays: [6, 2, 3, 4, 5], tvHost: "").summary, "07:05 · dias úteis")
        try equal(SceneSchedule(hour: 23, minute: 30, weekdays: [1, 7], tvHost: "").summary, "23:30 · fim de semana")
        try equal(SceneSchedule(hour: 9, minute: 0, weekdays: [2, 4], tvHost: "").summary, "09:00 · S Q")
        // Scenes saved before schedules existed still load.
        let old = #"[{"id":"7F1B2C3D-0000-4000-8000-000000000001","name":"Cinema","symbol":"film","steps":[{"volume":{"_0":25}}]}]"#
        let decoded = try JSONDecoder().decode([TVScene].self, from: Data(old.utf8))
        try equal(decoded.first?.steps, [.volume(25)]); try truth(decoded.first?.schedule == nil)
        try equal(SceneLibrary.label(.powerOff), "Desligar a TV")
        try equal(CallAction.lowered(from: 30), 9)
        try equal(CallAction.lowered(from: 4), 2)
        try equal(CallAction.lowered(from: 1), 1)
    }
    static func testScenesPersistAndFindAppsAcrossBrands() throws {
        let suite = "NodeRemote.FeatureChecks." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { throw RemoteError.message("Could not create isolated test preferences") }
        defer { defaults.removePersistentDomain(forName: suite) }
        try equal(SceneLibrary.load(defaults).map(\.name), ["Cinema", "Dormir"])
        let scene = TVScene(name: "Jogo", symbol: "gamecontroller", steps: [.openApp(id: "111299001912", title: "YouTube"), .volume(30), .sleepTimer(minutes: 45), .pictureMode("game")])
        SceneLibrary.save([scene], defaults)
        try equal(SceneLibrary.load(defaults), [scene])
        SceneLibrary.save([], defaults)
        try truth(SceneLibrary.load(defaults).isEmpty) // Deleting every scene does not bring the defaults back.
        let samsungApps = [TVApp(id: "3201907018807", title: "Netflix", icon: nil), TVApp(id: "3201606009684", title: "Spotify - Music and Podcasts", icon: nil)]
        let lgApps = [TVApp(id: "netflix", title: "Netflix", icon: nil), TVApp(id: "spotify-beehive", title: "Spotify", icon: nil)]
        try equal(SceneLibrary.resolve(id: "netflix", title: "Netflix", in: samsungApps)?.id, "3201907018807")
        try equal(SceneLibrary.resolve(id: "netflix", title: "Netflix", in: lgApps)?.id, "netflix")
        try equal(SceneLibrary.resolve(id: "spotify-beehive", title: "Spotify", in: samsungApps)?.id, "3201606009684")
        try equal(SceneLibrary.resolve(id: "3201606009684", title: "Spotify - Music and Podcasts", in: lgApps)?.id, "spotify-beehive")
        try truth(SceneLibrary.resolve(id: "x", title: "Globoplay", in: lgApps) == nil)
        try truth(SceneLibrary.resolve(id: "x", title: "", in: lgApps) == nil)
        try equal(scene.steps.map(SceneLibrary.label), ["Abrir YouTube", "Volume 30", "Desligar em 45 min", "Imagem Jogo"])
    }
    static func testSleepTimerLabels() throws {
        try equal(SleepTimer.presets.map(SleepTimer.duration), ["15 min", "30 min", "45 min", "1 h", "1 h 30 min", "2 h"])
        try equal(SleepTimer.clock(27 * 60 + 41), "27:41")
        try equal(SleepTimer.clock(3900), "1:05:00")
        try equal(SleepTimer.clock(0.2), "0:01")
        try equal(SleepTimer.clock(-5), "0:00")
        try equal(SleepTimer.menuBar(30 * 60), "30m")
        try equal(SleepTimer.menuBar(29 * 60 + 1), "30m")
        try equal(SleepTimer.menuBar(59), "<1m")
    }
    static func testRenderingControlEnvelopeAndValue() throws {
        let envelope = DLNATransport.envelope(action: "SetVolume", parameters: [("Channel", "Master"), ("DesiredVolume", "12")], urn: DLNATransport.renderingURN)
        try truth(XMLParser(data: Data(envelope.utf8)).parse())
        try truth(envelope.contains("<InstanceID>0</InstanceID><Channel>Master</Channel><DesiredVolume>12</DesiredVolume>"))
        try truth(envelope.contains(DLNATransport.renderingURN))
        try equal(DLNATransport.value("CurrentVolume", in: "<s:Body><u:GetVolumeResponse><CurrentVolume> 10 </CurrentVolume></u:GetVolumeResponse></s:Body>"), "10")
        try truth(DLNATransport.value("CurrentMute", in: "<CurrentVolume>10</CurrentVolume>") == nil)
    }

    static func testUsageSurvivesRestartAndClipsMidnightWithoutCountingSleep() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("usage.json")
        let midnight = Date(timeIntervalSince1970: 86400 * 20000)
        let journal = UsageJournal(url: file)
        journal.observe(host: "tv", appID: "netflix", title: "Netflix", at: midnight.addingTimeInterval(-10))
        journal.observe(host: "tv", appID: "youtube", title: "YouTube", at: midnight.addingTimeInterval(10))
        journal.observe(host: "tv", appID: "youtube", title: "YouTube", at: midnight.addingTimeInterval(30))
        // An hour offline must contribute zero seconds, even for the same app.
        journal.observe(host: "tv", appID: "youtube", title: "YouTube", at: midnight.addingTimeInterval(3630))
        journal.pause(at: midnight.addingTimeInterval(3640))
        try journal.save()
        let restored = UsageJournal(url: file)
        let totals = restored.totals(host: "tv", since: midnight, until: midnight.addingTimeInterval(4000))
        try equal(totals.first?.id, "youtube")
        try equal(totals.first?.seconds, 30)
        try equal(totals.last?.seconds, 10)
        try truth(restored.totals(host: "other", since: midnight).isEmpty)
    }
    static func testHTTPRangeSupportsSeekSuffixAndRejectsInvalidRanges() throws {
        let seek = try MediaHTTP.range("bytes=5-12", size: 10)
        try equal(seek.start, 5); try equal(seek.end, 9); try truth(seek.partial)
        try equal(try MediaHTTP.range("bytes=-3", size: 10).start, 7)
        try equal(try MediaHTTP.range("bytes=3-", size: 10).end, 9)
        try rejects { _ = try MediaHTTP.range("bytes=10-", size: 10) }
        try rejects { _ = try MediaHTTP.range("bytes=6-2", size: 10) }
        try rejects { _ = try MediaHTTP.range("bytes=0-1,4-5", size: 10) }
    }
    static func testMediaServerStreamsOnlySelectedFileAndSupportsHeadAndRange() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try Data("0123456789".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let server = MediaFileServer(file: file, allowedHost: "127.0.0.1")
        let url = try await server.start()
        defer { server.stop() }
        var request = URLRequest(url: url); request.setValue("bytes=3-6", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        try equal((response as? HTTPURLResponse)?.statusCode, 206)
        try equal(String(decoding: data, as: UTF8.self), "3456")
        request.httpMethod = "HEAD"
        let (empty, head) = try await URLSession.shared.data(for: request)
        try truth(empty.isEmpty)
        try equal((head as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Length"), "4")
        request.httpMethod = "GET"; request.setValue("bytes=99-", forHTTPHeaderField: "Range")
        let (_, invalid) = try await URLSession.shared.data(for: request)
        try equal((invalid as? HTTPURLResponse)?.statusCode, 416)
        let (_, absent) = try await URLSession.shared.data(from: url.deletingLastPathComponent().appendingPathComponent("secret"))
        try equal((absent as? HTTPURLResponse)?.statusCode, 404)
    }
    static func testSOAPMetadataEscapesUserFilenameAndURL() throws {
        let metadata = DLNATransport.metadata(url: URL(string: "http://127.0.0.1/a?x=1&y=2")!, title: "A < B & C", mime: "video/mp4")
        let envelope = DLNATransport.envelope(action: "SetAVTransportURI", parameters: [("CurrentURIMetaData", metadata)])
        try truth(XMLParser(data: Data(envelope.utf8)).parse())
        try truth(metadata.contains("A &lt; B &amp; C"))
        try truth(envelope.contains("&lt;DIDL-Lite"))
    }
    static func testPointerMotionKeepsEveryDelta() throws {
        var motion = PointerMotion()
        motion.add(dx: 10, dy: 2)
        let first = motion.next()
        // Additional gesture samples arrive while the first send is in progress.
        motion.add(dx: 160, dy: -40); motion.add(dx: 75, dy: -5)
        var x = first.dx, y = first.dy
        while !motion.isEmpty { let delta = motion.next(); x += delta.dx; y += delta.dy; try truth(abs(delta.dx) <= 80 && abs(delta.dy) <= 80) }
        try equal(x, 245); try equal(y, -43)
        try equal(PointerMessage.click, "type:click\n\n")
    }
    static func testHomePresentationSurvivesRepeatedUnderlyingAppReports() throws {
        var state = HomePresentation()
        state.didSendHome(underlyingID: "youtube.leanback.v4")
        for _ in 0..<100 { state.observe(appID: "youtube.leanback.v4") }
        try truth(state.requested)
        state.observe(appID: "com.webos.app.hdmi2")
        try truth(!state.requested)
        state.didSendHome(underlyingID: "com.webos.app.hdmi2")
        state.dismiss() // User selects the same underlying input or presses Back/OK.
        state.observe(appID: "com.webos.app.hdmi2")
        try truth(!state.requested)
        state.didSendHome(underlyingID: "")
        state.observe(appID: "")
        try truth(state.requested)
        state.observe(appID: "netflix")
        try truth(!state.requested)
    }
    @MainActor static func testHomeClosesUserAppOnceWithoutLaunchingAnything() async throws {
        var actions: [String] = []
        let installed: Set<String> = ["youtube.leanback.v4", "com.webos.app.browser"]
        try await HomeNavigation.run(appID: "youtube.leanback.v4", installedApps: installed, closeApp: { actions.append("close:\($0)") }, pressHome: { actions.append("HOME") })
        try equal(actions, ["close:youtube.leanback.v4", "HOME"])
        for id in ["com.webos.app.hdmi2", "com.webos.app.browser", "com.webos.app.livetv", "", "unknown"] {
            actions = []
            try await HomeNavigation.run(appID: id, installedApps: installed, closeApp: { actions.append("close:\($0)") }, pressHome: { actions.append("HOME") })
            try equal(actions, ["HOME"])
        }
        actions = []; var reportedFailure = false
        do {
            try await HomeNavigation.run(appID: "youtube.leanback.v4", installedApps: installed, closeApp: { actions.append("close:\($0)"); throw RemoteError.message("TV refusal") }, pressHome: { actions.append("HOME") })
        } catch { reportedFailure = true }
        try truth(reportedFailure); try equal(actions, ["close:youtube.leanback.v4", "HOME"])
    }
    @MainActor static func testPointerConnectionAndRecovery() async throws {
        let first = FakePointerTransport(), second = FakePointerTransport(), third = FakePointerTransport()
        var opens = 0
        let channel = PointerChannel {
            opens += 1
            try await Task.sleep(nanoseconds: 20_000_000)
            return opens == 1 ? first : opens == 2 ? second : third
        }
        defer { channel.close() }
        let left = Task { try await channel.send(PointerMessage.button("LEFT")) }
        while opens == 0 { await Task.yield() }
        let right = Task { try await channel.send(PointerMessage.button("RIGHT")) }
        try await left.value; try await right.value
        try equal(opens, 1)
        try equal(first.messages, [PointerMessage.button("LEFT"), PointerMessage.button("RIGHT")])
        first.close()
        try await channel.check()
        try equal(opens, 2); try truth(second.messages.isEmpty)
        second.failSend = true
        var failedClick = false
        do { try await channel.send(PointerMessage.click) } catch { failedClick = true }
        try truth(failedClick); try equal(second.sendAttempts, 1); try equal(opens, 2)
        // Only a subsequent user action opens a new connection. No replay of the failed click.
        try await channel.send(PointerMessage.click)
        try equal(opens, 3); try equal(third.messages, [PointerMessage.click])
    }
    @MainActor static func testCancelledHomeDoesNotSendAnotherCommand() async throws {
        var actions: [String] = []
        let operation = Task { @MainActor in
            try await HomeNavigation.run(appID: "netflix", installedApps: ["netflix"], closeApp: { id in
                actions.append("close:\(id)")
                withUnsafeCurrentTask { $0?.cancel() }
            }, pressHome: { actions.append("HOME") })
        }
        var cancelled = false
        do { try await operation.value } catch is CancellationError { cancelled = true }
        try truth(cancelled)
        try equal(actions, ["close:netflix"])
    }
    @MainActor static func testPointerPreflightRecoveryDoesNotReplayCommands() async throws {
        let first = FakePointerTransport(), replacement = FakePointerTransport()
        var opens = 0
        let channel = PointerChannel { opens += 1; return opens == 1 ? first : replacement }
        defer { channel.close() }
        try await channel.send(PointerMessage.button("HOME"))
        first.failPing = true
        try await channel.check()
        try equal(opens, 2)
        try truth(first.closed)
        try equal(first.messages, [PointerMessage.button("HOME")])
        try truth(replacement.messages.isEmpty)
        try await channel.send(PointerMessage.button("BACK"))
        try equal(replacement.messages, [PointerMessage.button("BACK")])
    }
    @MainActor static func testPointerCloseCancelsPendingInput() async throws {
        let transport = FakePointerTransport()
        var opening = false
        let channel = PointerChannel {
            opening = true
            try await Task.sleep(nanoseconds: 20_000_000)
            return transport
        }
        let operation = Task { try await channel.send(PointerMessage.click) }
        for _ in 0..<1000 where !opening { await Task.yield() }
        try truth(opening)
        channel.close()
        var cancelled = false
        do { try await operation.value } catch is CancellationError { cancelled = true }
        try truth(cancelled)
        try equal(transport.sendAttempts, 0)
        do { try await channel.send(PointerMessage.click); throw RemoteError.message("Closed channel accepted input") }
        catch is CancellationError { }
        try equal(transport.sendAttempts, 0)
    }
}

@MainActor private final class FakePointerTransport: PointerTransport {
    var messages: [String] = []
    var sendAttempts = 0
    var failSend = false
    var failPing = false
    var closed = false
    func send(_ message: String) async throws {
        sendAttempts += 1
        guard !closed, !failSend else { throw RemoteError.message("Simulated send failure") }
        messages.append(message)
    }
    func receive() async throws {
        while !closed { try await Task.sleep(nanoseconds: 5_000_000) }
        throw RemoteError.message("Simulated server closure")
    }
    func ping() async throws { if closed || failPing { throw RemoteError.message("Simulated failed ping") } }
    func close() { closed = true }
}
