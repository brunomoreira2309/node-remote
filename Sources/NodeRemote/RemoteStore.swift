import SwiftUI
import AppKit

struct TVApp: Identifiable, Codable { let id: String; let title: String; let icon: String? }
struct TVInput: Identifiable { let id: String; let label: String; let connected: Bool; let appID: String }
struct RemoteEvent: Identifiable, Codable { let id: UUID; let date: Date; let title: String; let detail: String
    init(title: String, detail: String) { id = UUID(); date = Date(); self.title = title; self.detail = detail }
}

@MainActor final class RemoteStore: ObservableObject {
    @Published var savedTVs = TVLibrary.load()
    @Published var sleepDeadline: Date?
    @Published var scenes = SceneLibrary.load()
    @Published var callAction = CallAction(rawValue: UserDefaults.standard.string(forKey: "tv.callAction") ?? "") ?? .off {
        didSet { UserDefaults.standard.set(callAction.rawValue, forKey: "tv.callAction"); watchCalls() }
    }
    @Published private(set) var inCall = false
    private let callMonitor = CallMonitor()
    private var callRestore: (host: String, volume: Int?, loweredTo: Int?, muted: Bool, paused: Bool)?
    private let preview: Bool
    private var scheduleTimer: Timer?
    private var firedSchedules: [UUID: String] = [:]
    @Published var runningScene: UUID?
    private var sleepTask: Task<Void, Never>?
    private var sleepHost = ""
    @Published var brand = TVConfiguration().brand
    @Published var host = TVConfiguration().host
    @Published var name = TVConfiguration().name
    @Published var model = TVConfiguration().model
    @Published var mac = TVConfiguration().mac
    @Published var connected = false
    @Published var pointerReady = false
    @Published var connecting = false
    @Published var pairing = false
    @Published var discovering = false
    @Published var devices: [TVDevice] = []
    @Published var apps: [TVApp] = []
    @Published var inputs: [TVInput] = []
    @Published var volume: Double = 0
    @Published var hasVolume = false
    @Published var muted = false
    @Published var foregroundID = ""
    @Published var foregroundName = ""
    @Published private var homePresentation = HomePresentation()
    @Published var error: String?
    @Published var notice: String?
    @Published var events: [RemoteEvent] = []
    @Published var firmware = ""
    @Published var webOS = ""
    @Published var picture: [String: Int] = [:]
    @Published var pictureApplying = false
    @Published var usageRevision = 0
    @Published var mediaFile: URL?
    @Published var mediaBusy = false
    @Published var casting = false
    @Published var mediaStatus = "Escolha um vídeo, uma música ou uma foto."
    @Published var preferredPanelHeight: CGFloat = 740
    @Published var favorites = Set(UserDefaults.standard.stringArray(forKey: "tv.favorites") ?? [
        "netflix", "youtube.leanback.v4", "amazon", "com.disney.disneyplus-prod",
        "3201907018807", "111299001912", "3201910019365", "3201901017640",
    ])
    private(set) var connection: (any TVController)?
    private var connectTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private var autoReconnect = false
    private let catalog: [TVApp]
    private let dataDirectory: URL
    private lazy var journal = UsageJournal(url: dataDirectory.appendingPathComponent("usage.json"))
    private var observers: [NSObjectProtocol] = []
    private var fileServer: MediaFileServer?
    private var transportURL: URL?
    private var powerActive = false
    /// A preview store keeps its history in a throwaway folder and never loads this Mac's own.
    init(preview: Bool = false) {
        self.preview = preview
        dataDirectory = preview
            ? FileManager.default.temporaryDirectory.appendingPathComponent("node-remote-preview-" + UUID().uuidString)
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("br.local.NodeRemote")
        catalog = (try? AppResources.bundle.url(forResource: "app-catalog", withExtension: "json").map {
            try JSONDecoder().decode([TVApp].self, from: Data(contentsOf: $0))
        }) ?? []
        events = (try? JSONDecoder().decode([RemoteEvent].self, from: Data(contentsOf: dataDirectory.appendingPathComponent("events.json")))) ?? []
        callMonitor.onChange = { [weak self] active in MainActor.assumeIsolated { self?.callChanged(active) } }
        if !preview {
            scheduleTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.checkSchedules() } }
        }
        watchCalls()
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pauseUsage() }
        })
    }

    var capabilities: TVCapabilities { brand.capabilities }
    var pinnedApps: [TVApp] { shortcuts.filter { favorites.contains($0.id) } }
    var homeRequested: Bool { homePresentation.requested }
    var displayForegroundID: String { homeRequested ? "com.webos.app.home" : foregroundID }
    var currentInput: TVInput? { homeRequested ? nil : inputs.first { $0.appID == foregroundID } }
    var orderedInputs: [TVInput] {
        inputs.enumerated().sorted { a, b in
            let aActive = a.element.appID == displayForegroundID
            let bActive = b.element.appID == displayForegroundID
            return aActive != bActive ? aActive : a.offset < b.offset
        }.map(\.element)
    }
    func log(_ title: String, _ detail: String) {
        events.insert(RemoteEvent(title: title, detail: detail), at: 0)
        if events.count > 200 { events.removeLast(events.count - 200) }
        if title != "Leitura" {
            let persisted = events.filter { $0.title != "Leitura" }
            do { try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true); try JSONEncoder().encode(persisted).write(to: dataDirectory.appendingPathComponent("events.json"), options: .atomic) }
            catch { notice = "Não foi possível salvar o histórico de eventos." }
        }
    }

    var status: String { pairing ? "Aceite a conexão na TV" : connecting ? "Conectando…" : connected ? "Conectado" : "Desconectado" }
    var currentApp: String { homeRequested ? "Tela inicial" : foregroundName.isEmpty ? (connected ? "TV ligada" : "Sua TV, no seu Mac.") : foregroundName }
    var shortcuts: [TVApp] {
        let preferred = ["netflix", "youtube", "amazon", "disney", "globoplay", "spotify", "hbo", "apple"]
        return apps.sorted { a, b in
            if favorites.contains(a.id) != favorites.contains(b.id) { return favorites.contains(a.id) }
            let ai = preferred.firstIndex { a.id.localizedCaseInsensitiveContains($0) || a.title.localizedCaseInsensitiveContains($0) } ?? 100
            let bi = preferred.firstIndex { b.id.localizedCaseInsensitiveContains($0) || b.title.localizedCaseInsensitiveContains($0) } ?? 100
            return ai != bi ? ai < bi : a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }
    func connect(allowFirstUseTrust: Bool = true) {
        guard !connecting else { return }
        guard TVHost.local(host) else { error = "Digite o IPv4 local da TV ou procure uma TV na rede."; return }
        autoReconnect = true; error = nil; connecting = true; pairing = false
        pauseUsage()
        homePresentation.dismiss()
        connection?.close(); refreshTask?.cancel(); pointerReady = false
        let client: any TVController = brand == .samsung ? SamsungConnection(host: host) : WebOSConnection(host: host)
        connection = client
        let trustedBrand = brand
        client.onCertificateTrust = { host, fingerprint in
            await ConnectionTrustPrompt.confirm(host: host, fingerprint: fingerprint, brand: trustedBrand)
        }
        client.onPairing = { [weak self] in self?.pairing = true }
        client.onEvent = { [weak self] title, detail in self?.log(title, detail) }
        client.onPointerState = { [weak self, weak client] ready in
            guard let self, self.connection === client else { return }
            self.pointerReady = ready
        }
        client.onDisconnect = { [weak self, weak client] failure in
            guard let self, self.connection === client else { return }
            self.connected = false; self.pointerReady = false; self.hasVolume = false; self.pointerMotionTask?.cancel(); self.motion = PointerMotion()
            self.homePresentation.dismiss()
            self.pauseUsage()
            self.log("Conexão perdida", failure.localizedDescription)
            if !self.connecting {
                self.notice = "Conexão perdida. Reconectando…"
                self.scheduleReconnect()
            }
        }
        connectTask = Task {
            do {
                try await client.connect(allowFirstUseTrust: allowFirstUseTrust)
                guard connection === client else { return }
                connected = true; connecting = false; pairing = false; notice = nil
                log("Conectado", "\(name) · \(host)")
                UserDefaults.standard.set(brand.rawValue, forKey: "tv.brand")
                UserDefaults.standard.set(host, forKey: "tv.host")
                UserDefaults.standard.set(name, forKey: "tv.name")
                UserDefaults.standard.set(mac, forKey: "tv.mac")
                let details = await client.details()
                if let detectedModel = details.model { model = detectedModel }
                firmware = details.firmware; webOS = details.platform
                UserDefaults.standard.set(model, forKey: "tv.model")
                savedTVs = TVLibrary.upsert(SavedTV(brand: brand, host: host, name: name, model: model, mac: mac), into: savedTVs)
                TVLibrary.save(savedTVs)
                await refresh()
                await client.observeState { [weak self] in self?.apply($0) }
                await refreshPicture()
                // Warm up and verify the input socket without issuing any TV input.
                do { try await client.checkPointer(); log("Controle pronto", "A conexão de navegação está pronta e verificada.") }
                catch { log("Controle indisponível", error.localizedDescription) }
                refreshTask = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 20_000_000_000)
                        if Task.isCancelled { break }
                        await refreshState()
                    }
                }
            } catch {
                guard connection === client else { return }
                client.close(); connected = false; connecting = false; pairing = false
                self.error = "\(error.localizedDescription) Verifique se a TV está ligada e na mesma rede Wi-Fi."
                log("Falha na conexão", error.localizedDescription)
                if allowFirstUseTrust { autoReconnect = false }
                scheduleReconnect()
            }
        }
    }
    private func scheduleReconnect() {
        guard autoReconnect else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { try? await Task.sleep(nanoseconds: 5_000_000_000); if !Task.isCancelled { connect(allowFirstUseTrust: false) } }
    }
    func disconnect() {
        pauseUsage()
        pointerMotionTask?.cancel(); motion = PointerMotion()
        fileServer?.stop(); fileServer = nil; casting = false; transportURL = nil
        autoReconnect = false; connectTask?.cancel(); reconnectTask?.cancel(); refreshTask?.cancel(); volumeTask?.cancel()
        connection?.close(); connection = nil; connected = false; pointerReady = false; connecting = false; pairing = false; hasVolume = false
        foregroundID = ""; foregroundName = ""; apps = []; inputs = []
        homePresentation.dismiss()
    }
    func discover() {
        guard !discovering else { return }; discovering = true; error = nil
        Task { devices = await TVDiscovery.search(); discovering = false; if devices.isEmpty { notice = "Nenhuma TV encontrada. Ligue a TV ou digite o IP dela abaixo." } }
    }
    func select(_ tv: TVDevice) {
        if tv.host != host { cancelSleepTimer(notice: nil) }
        disconnect(); brand = tv.brand; host = tv.host; name = tv.name; model = tv.model; mac = tv.mac ?? ""
        connect()
    }
    func refresh() async {
        guard let client = connection, connected else { return }
        do {
            var seen = Set<String>()
            apps = try await client.listApps().filter { seen.insert($0.id).inserted }.map(catalogApp)
        } catch { self.error = "Não foi possível listar os apps: \(error.localizedDescription)" }
        inputs = await client.listInputs()
        await refreshState()
    }
    /// Packaged names and icons, matched by ID or, across brands, by the name the TV reports.
    private func catalogApp(_ app: TVApp) -> TVApp {
        if let known = catalog.first(where: { $0.id == app.id }) { return TVApp(id: app.id, title: known.title, icon: known.icon) }
        let similar = catalog.first { app.title.lowercased().hasPrefix($0.title.lowercased()) }
        return TVApp(id: app.id, title: app.title, icon: similar?.icon)
    }
    func refreshState() async {
        guard let client = connection, connected else { return }
        let state = await client.readState()
        guard connection === client else { return }
        apply(state)
        if state.powerActive == false { pauseUsage() }
    }
    private func apply(_ state: TVState) {
        if let active = state.powerActive { powerActive = active }
        if let value = state.volume { volume = value; hasVolume = true }
        if let value = state.muted { muted = value }
        if let id = state.foregroundID { updateForeground(id: id, title: state.foregroundTitle) }
    }
    private func updateForeground(id: String, title: String?) {
        let previous = foregroundID
        foregroundID = id
        homePresentation.observe(appID: foregroundID)
        if foregroundID.hasPrefix("com.webos.app.hdmi") {
            let inputID = "HDMI" + foregroundID.replacingOccurrences(of: "com.webos.app.hdmi", with: "")
            let label = inputs.first(where: { $0.id.replacingOccurrences(of: "_", with: "") == inputID })?.label ?? inputID
            foregroundName = label == inputID ? inputID : "\(label) · \(inputID)"
        } else {
            foregroundName = title ?? apps.first(where: { $0.id == foregroundID })?.title ?? "TV ligada"
        }
        if previous != foregroundID { log("App informado", foregroundName) }
        if powerActive && connected && !homeRequested { journal.observe(host: host, appID: foregroundID, title: currentInput?.label ?? foregroundName); saveUsage() }
        else if homeRequested { journal.pause(); saveUsage() }
        else { pauseUsage() }
    }
    func perform(_ action: @escaping (any TVController) async throws -> Void) {
        guard connected, let client = connection else { return }
        error = nil
        Task { do { try await action(client) } catch { self.error = error.localizedDescription; self.log("Falha no comando", error.localizedDescription) } }
    }
    func press(_ key: RemoteKey) {
        if key == .home { goHome(); return }
        log("Controle", key.rawValue); perform {
            try await $0.press(key)
            if [.back, .exit, .source].contains(key) { self.homePresentation.dismiss(); await self.refreshState() }
        }
    }
    @Published var navigatingHome = false
    func goHome() {
        guard connected, !navigatingHome, let client = connection else { return }
        navigatingHome = true; error = nil
        log("Controle", "HOME · fechar o app e abrir o menu")
        Task {
            defer { navigatingHome = false }
            do {
                // Home on webOS 5 overlays the running app. Close a foreground user app first;
                // never close an HDMI input, the launcher or a system service.
                let closes = capabilities.contains(.closeApps)
                let id = closes ? try await client.foregroundAppID() : ""
                try await HomeNavigation.run(appID: id, installedApps: closes ? Set(apps.map(\.id)) : [], closeApp: { appID in
                    self.log("Fechar app", self.apps.first { $0.id == appID }?.title ?? appID)
                    try await client.closeApp(appID)
                }, pressHome: {
                    try await client.press(.home)
                    // Read the app underneath after closing; keep Home presentation across polls.
                    await self.refreshState()
                    self.homePresentation.didSendHome(underlyingID: self.foregroundID)
                    self.journal.pause(); self.saveUsage()
                })
                await refreshState()
            } catch { self.error = error.localizedDescription; log("Não foi possível abrir o início", error.localizedDescription) }
        }
    }
    private var motion = PointerMotion()
    private var pointerMotionTask: Task<Void, Never>?
    func movePointer(dx: Int, dy: Int) {
        guard connected, let client = connection, dx != 0 || dy != 0 else { return }
        motion.add(dx: dx, dy: dy)
        guard pointerMotionTask == nil else { return }
        pointerMotionTask = Task {
            defer { pointerMotionTask = nil }
            do {
                while !Task.isCancelled && connected && connection === client && !motion.isEmpty {
                    let delta = motion.next()
                    try await client.move(dx: delta.dx, dy: delta.dy)
                    try await Task.sleep(nanoseconds: 16_000_000)
                }
            } catch {
                motion = PointerMotion()
                if !Task.isCancelled { self.error = error.localizedDescription; log("Falha no cursor", error.localizedDescription) }
            }
        }
    }
    func clickPointer() { log("Controle", "OK / clique"); perform { try await $0.click(); self.homePresentation.dismiss(); await self.refreshState() } }
    func launch(_ app: TVApp) {
        log("Abrir app", app.title)
        perform { client in try await client.launch(app.id); self.homePresentation.dismiss(); try? await Task.sleep(nanoseconds: 600_000_000); await self.refreshState() }
    }
    func changeVolume(_ value: Double) {
        volume = min(100, max(0, value)); volumeTask?.cancel()
        volumeTask = Task {
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled, let client = connection, connected else { return }
            do { try await client.setVolume(Int(volume)); await refreshState() }
            catch { self.error = error.localizedDescription }
        }
    }
    func volumeStep(_ up: Bool) { perform { client in try await client.stepVolume(up: up); await self.refreshState() } }
    func toggleMute() { perform { client in try await client.toggleMute(current: self.muted); await self.refreshState() } }
    func input(_ input: TVInput) { log("Trocar entrada", input.label); perform { client in try await client.switchInput(input.id); self.homePresentation.dismiss(); try? await Task.sleep(nanoseconds: 500_000_000); await self.refreshState() } }
    func media(_ command: MediaCommand) { perform { try await $0.media(command) } }
    private var playbackPaused = false
    /// TVs only expose separate play and pause commands, so the keyboard alternates them.
    func togglePlayback() { playbackPaused.toggle(); log("Controle", playbackPaused ? "Pausar" : "Reproduzir"); media(playbackPaused ? .pause : .play) }
    func run(_ shortcut: RemoteShortcut) {
        switch shortcut {
        case .key(let key): press(key)
        case .ok: clickPointer()
        case .playPause: togglePlayback()
        case .volume(let up): volumeStep(up)
        case .mute: toggleMute()
        }
    }
    /// Plays a YouTube link on the TV, or opens YouTube when the TV cannot jump to a video.
    func sendLink(_ text: String) {
        guard let id = YouTubeLink.videoID(from: text) else { error = "Cole um link de vídeo do YouTube (youtube.com ou youtu.be)."; return }
        log("Mandar pra TV", "YouTube")
        perform { client in
            let exact = try await client.openYouTube(videoID: id)
            self.homePresentation.dismiss()
            self.notice = exact ? "Vídeo aberto na TV." : "YouTube aberto na TV. Esta TV não aceita abrir um vídeo específico pela rede local; procure o vídeo na TV."
            try? await Task.sleep(nanoseconds: 1_500_000_000); await self.refreshState()
        }
    }
    func pasteToTV() {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            notice = "A área de transferência do Mac não tem texto."; return
        }
        if YouTubeLink.videoID(from: text) != nil { sendLink(text) } else { sendText(text); notice = "Texto colado na TV." }
    }
    /// Media dropped on the panel: files go to the TV's player, YouTube links open in YouTube.
    func receive(_ urls: [URL]) -> Bool {
        if let file = urls.first(where: MediaDrop.playable) { mediaFile = file; castMedia(); return true }
        if let link = urls.first(where: { !$0.isFileURL && YouTubeLink.videoID(from: $0.absoluteString) != nil }) { sendLink(link.absoluteString); return true }
        notice = "Arraste uma foto, um vídeo, uma música ou um link do YouTube."
        return false
    }
    func sendText(_ text: String) { guard !text.isEmpty else { return }; perform { try await $0.insertText(text) } }
    func enterText() { perform { try await $0.sendEnter() } }
    func toggleFavorite(_ app: TVApp) {
        if favorites.contains(app.id) { favorites.remove(app.id) } else { favorites.insert(app.id) }
        UserDefaults.standard.set(Array(favorites), forKey: "tv.favorites")
    }
    func refreshPicture() async {
        guard let client = connection, connected else { return }
        picture = await client.readPicture()
    }
    private func saveUsage() {
        do { try journal.save() } catch { notice = "Não foi possível salvar o histórico de uso." }
        usageRevision += 1
    }
    private func pauseUsage() { journal.pause(); saveUsage(); powerActive = false }
    func usage(days: Int) -> [UsageTotal] {
        let since = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-Double(max(0, days - 1)) * 86400)
        return journal.totals(host: host, since: since)
    }
    var mostUsedApps: [TVApp] { usage(days: 7).compactMap { total in apps.first { $0.id == total.id } } }
    func applyPicture(_ settings: [String: Int]) {
        guard connected, let client = connection, !pictureApplying else { return }
        let allowed = Set(["backlight", "brightness", "contrast", "color"])
        let validated = settings.filter { allowed.contains($0.key) }.mapValues { min(100, max(0, $0)) }
        pictureApplying = true; error = nil
        Task {
            defer { pictureApplying = false }
            do {
                try await client.writePicture(validated)
                await refreshPicture()
                guard validated.allSatisfy({ picture[$0.key] == $0.value }) else { throw RemoteError.message("A TV não confirmou esses ajustes. Os valores exibidos foram lidos de novo.") }
                notice = "Imagem atualizada."; log("Imagem", "Ajustes de imagem aplicados.")
            } catch { await refreshPicture(); self.error = "Ajustes indisponíveis nesta conexão: \(error.localizedDescription)" }
        }
    }
    func chooseMedia() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = false; picker.allowsMultipleSelection = false
        picker.allowedContentTypes = [.movie, .audio, .image]; picker.prompt = "Selecionar"; picker.title = "Enviar mídia para a TV"
        if picker.runModal() == .OK { mediaFile = picker.url; mediaStatus = "Pronto para enviar. O arquivo vai abrir na TV." }
    }
    func castMedia() {
        guard !mediaBusy, connected, let file = mediaFile else { return }
        mediaBusy = true; error = nil
        let targetHost = host, renderer = brand.mediaRenderer
        Task {
            defer { mediaBusy = false }
            var newServer: MediaFileServer?
            do {
                let control = try await DLNATransport.discover(host: targetHost, renderer: renderer)
                let server = MediaFileServer(file: file, allowedHost: targetHost); newServer = server
                let url = try await server.start()
                _ = try await DLNATransport.command(control, action: "SetAVTransportURI", parameters: [("CurrentURI", url.absoluteString), ("CurrentURIMetaData", DLNATransport.metadata(url: url, title: file.lastPathComponent, mime: server.mime))])
                _ = try await DLNATransport.command(control, action: "Play", parameters: [("Speed", "1")])
                fileServer?.stop(); fileServer = server; transportURL = control; casting = true
                mediaStatus = "Enviado para a TV · \(file.lastPathComponent)"; log("Enviar mídia", file.lastPathComponent)
            } catch { newServer?.stop(); self.error = error.localizedDescription; mediaStatus = "Não foi possível reproduzir este arquivo." }
        }
    }
    func controlCast(_ action: String) {
        guard casting, !mediaBusy, let control = transportURL, ["Play", "Pause", "Stop"].contains(action) else { return }
        mediaBusy = true
        Task {
            defer { mediaBusy = false }
            do {
                _ = try await DLNATransport.command(control, action: action, parameters: action == "Play" ? [("Speed", "1")] : [])
                if action == "Stop" { fileServer?.stop(); fileServer = nil; casting = false; mediaStatus = "Transmissão encerrada." }
                else { mediaStatus = action == "Pause" ? "Mídia pausada na TV." : "Reproduzindo na TV." }
            } catch { self.error = error.localizedDescription }
        }
    }
    func power() {
        if connected { cancelSleepTimer(notice: nil); perform { client in try await client.turnOff(); self.disconnect(); self.notice = "TV desligada." } }
        else {
            do { try TVDiscovery.wake(mac: mac, host: host); notice = "Sinal para ligar enviado. A opção de ligar via Wi-Fi precisa estar ativa na TV." }
            catch { self.error = error.localizedDescription }
        }
    }
    func startSleepTimer(minutes: Int) {
        guard connected else { error = "Conecte-se à TV para programar o desligamento."; return }
        sleepTask?.cancel()
        let deadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepDeadline = deadline; sleepHost = host; notice = nil
        log("Timer", "Desligar \(name) em \(SleepTimer.duration(minutes))")
        // Wall-clock checks: after the Mac wakes from sleep, an expired timer fires at once.
        sleepTask = Task { [weak self] in
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            await self?.fireSleepTimer()
        }
    }
    func cancelSleepTimer(notice message: String? = "Timer cancelado.") {
        sleepTask?.cancel(); sleepTask = nil
        guard sleepDeadline != nil else { return }
        sleepDeadline = nil; log("Timer", "Cancelado")
        if let message { notice = message }
    }
    private func fireSleepTimer() async {
        sleepTask = nil; sleepDeadline = nil
        guard host == sleepHost, connected, let client = connection else {
            notice = "Timer: a TV estava desconectada e não foi desligada."; log("Timer", "TV desconectada"); return
        }
        // Samsung's power key toggles, so never send it to a TV that is already in standby.
        await refreshState()
        guard powerActive else { notice = "Timer: a TV já estava desligada."; log("Timer", "A TV já estava desligada"); return }
        do {
            try await client.turnOff()
            log("Timer", "TV desligada"); disconnect(); notice = "Timer: TV desligada."
        } catch { self.error = "O timer não conseguiu desligar a TV: \(error.localizedDescription)" }
    }
    /// Preview stores only: fills today's history so the Uso tab can be rendered with data.
    func seedPreviewUsage(_ entries: [(id: String, title: String, minutes: Double)]) {
        guard preview else { return }
        var now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600)
        for entry in entries {
            var left = entry.minutes * 60
            while left > 0 { journal.observe(host: host, appID: entry.id, title: entry.title, at: now); let step = min(30, left); now += step; left -= step }
        }
        journal.pause(at: now)
    }
    private func watchCalls() {
        if callAction == .off || preview { callMonitor.stop(); inCall = false } else { callMonitor.start() }
    }
    /// Quiets the TV while any app uses the Mac's microphone and restores it afterwards,
    /// unless the person changed that setting themselves during the call.
    private func callChanged(_ active: Bool) {
        inCall = active
        guard connected, let client = connection else { callRestore = nil; return }
        if active {
            guard callAction != .off, callRestore == nil else { return }
            let current = hasVolume ? Int(volume) : nil
            switch callAction {
            case .off: return
            case .pause:
                callRestore = (host, nil, nil, false, true)
                perform { try await $0.media(.pause) }
                notice = "Em call: TV pausada."
            case .lower:
                guard let current else { return }
                let target = CallAction.lowered(from: current)
                callRestore = (host, current, target, false, false)
                perform { try await $0.setVolume(target); await self.refreshState() }
                notice = "Em call: volume da TV em \(target)."
            case .mute:
                guard !muted else { return }
                callRestore = (host, nil, nil, true, false)
                perform { try await $0.toggleMute(current: false); await self.refreshState() }
                notice = "Em call: TV no mudo."
            }
            log("Call", "Microfone em uso no Mac")
        } else {
            guard let restore = callRestore, restore.host == host else { callRestore = nil; return }
            callRestore = nil
            log("Call", "Call encerrada")
            notice = "Call encerrada: TV de volta ao normal."
            Task {
                await refreshState()
                guard connected, connection === client else { return }
                do {
                    if restore.paused { try await client.media(.play) }
                    if let previous = restore.volume, let lowered = restore.loweredTo, Int(volume) == lowered { try await client.setVolume(previous) }
                    if restore.muted, muted { try await client.toggleMute(current: true) }
                    await refreshState()
                } catch { self.error = "Não foi possível restaurar a TV depois da call: \(error.localizedDescription)" }
            }
        }
    }
    private func checkSchedules(now: Date = Date()) {
        let minute = Int(now.timeIntervalSince1970 / 60).description
        for scene in scenes {
            guard let schedule = scene.schedule, schedule.isDue(at: now), firedSchedules[scene.id] != minute else { continue }
            firedSchedules[scene.id] = minute
            runScheduled(scene, schedule)
        }
    }
    /// Connects to the routine's TV (waking it over the network when the routine turns things on) and runs the scene.
    private func runScheduled(_ scene: TVScene, _ schedule: SceneSchedule) {
        guard let tv = savedTVs.first(where: { $0.host == schedule.tvHost }) else {
            log("Rotina", "\(scene.name): a TV desta rotina não está mais salva."); return
        }
        let turnsOff = scene.steps.contains(.powerOff)
        log("Rotina", "\(scene.name) · \(tv.name)")
        Task {
            if host != tv.host || !(connected || connecting) { switchTo(tv) }
            for second in 0..<45 {
                if connected && host == tv.host { break }
                // A routine that turns the TV off never wakes it; one that turns things on may need Wake-on-LAN.
                if turnsOff && second >= 10 { break }
                if !turnsOff && second == 2 && !tv.mac.isEmpty { try? TVDiscovery.wake(mac: tv.mac, host: tv.host) }
                if second % 10 == 9 && !connecting && host == tv.host { connect(allowFirstUseTrust: false) }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard connected, host == tv.host else {
                notice = turnsOff ? "Rotina \(scene.name): a TV \(tv.name) já estava desligada." : "Rotina \(scene.name): a TV \(tv.name) não respondeu."
                log("Rotina", notice ?? scene.name); return
            }
            // Let the app list arrive so "open app" steps find their app.
            for _ in 0..<5 where apps.isEmpty { try? await Task.sleep(nanoseconds: 1_000_000_000) }
            runScene(scene)
        }
    }
    func saveScene(_ scene: TVScene) {
        if let index = scenes.firstIndex(where: { $0.id == scene.id }) { scenes[index] = scene } else { scenes.append(scene) }
        SceneLibrary.save(scenes)
    }
    func deleteScene(_ scene: TVScene) {
        scenes.removeAll { $0.id == scene.id }
        SceneLibrary.save(scenes)
    }
    /// Runs every step in order. A step this TV cannot do is skipped and reported, never retried.
    func runScene(_ scene: TVScene) {
        guard connected, let client = connection else { error = "Conecte-se à TV para rodar uma cena."; return }
        guard runningScene == nil else { return }
        runningScene = scene.id; error = nil; notice = nil
        log("Cena", scene.name)
        Task {
            defer { runningScene = nil }
            var skipped: [String] = []
            var poweredOff = false
            for step in scene.steps {
                guard connected, connection === client else { skipped.append("o resto (TV desconectada)"); break }
                do {
                    switch step {
                    case .openApp(let id, let title):
                        guard let app = SceneLibrary.resolve(id: id, title: title, in: apps) else { skipped.append("abrir \(title) (não está nesta TV)"); continue }
                        try await client.launch(app.id); homePresentation.dismiss()
                        // Give the app time to come up before changing volume or picture.
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                    case .volume(let value):
                        try await client.setVolume(min(100, max(0, value)))
                    case .sleepTimer(let minutes):
                        startSleepTimer(minutes: minutes)
                    case .pictureMode(let mode):
                        guard capabilities.contains(.picture) else { skipped.append("modo de imagem (não disponível nesta TV)"); continue }
                        try await client.setPictureMode(mode)
                    case .powerOff:
                        // Samsung's power key toggles: only send it to a TV that is still on.
                        await refreshState()
                        if powerActive { cancelSleepTimer(notice: nil); try await client.turnOff() }
                        poweredOff = true
                    }
                    if poweredOff { break }
                } catch { skipped.append("\(SceneLibrary.label(step).lowercased()) (\(error.localizedDescription))") }
            }
            if poweredOff { disconnect() } else { await refreshState() }
            notice = skipped.isEmpty ? (poweredOff ? "Cena \(scene.name): TV desligada." : "Cena \(scene.name) pronta.") : "Cena \(scene.name) rodou, mas pulou: \(skipped.joined(separator: "; "))."
            log("Cena concluída", notice ?? scene.name)
        }
    }
    func switchTo(_ tv: SavedTV) {
        guard tv.host != host || !(connected || connecting) else { return }
        cancelSleepTimer(notice: nil)
        disconnect(); firmware = ""; webOS = ""; picture = [:]
        brand = tv.brand; host = tv.host; name = tv.name; model = tv.model; mac = tv.mac
        connect()
    }
    /// Removes a TV from this Mac: from the list and, like forgetPairing, its Keychain items.
    func remove(_ tv: SavedTV) {
        let alert = NSAlert()
        alert.messageText = "Remover \(tv.name) deste Mac?"
        alert.informativeText = "A TV sai da lista e a chave e o certificado de pareamento dela são apagados. Para usar de novo, conecte e pareie outra vez."
        alert.addButton(withTitle: "Remover"); alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if tv.host == host {
            cancelSleepTimer(notice: nil)
            disconnect(); host = ""; name = TVBrand.lg.defaultName; model = ""; mac = ""; firmware = ""; webOS = ""
            for key in ["tv.brand", "tv.host", "tv.name", "tv.model", "tv.mac"] { UserDefaults.standard.removeObject(forKey: key) }
        }
        savedTVs.removeAll { $0.host == tv.host }
        TVLibrary.save(savedTVs)
        let pairingHost = tv.host
        Task {
            do { try await Task.detached(priority: .userInitiated) { try PairingKey.delete(pairingHost) }.value; notice = "\(tv.name) foi removida deste Mac." }
            catch { self.error = "A TV saiu da lista, mas o pareamento não foi apagado: \(error.localizedDescription)" }
        }
    }
    func forgetPairing() {
        guard !host.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Esquecer o pareamento desta TV?"
        alert.informativeText = "A chave e o certificado salvos desta TV serão removidos deste Mac. Você pode conectar e parear de novo depois."
        alert.addButton(withTitle: "Esquecer pareamento"); alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let pairingHost = host
        disconnect()
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { try PairingKey.delete(pairingHost) }.value
                notice = "Pareamento removido. Conecte para parear esta TV de novo."
            } catch {
                self.error = "Não foi possível remover o pareamento: \(error.localizedDescription)"
            }
        }
    }
}
