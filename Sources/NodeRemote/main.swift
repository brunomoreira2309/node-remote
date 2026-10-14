import AppKit
import SwiftUI
import Combine

final class RemotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct PanelArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - 11, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX - 3, y: rect.minY + 2), control: CGPoint(x: rect.midX - 6, y: rect.maxY - 6))
        path.addQuadCurve(to: CGPoint(x: rect.midX + 3, y: rect.minY + 2), control: CGPoint(x: rect.midX, y: rect.minY - 2))
        path.addQuadCurve(to: CGPoint(x: rect.midX + 11, y: rect.maxY), control: CGPoint(x: rect.midX + 6, y: rect.maxY - 6))
        path.closeSubpath()
        return path
    }
}

private struct PanelShell: View {
    @ObservedObject var store: RemoteStore
    let height: CGFloat
    let arrowX: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            PanelArrow().fill(Color(red: 0.085, green: 0.095, blue: 0.10))
                .frame(width: 24, height: 11).frame(width: 360, alignment: .leading).offset(x: arrowX - 12)
            RemoteView(store: store).frame(width: 360, height: height - 11)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.13), lineWidth: 0.7))
        }.frame(width: 360, height: height).preferredColorScheme(.dark)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = RemoteStore()
    var statusItem: NSStatusItem!
    let panel = RemotePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var host: NSHostingController<PanelShell>?
    var clickMonitor: Any?
    var keyMonitor: Any?
    private var sizeSubscription: AnyCancellable?
    private var outsideHide: TimeInterval = 0
    private var hotKey: GlobalHotKey?
    private var sleepSubscription: AnyCancellable?
    private var sleepTicker: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.image = Self.menuBarIcon() ?? NSImage(systemSymbolName: "tv", accessibilityDescription: AppInfo.name)
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.target = self; statusItem.button?.action = #selector(toggle)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .popUpMenu; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        sizeSubscription = store.$preferredPanelHeight.dropFirst().removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { if self?.panel.isVisible == true { self?.show() } }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            let location = NSEvent.mouseLocation
            DispatchQueue.main.async {
                guard let self, self.panel.isVisible else { return }
                // A click on our own menu bar icon belongs to toggle(); closing here would make it reopen.
                if let icon = self.statusItem.button?.window?.frame, icon.contains(location) { return }
                self.panel.orderOut(nil); self.outsideHide = ProcessInfo.processInfo.systemUptime
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.keyCode == 53 { self.panel.orderOut(nil); return nil }
            // Typing in a field (TV keyboard, app search, settings) keeps every key.
            guard event.window === self.panel, !(self.panel.firstResponder is NSTextView), self.store.connected,
                  let shortcut = RemoteShortcut.action(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags) else { return event }
            self.store.run(shortcut)
            return nil
        }
        hotKey = GlobalHotKey { [weak self] in self?.toggle() }
        sleepSubscription = store.$sleepDeadline.sink { [weak self] deadline in
            DispatchQueue.main.async { self?.showSleepTimer(deadline) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !CommandLine.arguments.contains("--background") { self.show() }
            if !self.store.host.isEmpty { self.store.connect(allowFirstUseTrust: false) }
        }
    }
    /// A brand-neutral remote control, drawn as vectors. As a template image it takes
    /// the menu bar's own color in light and dark mode.
    private static func menuBarIcon() -> NSImage? {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            let body = NSBezierPath(roundedRect: NSRect(x: 5, y: 0.75, width: 8, height: 16.5), xRadius: 3.6, yRadius: 3.6)
            body.lineWidth = 1.5; body.stroke()
            let pad = NSBezierPath(ovalIn: NSRect(x: 6.6, y: 9.4, width: 4.8, height: 4.8))
            pad.lineWidth = 1.2; pad.stroke()
            NSBezierPath(ovalIn: NSRect(x: 8.25, y: 11.05, width: 1.5, height: 1.5)).fill()
            for y in [6.0, 3.6] as [CGFloat] {
                NSBezierPath(ovalIn: NSRect(x: 6.9, y: y, width: 1.5, height: 1.5)).fill()
                NSBezierPath(ovalIn: NSRect(x: 9.6, y: y, width: 1.5, height: 1.5)).fill()
            }
            return true
        }
        image.accessibilityDescription = AppInfo.name
        return image
    }
    /// Minutes left beside the menu bar icon while a sleep timer runs.
    private func showSleepTimer(_ deadline: Date?) {
        sleepTicker?.invalidate(); sleepTicker = nil
        guard let deadline else { statusItem.button?.title = ""; return }
        let update = { [weak self] in self?.statusItem.button?.title = " " + SleepTimer.menuBar(deadline.timeIntervalSinceNow) }
        update()
        sleepTicker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in update() }
    }
    @objc func toggle() {
        if panel.isVisible { panel.orderOut(nil) }
        // The same click may have just closed the panel as an outside click; keep it closed.
        else if ProcessInfo.processInfo.systemUptime - outsideHide > 0.3 { show() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func show() {
        guard let button = statusItem.button, let anchorWindow = button.window else { return }
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = anchorWindow.screen ?? NSScreen.main!
        let visible = screen.visibleFrame
        let top = min(anchor.minY - 3, visible.maxY - 3)
        let height = min(store.preferredPanelHeight, max(300, top - visible.minY - 12))
        let x = min(max(anchor.midX - 180, visible.minX + 8), visible.maxX - 368)
        let root = PanelShell(store: store, height: height, arrowX: min(342, max(18, anchor.midX - x)))
        if let host { host.rootView = root }
        else { let controller = NSHostingController(rootView: root); host = controller; panel.contentViewController = controller }
        // Use screen coordinates explicitly so AppKit cannot flip the panel above the menu bar.
        panel.setFrame(NSRect(x: x, y: top - height, width: 360, height: height), display: true)
        let opening = !panel.isVisible
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // Open without a focused text field so the keyboard controls the TV right away.
        if opening { panel.makeFirstResponder(nil) }
    }
    func applicationWillTerminate(_ notification: Notification) {
        store.disconnect()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}

let app = NSApplication.shared
if CommandLine.arguments.contains("--help") {
    print("""
    Node Remote — controle remoto na barra de menu do macOS para TVs LG webOS e Samsung Tizen

    Abra o app normalmente para encontrar ou configurar a TV nas configurações.
    --background   Inicia sem mostrar o painel.
    --self-check   Roda testes offline sem acessar a TV nem o pareamento salvo.
    --diagnose --host <ip-da-tv> [--brand lg|samsung] [--report <arquivo>] [--check-home] [--trust-new-tv]
                   Roda um diagnóstico só de leitura. Uma TV nova precisa de aprovação
                   explícita do certificado com --trust-new-tv e do pareamento na TV.
                   Os relatórios contêm informações dos aparelhos da rede local.
    """)
} else if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
    let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    MainActor.assumeIsolated {
        let arguments = CommandLine.arguments
        let scale = arguments.firstIndex(of: "--scale").flatMap { arguments.count > $0 + 1 ? Int(arguments[$0 + 1]) : nil } ?? 1
        do { try PreviewRenderer.run(directory: directory, scale: max(1, min(4, scale)), film: arguments.contains("--film")); exit(0) } catch { print("ERRO: \(error.localizedDescription)"); exit(1) }
    }
} else if CommandLine.arguments.contains("--self-check") {
    Task { do { try await FeatureChecks.run(); exit(0) } catch { print("FAIL: \(error)"); exit(1) } }
    RunLoop.main.run()
} else if CommandLine.arguments.contains("--diagnose") {
    Task { @MainActor in
        guard let hostIndex = CommandLine.arguments.firstIndex(of: "--host"), CommandLine.arguments.count > hostIndex + 1,
              TVHost.local(CommandLine.arguments[hostIndex + 1]) else {
            print("ERRO: use --diagnose --host <ip-da-tv> com o IPv4 local da TV."); exit(2)
        }
        let host = CommandLine.arguments[hostIndex + 1]
        let brand = CommandLine.arguments.firstIndex(of: "--brand").flatMap { CommandLine.arguments.count > $0 + 1 ? TVBrand(rawValue: CommandLine.arguments[$0 + 1]) : nil } ?? .lg
        if brand == .samsung {
            let client = SamsungConnection(host: host)
            client.onPairing = { print("PAREAMENTO: \(brand.pairingHint)"); fflush(stdout) }
            client.onCertificateTrust = { host, fingerprint in await ConnectionTrustPrompt.confirm(host: host, fingerprint: fingerprint, brand: brand) }
            do {
                try await client.connect(allowFirstUseTrust: CommandLine.arguments.contains("--trust-new-tv"))
                print("PAREADO: conexão autorizada; pareamento salvo nas Chaves.")
                let details = await client.details()
                let apps = try await client.listApps()
                let state = await client.readState()
                let report: [String: Any] = [
                    "host": host, "brand": brand.rawValue, "model": details.model ?? "", "firmware": details.firmware,
                    "apps": apps.map { ["id": $0.id, "title": $0.title] },
                    "state": ["powerActive": state.powerActive as Any, "volume": state.volume as Any, "muted": state.muted as Any, "foreground": state.foregroundID as Any],
                ]
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                if let index = CommandLine.arguments.firstIndex(of: "--report"), CommandLine.arguments.count > index + 1 { try data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
                print("DIAGNÓSTICO: \(details.model ?? "modelo desconhecido"); \(apps.count) apps encontrados; volume \(state.volume.map { String(Int($0)) } ?? "indisponível"); app na tela: \(state.foregroundTitle ?? "nenhum").")
                client.close(); exit(0)
            } catch { print("ERRO: \(error.localizedDescription)"); client.close(); exit(1) }
        }
        let client = WebOSConnection(host: host)
        client.onPairing = { print("PAREAMENTO: aceite o LG Remote App na TV."); fflush(stdout) }
        client.onCertificateTrust = { host, fingerprint in await ConnectionTrustPrompt.confirm(host: host, fingerprint: fingerprint, brand: .lg) }
        do {
            try await client.connect(allowFirstUseTrust: CommandLine.arguments.contains("--trust-new-tv"))
            print("PAREADO: conexão autorizada; pareamento salvo nas Chaves.")
            let system = try? await client.request("system/getSystemInfo")
            let volume = try await client.request("audio/getVolume")
            let apps = try await client.request("com.webos.applicationManager/listApps")
            let inputs = try? await client.request("tv/getExternalInputList")
            let foreground = try? await client.request("com.webos.applicationManager/getForegroundAppInfo")
            var homeStates: [String: Any] = [:]
            if CommandLine.arguments.contains("--check-home") {
                for id in ["com.webos.app.home", "com.webos.app.fullhome", foreground?["appId"] as? String ?? ""] where !id.isEmpty {
                    do { homeStates[id] = try await client.request("system.launcher/getAppState", ["id": id]) }
                    catch { homeStates[id] = ["error": error.localizedDescription] }
                }
            }
            var pointerError: String?
            do { try await client.checkPointer() } catch { pointerError = error.localizedDescription }
            let report: [String: Any] = ["host": host, "system": system ?? [:], "volume": volume, "apps": apps, "inputs": inputs ?? [:], "foreground": foreground ?? [:], "homeStates": homeStates, "pointerAvailable": pointerError == nil, "pointerError": pointerError ?? ""]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            if let index = CommandLine.arguments.firstIndex(of: "--report"), CommandLine.arguments.count > index + 1 { try data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            print("DIAGNÓSTICO: dados da TV lidos; canal de navegação \(pointerError == nil ? "pronto" : "indisponível").")
            client.close(); exit(0)
        } catch { print("ERRO: \(error.localizedDescription)"); client.close(); exit(1) }
    }
    RunLoop.main.run()
} else {
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
