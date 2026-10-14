import AppKit
import SwiftUI

/// `--render-preview DIR [--scale N] [--film]`: draws the panel with demo data into PNGs for design review
/// (`--film` adds the states of the product film). It never reads pairing keys, contacts a TV or saves preferences.
enum PreviewRenderer {
    @MainActor static func run(directory: URL, scale: Int = 1, film: Bool = false) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let catalog = (try? AppResources.bundle.url(forResource: "app-catalog", withExtension: "json").map {
            try JSONDecoder().decode([TVApp].self, from: Data(contentsOf: $0))
        }) ?? []
        func demo(_ brand: TVBrand) -> RemoteStore {
            let store = RemoteStore(preview: true)
            store.brand = brand; store.name = brand == .lg ? "Quarto" : "Sala"; store.host = "192.0.2.10"
            store.model = brand == .lg ? "OLED65C5" : "UN43T5300AGXZD"; store.webOS = brand == .lg ? "webOS 25" : "Tizen"
            store.connected = true; store.pointerReady = true; store.hasVolume = true; store.volume = 24
            store.apps = ["netflix", "youtube.leanback.v4", "amazon", "com.disney.disneyplus-prod", "globoplaywebos", "spotify-beehive", "com.apple.appletv", "com.wbd.stream"]
                .compactMap { id in catalog.first { $0.id == id } }
            store.foregroundID = "netflix"; store.foregroundName = "Netflix"
            store.inputs = brand == .lg ? [TVInput(id: "HDMI_1", label: "PS5", connected: true, appID: "com.webos.app.hdmi1"), TVInput(id: "HDMI_2", label: "Chromecast", connected: true, appID: "com.webos.app.hdmi2")] : []
            store.savedTVs = [SavedTV(brand: .samsung, host: "192.0.2.10", name: "Sala", model: "UN43T5300AGXZD", mac: ""), SavedTV(brand: .lg, host: "192.0.2.11", name: "Quarto", model: "OLED65C5", mac: "")]
            store.picture = brand == .lg ? ["backlight": 80, "brightness": 50, "contrast": 85, "color": 55] : [:]
            return store
        }
        let samsung = demo(.samsung)
        samsung.sleepDeadline = Date().addingTimeInterval(27 * 60 + 41)
        let routine = TVScene(name: "Bom dia", symbol: "sparkles", steps: [.openApp(id: "youtube.leanback.v4", title: "YouTube"), .volume(15)],
                              schedule: SceneSchedule(hour: 7, minute: 0, weekdays: [2, 3, 4, 5, 6], tvHost: "192.0.2.10"))
        struct Extra { var showTVs = false; var link = ""; var drop = false }
        var extras: [String: Extra] = [:]
        var shots: [(String, RemoteStore, RemoteTab, Bool)] = [
            ("1-home", samsung, .home, false), ("2-remote", demo(.lg), .remote, false), ("3-apps", samsung, .apps, false),
            ("4-picture", demo(.lg), .info, false), ("5-media", samsung, .media, false), ("6-usage", samsung, .usage, false),
            ("7-settings", samsung, .home, true), ("8-routine", samsung, .home, false),
        ]
        if film {
            // One real panel per step of the film: the volume stepping down in a call, the sleep timer counting.
            func state(_ volume: Double, app: Bool, sleep: TimeInterval? = nil) -> RemoteStore {
                let store = demo(.samsung); store.volume = volume
                if !app { store.foregroundID = ""; store.foregroundName = "" }
                if let sleep { store.sleepDeadline = Date().addingTimeInterval(sleep) }
                return store
            }
            shots += [("film-idle", state(24, app: false), .home, false), ("film-cinema", state(25, app: true), .home, false),
                      ("film-remote", state(25, app: true), .remote, false)]
            shots += [21, 16, 12, 9, 8].map { ("film-vol-\($0)", state(Double($0), app: true), .home, false) }
            shots += [1800, 1334, 903, 461, 72, 3].map { ("film-sleep-\($0)", state(10, app: true, sleep: TimeInterval($0) - 0.5), .home, false) }
            func on(_ id: String, _ store: RemoteStore) -> RemoteStore { store.foregroundID = id; store.foregroundName = store.apps.first { $0.id == id }?.title ?? id; return store }
            func lg(_ store: RemoteStore) -> RemoteStore { store.brand = .lg; store.name = "Quarto"; store.host = "192.0.2.11"; store.model = "OLED65C5"; store.webOS = "webOS 25"; return store }
            shots += [("film-picker", state(24, app: false), .home, false), ("film-youtube", on("youtube.leanback.v4", state(15, app: true)), .home, false),
                      ("film-apps", on("youtube.leanback.v4", state(15, app: true)), .apps, false), ("film-apps-disney", on("com.disney.disneyplus-prod", state(15, app: true)), .apps, false),
                      ("film-remote-lg", lg(on("com.disney.disneyplus-prod", demo(.lg))), .remote, false),
                      ("film-media", lg(on("com.disney.disneyplus-prod", demo(.lg))), .media, false), ("film-media-link", lg(on("com.disney.disneyplus-prod", demo(.lg))), .media, false),
                      ("film-media-drop", lg(on("com.disney.disneyplus-prod", demo(.lg))), .media, false)]
            extras["film-picker"] = Extra(showTVs: true)
            extras["film-media-link"] = Extra(link: "https://youtu.be/jNQXAC9IVRw")
            extras["film-media-drop"] = Extra(drop: true)
            for (i, light) in [80, 62, 45].enumerated() {
                let store = lg(on("com.disney.disneyplus-prod", demo(.lg))); store.picture = ["backlight": light, "brightness": 50 - i * 4, "contrast": 85, "color": 55 + i * 6]
                shots.append(("film-picture-\(i)", store, .info, false))
            }
            let usage = state(24, app: true)
            usage.seedPreviewUsage([("netflix", "Netflix", 96), ("youtube.leanback.v4", "YouTube", 64), ("com.disney.disneyplus-prod", "Disney+", 41), ("globoplaywebos", "Globoplay", 23), ("spotify-beehive", "Spotify", 12)])
            shots.append(("film-usage", usage, .usage, false))
            shots.append(("film-routine", state(24, app: false), .home, false))
            // Same-TV continuity for the tab clicks: Samsung media states, an LG home before the Imagem tab, LG screen time after it.
            shots += [("film-media-s", on("youtube.leanback.v4", state(15, app: true)), .media, false), ("film-media-link-s", on("youtube.leanback.v4", state(15, app: true)), .media, false),
                      ("film-media-drop-s", on("youtube.leanback.v4", state(15, app: true)), .media, false), ("film-lg-home", lg(on("youtube.leanback.v4", demo(.lg))), .home, false)]
            extras["film-media-link-s"] = Extra(link: "https://youtu.be/jNQXAC9IVRw")
            extras["film-media-drop-s"] = Extra(drop: true)
            let usageLG = lg(on("youtube.leanback.v4", demo(.lg)))
            usageLG.seedPreviewUsage([("netflix", "Netflix", 96), ("youtube.leanback.v4", "YouTube", 64), ("com.disney.disneyplus-prod", "Disney+", 41), ("globoplaywebos", "Globoplay", 23), ("spotify-beehive", "Spotify", 12)])
            shots.append(("film-usage-lg", usageLG, .usage, false))
        }
        for (name, store, tab, settings) in shots {
            let extra = extras[name] ?? Extra()
            let view = RemoteView(store: store, tab: tab, settings: settings, editing: name.hasSuffix("routine") ? routine : nil,
                                  showTVs: extra.showTVs, link: extra.link, dropTargeted: extra.drop).frame(width: 360, height: 820).preferredColorScheme(.dark)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 360, height: 820)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua); window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 360 * scale, pixelsHigh: 820 * scale, bitsPerSample: 8, samplesPerPixel: 4,
                                                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
        }
        print("PREVIEW: \(shots.count) imagens em \(directory.path)")
    }
}
