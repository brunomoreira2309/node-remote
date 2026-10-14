import SwiftUI
import AppKit

private let accent = Node.cyan
private let mutedInk = Node.muted

enum RemoteTab: String, CaseIterable, Identifiable {
    case home = "Sua TV", remote = "Controle", apps = "Apps", media = "Transmitir", usage = "Atividade", info = "Imagem"
    var id: String { rawValue }
    var short: String {
        switch self {
        case .home: return "Início"
        case .remote: return "Controle"
        case .apps: return "Apps"
        case .media: return "Mídia"
        case .usage: return "Uso"
        case .info: return "Imagem"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "tv"
        case .remote: return "dpad"
        case .apps: return "square.grid.2x2"
        case .media: return "airplay.video"
        case .info: return "slider.horizontal.3"
        case .usage: return "chart.bar.xaxis"
        }
    }
}

private struct PanelButton: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? accent : Node.ink)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? accent.opacity(0.16) : Node.ice.opacity(configuration.isPressed ? 0.13 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? accent.opacity(0.45) : Node.hairline, lineWidth: 0.7))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct PanelCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Node.ice.opacity(0.065), Node.ice.opacity(0.03)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Node.hairline, lineWidth: 0.7))
    }
}

struct AppMark: View {
    let app: TVApp
    var size: CGFloat = 36
    var body: some View {
        Group {
            if let filename = app.icon,
               let url = AppResources.bundle.url(forResource: filename, withExtension: nil, subdirectory: "AppAssets"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                ZStack { RoundedRectangle(cornerRadius: 8).fill(Node.ice.opacity(0.08)); Image(systemName: "app").foregroundStyle(mutedInk) }
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.23))
            .accessibilityHidden(true)
    }
}

/// The LG mark is packaged; other brands use a neutral TV symbol instead of a logo.
private struct BrandMark: View {
    let brand: TVBrand
    var size: CGFloat = 28
    var body: some View {
        if brand == .lg { BrandImage(name: "lg", width: size, height: size) }
        else { Image(systemName: "tv").font(.system(size: size * 0.62, weight: .regular)).frame(width: size, height: size).accessibilityHidden(true) }
    }
}

private struct BrandImage: View {
    let name: String
    var width: CGFloat = 28
    var height: CGFloat = 28
    var body: some View {
        Group {
            if let url = AppResources.bundle.url(forResource: name, withExtension: "png", subdirectory: "AppAssets"), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            }
        }.frame(width: width, height: height).accessibilityHidden(true)
    }
}

@MainActor private final class RemoteViewState: ObservableObject {
    @Published var tab: RemoteTab
    @Published var settings: Bool
    init(tab: RemoteTab = .home, settings: Bool = false) { self.tab = tab; self.settings = settings }
    @Published var search: String = ""
    @Published var text: String = ""
    @Published var draftHost: String = ""
    @Published var draftName: String = ""
    @Published var draftMAC: String = ""
    @Published var draftBrand: TVBrand = .lg
    @Published var showTVs: Bool = false
    @Published var editingScene: TVScene?
    @Published var linkDraft: String = ""
    @Published var dropTargeted: Bool = false
    @Published var arrangingScenes: Bool = false
    @Published var pictureDraft: [String: Int] = [:]
    @Published var usageDays: Int = 1
    @Published var showEvents: Bool = false
    @Published var pointerTranslation: CGSize = CGSize.zero
}

struct RemoteView: View {
    @ObservedObject var store: RemoteStore
    // Command Line Tools on the macOS 27 SDK lack the SwiftUI @State macro plugin; @StateObject is not a macro.
    @StateObject private var ui: RemoteViewState
    /// The extra parameters only stage previews (`--render-preview`): an open TV picker, a pasted link, a drag in progress.
    init(store: RemoteStore, tab: RemoteTab = .home, settings: Bool = false, editing scene: TVScene? = nil,
         showTVs: Bool = false, link: String = "", dropTargeted: Bool = false) {
        self.store = store
        let state = RemoteViewState(tab: tab, settings: settings); state.editingScene = scene
        state.showTVs = showTVs; state.linkDraft = link; state.dropTargeted = dropTargeted
        _ui = StateObject(wrappedValue: state)
    }
    private var tab: RemoteTab { get { ui.tab } nonmutating set { ui.tab = newValue } }
    private var settings: Bool { get { ui.settings } nonmutating set { ui.settings = newValue } }
    private var search: String { get { ui.search } nonmutating set { ui.search = newValue } }
    private var text: String { get { ui.text } nonmutating set { ui.text = newValue } }
    private var draftHost: String { get { ui.draftHost } nonmutating set { ui.draftHost = newValue } }
    private var draftName: String { get { ui.draftName } nonmutating set { ui.draftName = newValue } }
    private var draftMAC: String { get { ui.draftMAC } nonmutating set { ui.draftMAC = newValue } }
    private var draftBrand: TVBrand { get { ui.draftBrand } nonmutating set { ui.draftBrand = newValue } }
    private var showTVs: Bool { get { ui.showTVs } nonmutating set { ui.showTVs = newValue } }
    private var pictureDraft: [String: Int] { get { ui.pictureDraft } nonmutating set { ui.pictureDraft = newValue } }
    private var usageDays: Int { get { ui.usageDays } nonmutating set { ui.usageDays = newValue } }
    private var showEvents: Bool { get { ui.showEvents } nonmutating set { ui.showEvents = newValue } }
    private var pointerTranslation: CGSize { get { ui.pointerTranslation } nonmutating set { ui.pointerTranslation = newValue } }
    private var theme: BrandTheme { BrandTheme.forApp(store.displayForegroundID, title: store.currentInput?.label ?? store.currentApp) }
    private var activeTitle: String { isPlayStation ? "PlayStation 5" : store.currentInput?.label ?? store.currentApp }
    var body: some View {
        VStack(spacing: 0) {
            header.padding(.top, 16).padding(.bottom, 16)
            if let deadline = store.sleepDeadline { sleepChip(deadline).padding(.bottom, 12) }
            if showTVs { tvPicker.padding(.bottom, 12) }
            tabs.padding(.bottom, 14)
            contentScroll
            footer.padding(.top, 10).padding(.bottom, 12)
        }.padding(.horizontal, 14).frame(width: 360)
            .background {
                ZStack(alignment: .top) {
                    Node.background
                    CircuitPattern(seed: 3).frame(height: 230).opacity(0.07)
                        .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                }
            }
            .foregroundStyle(Node.ink).preferredColorScheme(.dark)
            .font(.system(size: 12))
            .tint(accent)
            .animation(.easeOut(duration: 0.22), value: store.displayForegroundID)
            .dropDestination(for: URL.self) { urls, _ in
                guard store.connected else { store.error = "Conecte-se à TV para mandar algo pra ela."; return false }
                settings = false; ui.editingScene = nil; tab = .media
                return store.receive(urls)
            }
            .onChange(of: tab) { _, value in store.preferredPanelHeight = preferredHeight(value) }
            .onChange(of: settings) { _, value in store.preferredPanelHeight = value ? 650 : preferredHeight(tab) }
            .onChange(of: store.picture) { _, value in pictureDraft = value }
            .onChange(of: store.pictureApplying) { _, value in if !value { pictureDraft = store.picture } }
            .onAppear {
                pictureDraft = store.picture
                if store.host.isEmpty { showConnectionSettings() }
            }
    }
    private func preferredHeight(_ tab: RemoteTab) -> CGFloat { tab == .home || tab == .remote ? 740 : tab == .media ? 590 : tab == .usage ? 580 : 660 }
    private var contentScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if ui.editingScene != nil { sceneEditor }
                else if settings { settingsPanel }
                else {
                    if tab != .home { sectionTitle(tab.rawValue.uppercased()) }
                    if !store.connected { connectionPanel }
                    tabContent
                }
                feedback
            }.padding(.bottom, 12)
        }.scrollIndicators(.hidden)
    }
    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .home: homePanel
        case .remote: remotePanel
        case .apps: appsPanel
        case .media: mediaPanel
        case .info: infoPanel
        case .usage: usagePanel
        }
    }
    @ViewBuilder private var feedback: some View {
        if let error = store.error {
            PanelCard {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                    Text(error).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { store.error = nil } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).help("Fechar mensagem")
                }
            }
        } else if let notice = store.notice {
            Text(notice).font(.system(size: 11)).foregroundStyle(mutedInk).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(brand: store.brand, size: 26).foregroundStyle(Node.ink)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Node.raised))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Node.hairline, lineWidth: 0.7))
            Button { showTVs.toggle() } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(store.name).font(.system(size: 17, weight: .semibold)).tracking(-0.4).lineLimit(1)
                        Image(systemName: showTVs ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(mutedInk)
                    }
                    HStack(spacing: 5) {
                        Circle().fill(store.connected ? accent : store.connecting ? .orange : Node.faint).frame(width: 5, height: 5)
                        Text(store.brand.platform).font(.system(size: 10, weight: .medium)).foregroundStyle(mutedInk)
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help("Trocar de TV").accessibilityLabel("\(store.name). Trocar de TV")
            Spacer()
            Menu {
                Button("Atualizar dados da TV") { Task { await store.refresh(); await store.refreshPicture() } }
                Button(store.connected ? "Desconectar" : "Conectar") {
                    if store.connected { store.disconnect() }
                    else if store.host.isEmpty { showConnectionSettings() }
                    else { store.connect() }
                }
                Divider()
                Button("Sair do \(AppInfo.name)") { NSApplication.shared.terminate(nil) }
            } label: { Image(systemName: "ellipsis").frame(width: 24, height: 30).foregroundStyle(mutedInk) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            Menu {
                if store.connected {
                    Button("Desligar a TV agora") { store.power() }
                    Menu("Desligar em…") {
                        ForEach(SleepTimer.presets, id: \.self) { minutes in Button(SleepTimer.duration(minutes)) { store.startSleepTimer(minutes: minutes) } }
                    }
                } else { Button("Ligar a TV pelo Wi-Fi") { store.power() }.disabled(store.mac.isEmpty) }
                if store.sleepDeadline != nil { Divider(); Button("Cancelar timer") { store.cancelSleepTimer() } }
            } label: {
                Image(systemName: "power").font(.system(size: 15, weight: .semibold)).foregroundStyle(store.connected ? accent : mutedInk)
                    .frame(width: 34, height: 34).background(Circle().fill(store.connected ? accent.opacity(0.12) : Node.raised))
                    .overlay(Circle().strokeBorder(store.connected ? accent.opacity(0.5) : Node.hairline, lineWidth: 0.8))
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Energia da TV")
        }
    }
    private func sleepChip(_ deadline: Date) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill").foregroundStyle(accent)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("A TV desliga em \(SleepTimer.clock(deadline.timeIntervalSince(context.date)))").monospacedDigit().fontWeight(.medium)
            }
            Spacer()
            Menu {
                ForEach(SleepTimer.presets, id: \.self) { minutes in Button("Mudar para \(SleepTimer.duration(minutes))") { store.startSleepTimer(minutes: minutes) } }
            } label: { Text("Mudar").font(.system(size: 10)).foregroundStyle(mutedInk) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            Button { store.cancelSleepTimer() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(mutedInk).help("Cancelar timer").accessibilityLabel("Cancelar timer")
        }.padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 11).fill(accent.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(accent.opacity(0.3), lineWidth: 0.7))
    }
    private var tvPicker: some View {
        PanelCard {
            VStack(spacing: 4) {
                ForEach(store.savedTVs) { tv in
                    let current = tv.host == store.host
                    Button { showTVs = false; store.switchTo(tv) } label: {
                        HStack(spacing: 10) {
                            BrandMark(brand: tv.brand, size: 22).foregroundStyle(current ? accent : mutedInk)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tv.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text([tv.brand.displayName, tv.model].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(mutedInk).lineLimit(1)
                            }
                            Spacer()
                            if current {
                                Text(store.connected ? "CONECTADA" : store.connecting ? "CONECTANDO" : "ATUAL").font(.system(size: 7, weight: .bold)).tracking(0.5).foregroundStyle(accent)
                            }
                        }.padding(.horizontal, 6).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 9).fill(current ? accent.opacity(0.12) : Color.clear))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(current ? .isSelected : [])
                }
                if store.savedTVs.isEmpty { Text("Nenhuma TV salva ainda.").foregroundStyle(mutedInk).padding(.vertical, 6) }
                Divider().padding(.vertical, 2)
                Button { showTVs = false; showConnectionSettings(newTV: true) } label: {
                    Label("Adicionar outra TV", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading).padding(6).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(accent)
            }
        }
    }
    private var tabs: some View {
        HStack(spacing: 3) {
            ForEach(RemoteTab.allCases) { item in
                let selected = tab == item && !settings
                Button { tab = item; settings = false; ui.editingScene = nil } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol).font(.system(size: 14, weight: .medium)).frame(height: 16)
                        Text(item.short).font(.system(size: 8.5, weight: selected ? .semibold : .medium))
                    }
                    .foregroundStyle(selected ? accent : mutedInk)
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? accent.opacity(0.14) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? accent.opacity(0.35) : .clear, lineWidth: 0.7))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).help(item.rawValue).accessibilityLabel(item.rawValue)
            }
        }.padding(4).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Node.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Node.hairline, lineWidth: 0.7))
            .animation(.easeOut(duration: 0.18), value: tab)
    }
    private func sectionTitle(_ title: String) -> some View { NodeRule(title: title, busy: store.connecting) }
    private var homePanel: some View {
        VStack(spacing: 12) {
            nowPlayingCard
            scenesCard
            audioCard
            if !store.pinnedApps.isEmpty {
                PanelCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Favoritos", systemImage: "star").font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Button { tab = .apps } label: { Text("Ver todos").font(.system(size: 10)).foregroundStyle(mutedInk) }.buttonStyle(.plain)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 13) {
                            ForEach(store.pinnedApps) { app in
                                Button { store.launch(app) } label: {
                                    VStack(spacing: 8) { AppMark(app: app, size: 34); Text(app.title).font(.system(size: 9, weight: .medium)).foregroundStyle(Node.ice.opacity(0.7)).lineLimit(1) }
                                        .frame(maxWidth: .infinity).padding(.vertical, 4).contentShape(Rectangle())
                                }.buttonStyle(.plain).disabled(!store.connected).help("Abrir \(app.title) na TV")
                            }
                        }
                    }
                }
            }
            if !store.inputs.isEmpty {
                PanelCard {
                    VStack(spacing: 7) {
                        HStack { Label("Entradas", systemImage: "cable.connector").font(.system(size: 12, weight: .semibold)); Spacer() }
                        ForEach(store.orderedInputs.filter(\.connected)) { input in inputRow(input) }
                    }
                }
            }
            if !store.mostUsedApps.isEmpty {
                HStack(spacing: 8) {
                    Text("Mais usados").font(.system(size: 10)).foregroundStyle(mutedInk)
                    Spacer()
                    ForEach(Array(store.mostUsedApps.prefix(4))) { app in
                        Button { store.launch(app) } label: { AppMark(app: app, size: 25) }.buttonStyle(.plain).help("Abrir \(app.title)").disabled(!store.connected)
                    }
                    Button { tab = .usage } label: { Image(systemName: "chevron.right").foregroundStyle(mutedInk) }.buttonStyle(.plain).help("Ver atividade")
                }.padding(.horizontal, 4)
            }
        }
    }
    private var scenesCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Cenas", systemImage: "sparkles").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button { ui.arrangingScenes.toggle() } label: { Text(ui.arrangingScenes ? "Concluir" : "Editar").font(.system(size: 10)) }
                        .buttonStyle(.plain).foregroundStyle(ui.arrangingScenes ? accent : mutedInk)
                    Button { ui.editingScene = TVScene(name: "", symbol: "sparkles", steps: []) } label: { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)) }
                        .buttonStyle(.plain).foregroundStyle(mutedInk).help("Nova cena").accessibilityLabel("Nova cena")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(store.scenes) { scene in
                        Button { if ui.arrangingScenes { ui.editingScene = scene } else { store.runScene(scene) } } label: {
                            VStack(spacing: 6) {
                                if store.runningScene == scene.id { ProgressView().controlSize(.small).frame(height: 19) }
                                else {
                                    Image(systemName: ui.arrangingScenes ? "pencil" : scene.symbol).font(.system(size: 17)).frame(height: 19)
                                        .overlay(alignment: .topTrailing) {
                                            if scene.schedule?.enabled == true && !ui.arrangingScenes {
                                                Image(systemName: "clock.fill").font(.system(size: 8)).foregroundStyle(accent).offset(x: 9, y: -4)
                                            }
                                        }
                                }
                                Text(scene.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                            }.frame(maxWidth: .infinity).frame(height: 54)
                        }.buttonStyle(PanelButton(selected: store.runningScene == scene.id))
                            .disabled(!ui.arrangingScenes && (!store.connected || store.runningScene != nil))
                            .help(ui.arrangingScenes ? "Editar \(scene.name)" : ([scene.schedule.flatMap { $0.enabled ? "Agendada: " + $0.summary : nil }].compactMap { $0 } + scene.steps.map(SceneLibrary.label)).joined(separator: " · "))
                    }
                }
                if store.scenes.isEmpty { Text("Crie uma cena com o +.").font(.system(size: 10)).foregroundStyle(mutedInk) }
            }
        }
    }
    private var sceneEditor: some View {
        let scene = Binding<TVScene>(get: { ui.editingScene ?? TVScene(name: "", symbol: "sparkles", steps: []) }, set: { ui.editingScene = $0 })
        let existing = store.scenes.contains { $0.id == scene.wrappedValue.id }
        let name = scene.wrappedValue.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle(existing ? "EDITAR CENA" : "NOVA CENA")
            PanelCard {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Nome da cena", text: scene.name).nodeField()
                    HStack(spacing: 5) {
                        ForEach(SceneLibrary.symbols, id: \.self) { symbol in
                            Button { scene.wrappedValue.symbol = symbol } label: { Image(systemName: symbol).font(.system(size: 13)).frame(width: 31, height: 28) }
                                .buttonStyle(PanelButton(selected: scene.wrappedValue.symbol == symbol)).accessibilityLabel(symbol)
                        }
                    }
                }
            }
            PanelCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Passos, em ordem").fontWeight(.semibold)
                    ForEach(Array(scene.wrappedValue.steps.enumerated()), id: \.offset) { index, step in sceneStepRow(scene, index, step) }
                    if scene.wrappedValue.steps.isEmpty { Text("Adicione o que a cena deve fazer.").font(.system(size: 10)).foregroundStyle(mutedInk) }
                    Menu {
                        Menu("Abrir app") {
                            ForEach(store.shortcuts) { app in Button(app.title) { scene.wrappedValue.steps.append(.openApp(id: app.id, title: app.title)) } }
                            if store.apps.isEmpty { Text("Conecte-se à TV para ver os apps") }
                        }
                        Button("Ajustar volume") { scene.wrappedValue.steps.append(.volume(Int(store.hasVolume ? store.volume : 20))) }
                        Menu("Timer para desligar") {
                            ForEach(SleepTimer.presets, id: \.self) { minutes in Button(SleepTimer.duration(minutes)) { scene.wrappedValue.steps.append(.sleepTimer(minutes: minutes)) } }
                        }
                        Menu("Modo de imagem (LG)") {
                            ForEach(SceneLibrary.pictureModes, id: \.id) { mode in Button(mode.label) { scene.wrappedValue.steps.append(.pictureMode(mode.id)) } }
                        }
                        Button("Desligar a TV") { scene.wrappedValue.steps.append(.powerOff) }
                    } label: { Label("Adicionar passo", systemImage: "plus.circle.fill").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(accent) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    Text("Uma cena feita numa TV também roda na outra. O que a TV não suportar é pulado e avisado.").font(.system(size: 10)).foregroundStyle(mutedInk).fixedSize(horizontal: false, vertical: true)
                }
            }
            sceneScheduleCard(scene)
            HStack {
                if existing {
                    Button("Excluir cena") { store.deleteScene(scene.wrappedValue); ui.editingScene = nil }.buttonStyle(NodeSecondaryButton(tint: Color(red: 1, green: 0.45, blue: 0.45)))
                }
                Spacer()
                Button("Cancelar") { ui.editingScene = nil }.buttonStyle(NodeSecondaryButton())
                Button("Salvar") { var saved = scene.wrappedValue; saved.name = name; store.saveScene(saved); ui.editingScene = nil }
                    .buttonStyle(NodePrimaryButton()).disabled(name.isEmpty || scene.wrappedValue.steps.isEmpty)
            }.font(.system(size: 11))
        }
    }
    private func sceneScheduleCard(_ scene: Binding<TVScene>) -> some View {
        let enabled = Binding<Bool>(
            get: { scene.wrappedValue.schedule?.enabled == true },
            set: { on in
                if var schedule = scene.wrappedValue.schedule { schedule.enabled = on; scene.wrappedValue.schedule = schedule }
                else if on { scene.wrappedValue.schedule = SceneSchedule(hour: 7, minute: 0, weekdays: [2, 3, 4, 5, 6], tvHost: store.host) }
            })
        let time = Binding<Date>(
            get: { Calendar.current.date(bySettingHour: scene.wrappedValue.schedule?.hour ?? 7, minute: scene.wrappedValue.schedule?.minute ?? 0, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                scene.wrappedValue.schedule?.hour = parts.hour ?? 7; scene.wrappedValue.schedule?.minute = parts.minute ?? 0
            })
        return PanelCard {
            VStack(alignment: .leading, spacing: 11) {
                Toggle(isOn: enabled) { Label("Rodar automaticamente", systemImage: "clock").fontWeight(.semibold) }.toggleStyle(.switch).tint(accent)
                if let schedule = scene.wrappedValue.schedule, schedule.enabled {
                    HStack {
                        Text("Horário").foregroundStyle(mutedInk)
                        Spacer()
                        DatePicker("Horário", selection: time, displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.field)
                    }
                    HStack(spacing: 5) {
                        ForEach(1...7, id: \.self) { day in
                            let on = schedule.weekdays.contains(day)
                            Button {
                                var days = Set(schedule.weekdays)
                                if on { days.remove(day) } else { days.insert(day) }
                                scene.wrappedValue.schedule?.weekdays = days.sorted()
                            } label: { Text(SceneSchedule.dayLetters[day - 1]).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 28) }
                                .buttonStyle(PanelButton(selected: on)).accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                        }
                    }
                    if store.savedTVs.count > 1 {
                        NodeSegmented(options: store.savedTVs.map { ($0.host, $0.name) }, selection: Binding(
                            get: { scene.wrappedValue.schedule?.tvHost ?? store.host }, set: { scene.wrappedValue.schedule?.tvHost = $0 }))
                    }
                    Text(schedule.weekdays.isEmpty ? "Escolha pelo menos um dia." : "Roda \(schedule.summary) na \(store.savedTVs.first { $0.host == schedule.tvHost }?.name ?? "TV"). O Mac precisa estar ligado e o app aberto. Se a cena liga algo, o app tenta ligar a TV pelo Wi-Fi antes.")
                        .font(.system(size: 10)).foregroundStyle(mutedInk).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private func sceneStepRow(_ scene: Binding<TVScene>, _ index: Int, _ step: SceneStep) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)").font(.system(size: 10, weight: .bold)).foregroundStyle(mutedInk).frame(width: 12)
            if case let .volume(value) = step {
                Text("Volume").frame(width: 46, alignment: .leading)
                Slider(value: Binding(get: { Double(value) }, set: { scene.wrappedValue.steps[index] = .volume(Int($0.rounded())) }), in: 0...100).accessibilityLabel("Volume da cena")
                Text("\(value)").monospacedDigit().frame(width: 24, alignment: .trailing)
            } else {
                Text(SceneLibrary.label(step)).lineLimit(1)
                Spacer()
            }
            Button { scene.wrappedValue.steps.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up").font(.system(size: 10)) }
                .buttonStyle(.plain).foregroundStyle(mutedInk).disabled(index == 0).help("Subir este passo")
            Button { scene.wrappedValue.steps.remove(at: index) } label: { Image(systemName: "trash").font(.system(size: 10)) }
                .buttonStyle(.plain).foregroundStyle(mutedInk).help("Remover este passo")
        }.font(.system(size: 11))
    }
    private var isPlayStation: Bool {
        store.currentInput?.label.localizedCaseInsensitiveContains("PS5") == true || store.currentInput?.label.localizedCaseInsensitiveContains("PlayStation") == true
    }
    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            // The TV mockup; its screen (273 × 141 points at this size) shows what the TV reports.
            ZStack {
                Ellipse().fill(accent.opacity(store.connected ? 0.3 : 0.08)).frame(width: 250, height: 110).blur(radius: 40).offset(y: 10)
                BrandImage(name: "tv-hero", width: 312, height: 175)
                ZStack {
                    CircuitPattern(seed: 11).opacity(store.connected ? 0.16 : 0.07)
                    RadialGradient(colors: [accent.opacity(store.connected ? 0.22 : 0.05), .clear], center: .center, startRadius: 2, endRadius: 120)
                    VStack(spacing: 9) {
                        Group {
                            if isPlayStation { BrandImage(name: "playstation", width: 44, height: 44) }
                            else if !store.homeRequested, let app = store.apps.first(where: { $0.id == store.foregroundID }) { AppMark(app: app, size: 44) }
                            else if store.currentInput?.label.localizedCaseInsensitiveContains("Chromecast") == true { BrandImage(name: "googlecast", width: 38, height: 38) }
                            else { BrandMark(brand: store.brand, size: 38).foregroundStyle(Node.ink) }
                        }.shadow(color: .black.opacity(0.45), radius: 10, y: 4)
                        Text(store.connected ? activeTitle : store.brand.platform).font(.system(size: 15, weight: .semibold)).tracking(-0.3).lineLimit(1)
                            .shadow(color: accent.opacity(0.35), radius: 10)
                    }
                }.frame(width: 272, height: 140).clipped().offset(y: -7)
            }.frame(height: 178).frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                Circle().fill(store.connected ? accent : mutedInk).frame(width: 5, height: 5)
                Text(store.connected ? (store.homeRequested ? "INÍCIO ABERTO PELO MAC" : "NA TELA AGORA") : "SUA TV, NO SEU MAC").font(.system(size: 8.5, weight: .semibold)).tracking(1.4).foregroundStyle(mutedInk)
                Spacer()
                if let input = store.currentInput { Text(input.id.replacingOccurrences(of: "_", with: " ")).font(.system(size: 9, weight: .semibold)).foregroundStyle(accent) }
            }.padding(.horizontal, 4)
            Text(theme.tagline).font(.system(size: 11.5)).foregroundStyle(Node.ice.opacity(0.7)).padding(.horizontal, 4)
        }
    }
    private var audioCard: some View {
        PanelCard {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(mutedInk)
                    Text("Áudio da TV").fontWeight(.semibold)
                    Spacer()
                    Text(store.hasVolume ? "\(Int(store.volume))" : "—").font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(accent).contentTransition(.numericText())
                }
                HStack(spacing: 9) {
                    Button { store.toggleMute() } label: { Image(systemName: store.muted ? "speaker.slash.fill" : "speaker.fill").foregroundStyle(store.muted ? accent : mutedInk).frame(width: 20) }.buttonStyle(.plain).help(store.muted ? "Ativar som" : "Silenciar")
                    Slider(value: Binding(get: { store.volume }, set: store.changeVolume), in: 0...100).tint(accent).accessibilityLabel("Volume da TV")
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 11)).foregroundStyle(mutedInk)
                }.disabled(!store.connected || !store.hasVolume)
                HStack {
                    Text(store.muted ? "Sem som" : "Alto-falantes da TV").font(.system(size: 10)).foregroundStyle(mutedInk)
                    Spacer()
                    Button { store.volumeStep(false) } label: { Image(systemName: "minus").frame(width: 25, height: 22) }.buttonStyle(PanelButton()).help("Diminuir volume")
                    Button { store.volumeStep(true) } label: { Image(systemName: "plus").frame(width: 25, height: 22) }.buttonStyle(PanelButton()).help("Aumentar volume")
                }.disabled(!store.connected)
            }
        }
    }
    private var remotePanel: some View {
        VStack(spacing: 12) {
            PanelCard {
                VStack(spacing: 16) {
                    HStack {
                        Text(store.currentApp).lineLimit(1).fontWeight(.semibold)
                        Spacer()
                        Circle().fill(store.pointerReady ? accent : Color.orange).frame(width: 5, height: 5)
                        Text(store.pointerReady ? "Controle pronto" : "Conectando controle").font(.system(size: 9)).foregroundStyle(mutedInk)
                    }
                    HStack(spacing: 15) {
                        VStack(spacing: 12) { remoteButton("house", store.capabilities.contains(.closeApps) ? "Fechar o app e ir para o início" : "Ir para o início", .home).disabled(store.navigatingHome); remoteButton("arrow.uturn.backward", "Voltar", .back) }
                        ZStack {
                            Circle().fill(RadialGradient(colors: [Node.ice.opacity(0.09), Node.ice.opacity(0.03)], center: .center, startRadius: 20, endRadius: 70))
                                .overlay(Circle().strokeBorder(LinearGradient(colors: [accent.opacity(0.35), Node.hairline], startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
                            VStack { remoteDirection("chevron.up", .up, "Para cima"); Spacer(); remoteDirection("chevron.down", .down, "Para baixo") }.padding(6)
                            HStack { remoteDirection("chevron.left", .left, "Para a esquerda"); Spacer(); remoteDirection("chevron.right", .right, "Para a direita") }.padding(6)
                            Button { store.clickPointer() } label: {
                                Text("OK").font(.system(size: 13, weight: .bold)).foregroundStyle(Node.abyss).frame(width: 50, height: 50)
                                    .background(Circle().fill(LinearGradient(colors: [accent, accent.opacity(0.78)], startPoint: .top, endPoint: .bottom)))
                                    .shadow(color: accent.opacity(0.45), radius: 12)
                            }.buttonStyle(.plain).help("Confirmar")
                        }.frame(width: 138, height: 138)
                        VStack(spacing: 12) { remoteButton("gearshape", "Configurações da TV", .menu); remoteButton("xmark", "Sair da tela", .exit) }
                    }.frame(maxWidth: .infinity)
                    HStack(spacing: 7) {
                        mediaButton("backward.end.fill", "Retroceder", .rewind)
                        mediaButton("play.fill", "Reproduzir", .play)
                        mediaButton("pause.fill", "Pausar", .pause)
                        mediaButton("stop.fill", "Parar", .stop)
                        mediaButton("forward.end.fill", "Avançar", .fastForward)
                    }
                }.disabled(!store.connected)
            }
            if store.capabilities.contains(.pointer) { PanelCard {
                VStack(spacing: 9) {
                    HStack { Label("Cursor da TV", systemImage: "cursorarrow").fontWeight(.semibold); Spacer(); Text("Arraste · toque para clicar").font(.system(size: 9)).foregroundStyle(mutedInk) }
                    RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.065)).overlay(Image(systemName: "hand.draw").font(.system(size: 25, weight: .light)).foregroundStyle(accent.opacity(0.7)))
                        .frame(height: 85).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                            let delta = CGSize(width: value.translation.width - pointerTranslation.width, height: value.translation.height - pointerTranslation.height)
                            pointerTranslation = value.translation
                            store.movePointer(dx: Int(delta.width * 1.8), dy: Int(delta.height * 1.8))
                        }.onEnded { _ in pointerTranslation = .zero })
                        .simultaneousGesture(TapGesture().onEnded { store.clickPointer() })
                        .accessibilityLabel("Touchpad da TV")
                }.disabled(!store.connected)
            } }
            audioCard
            HStack(spacing: 8) {
                Button { store.press(.channelDown) } label: { Label("Canal −", systemImage: "chevron.down").frame(maxWidth: .infinity).frame(height: 32) }.buttonStyle(PanelButton())
                Button { store.press(.channelUp) } label: { Label("Canal +", systemImage: "chevron.up").frame(maxWidth: .infinity).frame(height: 32) }.buttonStyle(PanelButton())
            }.disabled(!store.connected)
            PanelCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Teclado", systemImage: "keyboard").fontWeight(.semibold)
                    TextField("Digite no campo aberto na TV", text: $ui.text).nodeField().onSubmit(sendText)
                    HStack {
                        Text("Abra um campo de texto na TV.").font(.system(size: 10)).foregroundStyle(mutedInk)
                        Spacer()
                        Button("Enviar", action: sendText).buttonStyle(NodePrimaryButton()).disabled(text.isEmpty)
                        Button { store.pasteToTV() } label: { Image(systemName: "doc.on.clipboard") }.help("Colar na TV o texto copiado no Mac")
                        Button { store.enterText() } label: { Image(systemName: "return") }.help("Confirmar texto na TV")
                    }
                }.disabled(!store.connected)
            }
            if store.capabilities.contains(.inputList) { inputsPanel }
            else if store.capabilities.contains(.sourceKey) {
                Button { store.press(.source) } label: { Label("Fonte · trocar entrada", systemImage: "cable.connector").frame(maxWidth: .infinity).frame(height: 32) }
                    .buttonStyle(PanelButton()).disabled(!store.connected).help("Abrir o menu de fontes da TV")
            }
            PanelCard {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Atalhos do teclado", systemImage: "command").fontWeight(.semibold)
                    Text("Setas navegam · ↩ OK · ⌫ voltar · espaço play/pausa · + − volume · M mudo · H início · \(GlobalHotKey.label) abre o painel de qualquer lugar").font(.system(size: 10)).foregroundStyle(mutedInk).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Os controles de reprodução dependem do app aberto. A navegação controla a TV; o PS5 usa o próprio controle.").font(.system(size: 10)).foregroundStyle(mutedInk)
        }
    }
    private func sendText() { store.sendText(text); text = "" }
    private func remoteDirection(_ symbol: String, _ command: RemoteKey, _ title: String) -> some View {
        Button { store.press(command) } label: { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).frame(width: 29, height: 29).contentShape(Rectangle()) }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
    private func remoteButton(_ symbol: String, _ title: String, _ command: RemoteKey) -> some View {
        Button { store.press(command) } label: { Image(systemName: symbol).font(.system(size: 15)).frame(width: 43, height: 42) }.buttonStyle(PanelButton()).help(title).accessibilityLabel(title)
    }
    private func mediaButton(_ symbol: String, _ title: String, _ command: MediaCommand) -> some View {
        Button { store.media(command) } label: { Image(systemName: symbol).font(.system(size: 11)).frame(maxWidth: .infinity).frame(height: 30) }.buttonStyle(PanelButton()).help(title).accessibilityLabel(title)
    }
    private var appsPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(mutedInk)
                TextField("Buscar em \(store.apps.count) apps", text: $ui.search).textFieldStyle(.plain)
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(mutedInk) }.buttonStyle(.plain) }
            }.padding(11).background(RoundedRectangle(cornerRadius: 11).fill(Node.ice.opacity(0.06)))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
                ForEach(store.shortcuts.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { app in
                    let color = BrandTheme.forApp(app.id, title: app.title).color
                    VStack(spacing: 8) {
                        HStack {
                            Spacer()
                            Button { store.toggleFavorite(app) } label: {
                                Image(systemName: store.favorites.contains(app.id) ? "star.fill" : "star").font(.system(size: 9)).foregroundStyle(store.favorites.contains(app.id) ? color : mutedInk)
                            }.buttonStyle(.plain).help("Favoritar \(app.title)").accessibilityLabel("Favoritar \(app.title)")
                        }
                        Button { store.launch(app) } label: {
                            VStack(spacing: 10) {
                                AppMark(app: app, size: 43).shadow(color: color.opacity(0.18), radius: 9)
                                Text(app.title).font(.system(size: 10, weight: .medium)).lineLimit(2).frame(height: 26)
                            }.frame(maxWidth: .infinity).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!store.connected).help("Abrir \(app.title) na TV")
                        if store.displayForegroundID == app.id { Text("NA TELA").font(.system(size: 7, weight: .bold)).tracking(0.9).foregroundStyle(accent) }
                        else { Color.clear.frame(height: 9) }
                    }.padding(10).background(RoundedRectangle(cornerRadius: 13).fill(LinearGradient(colors: [color.opacity(0.17), Node.ice.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(store.displayForegroundID == app.id ? accent.opacity(0.8) : color.opacity(0.13), lineWidth: store.displayForegroundID == app.id ? 1.2 : 0.7))
                }
            }
            Text("Clique em um app para abri-lo na TV. Use a estrela para favoritar.").font(.system(size: 10)).foregroundStyle(mutedInk)
        }
    }
    private func active(_ input: TVInput) -> Bool { store.displayForegroundID == input.appID }
    private func inputRow(_ input: TVInput) -> some View {
        Button { store.input(input) } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(input.label.localizedCaseInsensitiveContains("PS5") ? Color(red: 0.02, green: 0.17, blue: 0.44) : Node.ice.opacity(0.055))
                    if input.label.localizedCaseInsensitiveContains("PS5") || input.label.localizedCaseInsensitiveContains("PlayStation") { BrandImage(name: "playstation", width: 24, height: 24) }
                    else if input.label.localizedCaseInsensitiveContains("Chromecast") { BrandImage(name: "googlecast", width: 22, height: 22) }
                    else { Image(systemName: "cable.connector").font(.system(size: 15)).foregroundStyle(mutedInk) }
                }.frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(input.label).font(.system(size: 12, weight: .semibold))
                    Text(input.id.replacingOccurrences(of: "_", with: " ") + " · " + (active(input) ? "Ativa" : input.connected ? "Conectada" : "Sem aparelho")).font(.system(size: 10)).foregroundStyle(mutedInk)
                }
                Spacer()
                if active(input) {
                    Text("ATIVO").font(.system(size: 7, weight: .bold)).tracking(0.5).foregroundStyle(accent)
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(accent)
                } else { Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(mutedInk) }
            }.padding(.horizontal, 9).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10).fill(active(input) ? accent.opacity(0.13) : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active(input) ? accent.opacity(0.32) : Color.clear, lineWidth: 0.7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!store.connected).help("Mudar a TV para \(input.label)")
            .accessibilityAddTraits(active(input) ? .isSelected : [])
    }
    private var inputsPanel: some View {
        VStack(spacing: 12) {
            PanelCard {
                VStack(spacing: 10) {
                    ForEach(store.orderedInputs) { input in inputRow(input) }
                    if store.inputs.isEmpty { Text("As entradas aparecem depois de conectar.").foregroundStyle(mutedInk).padding(.vertical, 15) }
                }
            }
            Text("Escolha uma entrada para mudar o que a TV mostra.").font(.system(size: 10)).foregroundStyle(mutedInk)
        }
    }
    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.08))
                VStack(spacing: 8) {
                    Image(systemName: "sun.max").font(.system(size: 29, weight: .light)).foregroundStyle(accent)
                    Text("Sua imagem, do seu jeito").font(.system(size: 17, weight: .semibold)).tracking(-0.3)
                    Text("Ajuste os valores e aplique quando quiser.").font(.system(size: 10)).foregroundStyle(mutedInk)
                }.padding(.vertical, 20)
            }
            if !store.capabilities.contains(.picture) {
                PanelCard { Text("Os ajustes de imagem não estão disponíveis pela rede nesta TV. Use o menu de configurações da própria TV.").foregroundStyle(mutedInk).fixedSize(horizontal: false, vertical: true) }
            } else { PanelCard {
                VStack(spacing: 19) {
                    ForEach([("backlight", "Luz de fundo", "sun.max"), ("brightness", "Brilho", "light.max"), ("contrast", "Contraste", "circle.lefthalf.filled"), ("color", "Cor", "paintpalette")], id: \.0) { key, title, symbol in
                        if store.picture[key] != nil {
                            VStack(spacing: 9) {
                                HStack { Label(title, systemImage: symbol).foregroundStyle(Node.ice.opacity(0.8)); Spacer(); Text("\(pictureDraft[key] ?? store.picture[key] ?? 0)").monospacedDigit().foregroundStyle(accent) }
                                Slider(value: Binding(get: { Double(pictureDraft[key] ?? store.picture[key] ?? 0) }, set: { pictureDraft[key] = Int($0.rounded()) }), in: 0...100).accessibilityLabel(title)
                            }
                        }
                    }
                    if store.picture.isEmpty { Text("Conecte-se à TV para ler as configurações.").foregroundStyle(mutedInk) }
                    HStack {
                        Button("Restaurar valores") { pictureDraft = store.picture }.buttonStyle(NodeSecondaryButton())
                        Spacer()
                        Button(store.pictureApplying ? "Aplicando…" : "Aplicar na TV") { store.applyPicture(pictureDraft) }.buttonStyle(NodePrimaryButton())
                            .disabled(!store.connected || store.picture.isEmpty || pictureDraft == store.picture || store.pictureApplying)
                    }.font(.system(size: 10))
                }
            } }
            Text("Os ajustes disponíveis dependem das permissões da TV. Os valores são lidos de novo depois de aplicar.").font(.system(size: 10)).foregroundStyle(mutedInk)
        }
    }
    private var usagePanel: some View {
        let totals = store.usage(days: usageDays)
        let total = totals.reduce(0) { $0 + $1.seconds }
        return VStack(alignment: .leading, spacing: 14) {
            NodeSegmented(options: [(1, "Hoje"), (7, "7 dias"), (30, "30 dias")], selection: $ui.usageDays)
            VStack(alignment: .leading, spacing: 7) {
                Text("TEMPO DE TELA").font(.system(size: 8, weight: .bold)).tracking(1.2).foregroundStyle(mutedInk)
                Text(duration(total)).font(.system(size: 38, weight: .medium, design: .rounded)).tracking(-1).foregroundStyle(accent)
                Text("Apps e entradas observados pelo seu Mac").font(.system(size: 10)).foregroundStyle(mutedInk)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.08)))
            PanelCard {
                VStack(spacing: 17) {
                    ForEach(totals) { item in
                        let color = BrandTheme.forApp(item.id, title: item.title).color
                        VStack(spacing: 8) {
                            HStack(spacing: 9) {
                                if let app = store.apps.first(where: { $0.id == item.id }) { AppMark(app: app, size: 26) }
                                else if item.title.localizedCaseInsensitiveContains("PS5") { BrandImage(name: "playstation", width: 26, height: 26) }
                                else { Image(systemName: "tv").foregroundStyle(color).frame(width: 26) }
                                Text(item.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Spacer(); Text(duration(item.seconds)).font(.system(size: 10)).foregroundStyle(mutedInk).monospacedDigit()
                            }
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) { Capsule().fill(Node.ice.opacity(0.04)); Capsule().fill(color).frame(width: geometry.size.width * CGFloat(item.seconds / max(total, 1))) }
                            }.frame(height: 4)
                        }
                    }
                    if totals.isEmpty { VStack(spacing: 9) { Image(systemName: "chart.bar.xaxis").font(.system(size: 26)).foregroundStyle(accent); Text("Seu histórico começa aqui").fontWeight(.medium); Text("O primeiro registro aparece na próxima leitura da TV.").font(.system(size: 10)).foregroundStyle(mutedInk) }.frame(maxWidth: .infinity).padding(.vertical, 25) }
                }
            }
            Text("O histórico local começa agora. Registra o app ou a entrada informados pela TV enquanto o Mac está ativo e conectado; períodos em repouso ou offline ficam de fora.").font(.system(size: 10)).foregroundStyle(mutedInk)
        }
    }
    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes == 0 { return "\(Int(seconds)) s" }
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
    private var sendToTVCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "paperplane.fill").font(.system(size: 20)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mandar pra TV").font(.system(size: 14, weight: .semibold))
                        Text("Links do YouTube, fotos, vídeos e músicas do Mac").font(.system(size: 10)).foregroundStyle(mutedInk)
                    }
                }
                HStack(spacing: 7) {
                    TextField("Cole um link do YouTube", text: $ui.linkDraft).nodeField().onSubmit { store.sendLink(ui.linkDraft); ui.linkDraft = "" }
                    Button("Abrir") { store.sendLink(ui.linkDraft); ui.linkDraft = "" }.buttonStyle(NodePrimaryButton()).disabled(ui.linkDraft.isEmpty)
                }
                Button { store.pasteToTV() } label: { Label("Colar o que copiei no Mac", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity) }
                    .buttonStyle(NodeSecondaryButton())
                VStack(spacing: 7) {
                    Image(systemName: "arrow.down.to.line").font(.system(size: 18, weight: .medium)).foregroundStyle(ui.dropTargeted ? Node.abyss : accent)
                    Text(ui.dropTargeted ? "Solte para mandar pra TV" : "Arraste aqui um arquivo ou link").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ui.dropTargeted ? Node.abyss : Node.ink)
                }
                .frame(maxWidth: .infinity).frame(height: 78)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ui.dropTargeted ? accent : accent.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(accent.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                .dropDestination(for: URL.self) { urls, _ in store.receive(urls) } isTargeted: { ui.dropTargeted = $0 }
                .animation(.easeOut(duration: 0.15), value: ui.dropTargeted)
                if !store.capabilities.contains(.videoLinks) {
                    Text("Nesta TV, links do YouTube abrem o app, mas não o vídeo: a \(store.brand.displayName) não aceita isso pela rede local.").font(.system(size: 10)).foregroundStyle(mutedInk).fixedSize(horizontal: false, vertical: true)
                }
            }.disabled(!store.connected)
        }
    }
    private var mediaPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            sendToTVCard
            PanelCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "airplay.video").font(.system(size: 26, weight: .light)).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 3) { Text("Seu Mac na tela grande").font(.system(size: 14, weight: .semibold)); Text("Espelhamento de tela com AirPlay").font(.system(size: 10)).foregroundStyle(mutedInk) }
                    }
                    Text("Na Central de Controle do Mac, abra Espelhamento de Tela e escolha “\(store.name)”. Você também pode usar a TV como segundo monitor nos ajustes de Telas.").font(.system(size: 11)).foregroundStyle(mutedInk).fixedSize(horizontal: false, vertical: true)
                    Button { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!) } label: { Label("Abrir ajustes de Telas", systemImage: "arrow.up.right") }.buttonStyle(.plain).foregroundStyle(accent)
                }
            }
            PanelCard {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Enviar um arquivo", systemImage: "play.tv").font(.system(size: 14, weight: .semibold))
                    if let file = store.mediaFile {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.richtext").font(.system(size: 23)).foregroundStyle(accent)
                            VStack(alignment: .leading, spacing: 4) { Text(file.lastPathComponent).fontWeight(.medium).lineLimit(2); Text(file.pathExtension.uppercased()).font(.system(size: 9)).foregroundStyle(mutedInk) }
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.08)))
                    }
                    Text(store.mediaStatus).font(.system(size: 10)).foregroundStyle(mutedInk).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Escolher arquivo") { store.chooseMedia() }.buttonStyle(NodeSecondaryButton()).disabled(store.mediaBusy)
                        Spacer()
                        Button(store.mediaBusy ? "Enviando…" : "Reproduzir na TV") { store.castMedia() }.buttonStyle(NodePrimaryButton()).disabled(!store.connected || store.mediaFile == nil || store.mediaBusy)
                    }.font(.system(size: 10))
                    if store.casting {
                        HStack(spacing: 8) {
                            ForEach([("play.fill", "Play", "Reproduzir"), ("pause.fill", "Pause", "Pausar"), ("stop.fill", "Stop", "Parar transmissão")], id: \.1) { symbol, action, title in
                                Button { store.controlCast(action) } label: { Image(systemName: symbol).frame(maxWidth: .infinity).frame(height: 32) }.buttonStyle(PanelButton()).help(title).accessibilityLabel(title)
                            }
                        }.disabled(store.mediaBusy)
                    }
                }
            }
            Text("O arquivo abre na TV quando você clica em Reproduzir na TV. A compatibilidade depende do formato e do codec; tente primeiro H.264 MP4, MP3 ou JPEG. Mantenha o Mac ativo durante a transmissão.").font(.system(size: 10)).foregroundStyle(mutedInk)
        }
    }
    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(mutedInk); Spacer(); Text(value).fontWeight(.medium).textSelection(.enabled) }.font(.system(size: 11))
    }
    private var logsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conexões e ações do \(AppInfo.name) salvas neste Mac. Os logs internos da TV exigem o modo desenvolvedor.").font(.system(size: 11)).foregroundStyle(mutedInk)
            PanelCard {
                LazyVStack(alignment: .leading, spacing: 13) {
                    ForEach(store.events.filter { $0.title != "Leitura" }) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(event.title).fontWeight(.semibold); Spacer(); Text(event.date, style: .time).foregroundStyle(mutedInk).monospacedDigit() }
                            Text(event.detail).font(.system(size: 10)).foregroundStyle(mutedInk).lineLimit(3).textSelection(.enabled)
                        }.font(.system(size: 11))
                    }
                    if store.events.isEmpty { Text("Nenhum evento ainda.").foregroundStyle(mutedInk).padding(.vertical, 12) }
                }
            }
        }
    }
    private var connectionPanel: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(store.status, systemImage: store.pairing ? "checkmark.shield" : "wifi").fontWeight(.semibold)
                Text(store.pairing ? store.brand.pairingHint : "O Mac e a TV precisam estar na mesma rede.").font(.system(size: 11)).foregroundStyle(mutedInk)
                Button(store.connecting ? "Cancelar" : "Conectar à TV") {
                    if store.connecting { store.disconnect() }
                    else if store.host.isEmpty { showConnectionSettings() }
                    else { store.connect() }
                }.buttonStyle(NodePrimaryButton())
            }
        }
    }
    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelCard {
                HStack(spacing: 13) {
                    BrandMark(brand: store.brand, size: 38)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.model.isEmpty ? store.brand.defaultName : "\(store.brand.displayName) \(store.model)").font(.system(size: 14, weight: .semibold))
                        Text([store.webOS, store.firmware].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(mutedInk)
                    }
                    Spacer()
                }
            }
            if !store.savedTVs.isEmpty {
                sectionTitle("SUAS TVS")
                PanelCard {
                    VStack(spacing: 8) {
                        ForEach(store.savedTVs) { tv in
                            HStack(spacing: 9) {
                                BrandMark(brand: tv.brand, size: 20).foregroundStyle(mutedInk)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tv.name).fontWeight(.medium).lineLimit(1)
                                    Text("\(tv.brand.displayName) · \(tv.host)").font(.system(size: 10)).foregroundStyle(mutedInk)
                                }
                                Spacer()
                                Button { store.remove(tv) } label: { Image(systemName: "trash").font(.system(size: 11)) }
                                    .buttonStyle(.plain).foregroundStyle(mutedInk).help("Remover \(tv.name) deste Mac").disabled(store.connecting)
                            }
                        }
                        Button { showConnectionSettings(newTV: true) } label: { Label("Adicionar outra TV", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading) }
                            .buttonStyle(.plain).foregroundStyle(accent)
                    }
                }
            }
            sectionTitle("AUTOMAÇÕES")
            PanelCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Quando o Mac entrar em call", systemImage: "phone.and.waveform").fontWeight(.semibold)
                    NodeSegmented(options: CallAction.allCases.map { ($0, $0.label) }, selection: $store.callAction)
                    Text("Detecta quando algum app (Meet, Zoom, FaceTime…) usa o microfone do Mac e volta a TV ao normal quando a call acaba. O app nunca ouve nada.")
                        .font(.system(size: 10)).foregroundStyle(mutedInk).fixedSize(horizontal: false, vertical: true)
                    if store.inCall && store.callAction != .off { Label("Em call agora", systemImage: "waveform").font(.system(size: 10, weight: .semibold)).foregroundStyle(accent) }
                }
            }
            sectionTitle("CONEXÃO")
            PanelCard {
                VStack(alignment: .leading, spacing: 11) {
                    Text("Sua TV").fontWeight(.semibold)
                    NodeSegmented(options: TVBrand.allCases.map { ($0, $0.displayName) }, selection: $ui.draftBrand)
                    TextField("Nome", text: $ui.draftName).nodeField()
                    TextField("Endereço IP da TV", text: $ui.draftHost).nodeField()
                    TextField("Endereço MAC do Wi-Fi (para ligar a TV)", text: $ui.draftMAC).nodeField()
                    Text("Opcional: o endereço MAC só é necessário para ligar a TV.").font(.system(size: 10)).foregroundStyle(mutedInk)
                    Button("Salvar e conectar") {
                        store.disconnect(); store.model = ""; store.firmware = ""; store.webOS = ""
                        store.brand = draftBrand
                        store.host = draftHost.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.name = draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? draftBrand.defaultName : draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.mac = draftMAC.trimmingCharacters(in: .whitespacesAndNewlines); store.connect(); settings = false
                    }.buttonStyle(NodePrimaryButton()).disabled(!TVHost.local(draftHost.trimmingCharacters(in: .whitespacesAndNewlines)) || store.connecting)
                    if !store.host.isEmpty {
                        Button("Esquecer pareamento") { store.forgetPairing() }.buttonStyle(NodeSecondaryButton()).disabled(store.connecting)
                    }
                }
            }
            PanelCard {
                VStack(alignment: .leading, spacing: 11) {
                    Button(store.discovering ? "Procurando TVs…" : "Procurar TVs na rede") { store.discover() }.buttonStyle(NodeSecondaryButton()).disabled(store.discovering)
                    ForEach(store.devices) { device in
                        Button { store.select(device); settings = false } label: { HStack { Text(device.name); Text(device.brand.displayName).font(.system(size: 9)).foregroundStyle(mutedInk); Spacer(); Text(device.host).foregroundStyle(mutedInk) } }.buttonStyle(.plain)
                    }
                    Text("Para ligar a TV pelo Mac, ative a opção de ligar via Wi-Fi nas configurações da TV.").font(.system(size: 11)).foregroundStyle(mutedInk)
                }
            }
            DisclosureGroup("Histórico de eventos", isExpanded: $ui.showEvents) { logsPanel.padding(.top, 10) }.font(.system(size: 11))
        }
    }
    private func showConnectionSettings(newTV: Bool = false) {
        if newTV { draftHost = ""; draftName = ""; draftMAC = ""; draftBrand = store.brand }
        else { draftHost = store.host; draftName = store.name; draftMAC = store.mac; draftBrand = store.brand }
        settings = true
    }
    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(store.connected ? accent : store.connecting ? .orange : mutedInk).frame(width: 5, height: 5)
                .shadow(color: store.connected ? accent.opacity(0.8) : .clear, radius: 3)
            Text(store.status).font(.system(size: 10)).foregroundStyle(mutedInk)
            Spacer()
            Text(AppInfo.name.uppercased()).font(.system(size: 8, weight: .semibold)).tracking(1.6).foregroundStyle(Node.faint)
            Button {
                if !settings { draftHost = store.host; draftName = store.name; draftMAC = store.mac; draftBrand = store.brand }
                ui.editingScene = nil
                settings.toggle()
            } label: { Image(systemName: settings ? "xmark" : "slider.horizontal.3").font(.system(size: 12)).foregroundStyle(mutedInk).frame(width: 24, height: 22) }.buttonStyle(.plain).help("Configurações do app")
        }
    }
}
