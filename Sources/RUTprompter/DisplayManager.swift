import AppKit
import Combine

/// Окно вывода: отдельный NSWindow со своим содержимым и своим
/// зеркалированием. На внешнем (HDMI) экране — полноэкранное без рамки;
/// без второго экрана можно открыть его обычным окном для проверки.
@MainActor
final class DisplayManager: ObservableObject {

    enum Placement: Equatable {
        case none
        case external(String)   // имя экрана
        case windowed
    }

    @Published private(set) var placement: Placement = .none
    @Published private(set) var externalScreens: [String] = []
    /// Пользователь вручную закрыл вывод — не открывать сам при
    /// переподключении, пока не попросят.
    @Published var autoOpenExternal = true

    private let engine: PlaybackEngine
    private let settings: SettingsStore
    private var window: NSWindow?
    private var canvas: PrompterCanvasView?
    private var cancellables = Set<AnyCancellable>()

    init(engine: PlaybackEngine, settings: SettingsStore) {
        self.engine = engine
        self.settings = settings
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.screensChanged() }
            .store(in: &cancellables)
        settings.$theme.sink { [weak self] t in self?.canvas?.theme = t }.store(in: &cancellables)
        settings.$output.sink { [weak self] o in self?.canvas?.output = o }.store(in: &cancellables)
    }

    func start() { screensChanged() }

    /// Экран с меню-баром — основной (ноутбук). Остальные — внешние.
    static func externalScreens() -> [NSScreen] { Array(NSScreen.screens.dropFirst()) }

    private func preferredExternal() -> NSScreen? {
        let list = Self.externalScreens()
        if let name = settings.output.preferredScreenName, let s = list.first(where: { $0.localizedName == name }) { return s }
        return list.first
    }

    private func screensChanged() {
        externalScreens = Self.externalScreens().map(\.localizedName)
        switch placement {
        case .external(let name):
            if let s = Self.externalScreens().first(where: { $0.localizedName == name }) {
                place(on: s)
            } else if let s = preferredExternal() {
                place(on: s)
            } else {
                close()  // экран отключили
            }
        case .none:
            if autoOpenExternal, let s = preferredExternal() { place(on: s) }
        case .windowed:
            if autoOpenExternal, let s = preferredExternal() { place(on: s) }
        }
    }

    func showOnExternal(named name: String? = nil) {
        autoOpenExternal = true
        if let name { settings.output.preferredScreenName = name }
        if let s = preferredExternal() { place(on: s) }
    }

    func showWindowed() {
        let w = makeWindowIfNeeded(borderless: false)
        w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        w.level = .normal
        w.collectionBehavior = []
        w.title = "RUTprompter — вывод"
        let main = NSScreen.screens.first?.visibleFrame ?? .init(x: 0, y: 0, width: 1200, height: 800)
        w.setFrame(NSRect(x: main.midX - 200, y: main.midY - 300, width: 400, height: 600), display: true)
        w.orderFront(nil)
        placement = .windowed
    }

    func close() {
        window?.orderOut(nil)
        placement = .none
    }

    func userClosed() {
        autoOpenExternal = false
        close()
    }

    private func place(on screen: NSScreen) {
        let w = makeWindowIfNeeded(borderless: true)
        w.styleMask = [.borderless]
        // Выше меню-бара этого экрана, но на своём экране не мешает оператору.
        w.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        placement = .external(screen.localizedName)
    }

    private func makeWindowIfNeeded(borderless: Bool) -> NSWindow {
        if let window { return window }
        let w = OutputWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                             styleMask: borderless ? [.borderless] : [.titled, .closable, .resizable],
                             backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.backgroundColor = .black
        w.hasShadow = false
        w.onClose = { [weak self] in self?.userClosed() }
        let c = PrompterCanvasView(role: .output)
        c.theme = settings.theme
        c.output = settings.output
        c.engine = engine
        engine.register(c)
        w.contentView = c
        canvas = c
        window = w
        return w
    }
}

private final class OutputWindow: NSWindow {
    var onClose: (() -> Void)?
    override var canBecomeKey: Bool { styleMask.contains(.titled) }
    override func close() {
        onClose?()
    }
}
