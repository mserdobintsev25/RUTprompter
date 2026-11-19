import AppKit
import Combine
import PrompterCore
import SwiftUI
import UniformTypeIdentifiers

/// Текст скрипта + автосохранение.
@MainActor
final class ScriptModel: ObservableObject {
    @Published var text: String
    private var cancellables = Set<AnyCancellable>()

    init(engine: PlaybackEngine, text: String) {
        self.text = text
        $text.removeDuplicates()
            .sink { [weak engine] t in engine?.setText(t) }
            .store(in: &cancellables)
        $text.removeDuplicates()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { ScriptStorage.save($0) }
            .store(in: &cancellables)
    }
}

/// Состояние интерфейса, которое меняют и меню, и SwiftUI.
@MainActor
final class UIState: ObservableObject {
    @Published var page: AppPage = .script
    @Published var editUnlocked = false
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsStore!
    private var engine: PlaybackEngine!
    private var script: ScriptModel!
    private var display: DisplayManager!
    private let ui = UIState()
    private var operatorWindow: NSWindow?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = SettingsStore()
        let text = ScriptStorage.load() ?? ScriptStorage.sample
        engine = PlaybackEngine(settings: settings, text: text)
        script = ScriptModel(engine: engine, text: text)
        display = DisplayManager(engine: engine, settings: settings)

        applyAppearance()
        buildMenu()
        showOperatorWindow()
        display.start()
        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        ScriptStorage.save(script.text)
    }

    private func showOperatorWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 780),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "RUTprompter"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.minSize = NSSize(width: 980, height: 640)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("OperatorWindow")
        window.contentView = NSHostingView(rootView: OperatorView(
            engine: engine, settings: settings, display: display, script: script, ui: ui,
            openFile: { [weak self] in self?.openScript(nil) },
            saveFile: { [weak self] in self?.saveScript(nil) }))
        if !window.setFrameUsingName("OperatorWindow") { window.center() }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        operatorWindow = window
    }

    // MARK: Горячие клавиши (без ⌘ — когда не идёт набор текста)

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        guard mods.isEmpty else { return false }
        guard event.window === operatorWindow || event.window?.contentView is PrompterCanvasView else { return false }
        if let tv = event.window?.firstResponder as? NSTextView, tv.isEditable { return false }
        if event.window?.firstResponder is NSTextField { return false }

        switch event.keyCode {
        case 49: engine.togglePlay(); return true                  // пробел
        case 126: engine.moveLines(-1); return true                // ↑
        case 125: engine.moveLines(1); return true                 // ↓
        case 123: engine.jumpToSection(offset: -1); return true    // ←
        case 124: engine.jumpToSection(offset: 1); return true     // →
        case 115: engine.rewind(); return true                     // Home
        case 53: engine.pause(); return true                       // Esc
        default: break
        }
        switch event.charactersIgnoringModifiers {
        case "+", "=": engine.adjustSpeed(10); return true
        case "-", "_": engine.adjustSpeed(-10); return true
        case "m", "M", "ь", "Ь": settings.output.mirrorHorizontal.toggle(); return true
        case "]", "ъ": changeFont(4); return true
        case "[", "х": changeFont(-4); return true
        default: return false
        }
    }

    private func changeFont(_ delta: Double) {
        settings.theme.fontSize = min(max(settings.theme.fontSize + delta, 20), 160)
    }

    // MARK: Меню

    private func buildMenu() {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "О RUTprompter", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(item("Настройки…", #selector(openSettings(_:)), ","))
        app.addItem(.separator())
        app.addItem(withTitle: "Скрыть RUTprompter", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Завершить RUTprompter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(app, "RUTprompter"))

        let file = NSMenu(title: "Файл")
        file.addItem(item("Открыть скрипт…", #selector(openScript(_:)), "o"))
        file.addItem(item("Сохранить скрипт как…", #selector(saveScript(_:)), "s"))
        file.addItem(item("Вставить пример", #selector(insertSample(_:)), ""))
        main.addItem(submenu(file, "Файл"))

        let edit = NSMenu(title: "Правка")
        edit.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Выбрать всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu(edit, "Правка"))

        let play = NSMenu(title: "Суфлёр")
        play.addItem(item("Старт / пауза", #selector(togglePlay(_:)), "\r"))
        play.addItem(item("Стоп (завершить дубль)", #selector(stopPlay(_:)), "."))
        play.addItem(item("В начало", #selector(rewind(_:)), "0"))
        play.addItem(.separator())
        play.addItem(item("Предыдущий раздел", #selector(prevSection(_:)), "["))
        play.addItem(item("Следующий раздел", #selector(nextSection(_:)), "]"))
        play.addItem(.separator())
        play.addItem(item("Крупнее шрифт", #selector(fontBigger(_:)), "="))
        play.addItem(item("Мельче шрифт", #selector(fontSmaller(_:)), "-"))
        let mirror = item("Зеркалить второй экран", #selector(toggleMirror(_:)), "m")
        mirror.keyEquivalentModifierMask = [.command, .shift]
        play.addItem(mirror)
        play.addItem(.separator())
        play.addItem(item("Дубли…", #selector(openTakes(_:)), "y"))
        main.addItem(submenu(play, "Суфлёр"))

        let win = NSMenu(title: "Окно")
        win.addItem(item("Вывод на внешний экран", #selector(outputExternal(_:)), "e"))
        win.addItem(item("Вывод в отдельном окне (проверка)", #selector(outputWindowed(_:)), ""))
        win.addItem(item("Закрыть вывод", #selector(outputClose(_:)), ""))
        win.addItem(.separator())
        let themeMenu = NSMenu(title: "Тема окна")
        for (i, t) in ["Как в системе", "Светлая", "Тёмная"].enumerated() {
            let mi = item(t, #selector(setAppearanceMode(_:)), "")
            mi.tag = i
            themeMenu.addItem(mi)
        }
        let themeItem = NSMenuItem(title: "Тема окна", action: nil, keyEquivalent: "")
        themeItem.submenu = themeMenu
        win.addItem(themeItem)
        win.addItem(.separator())
        win.addItem(withTitle: "Свернуть", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenu(win, "Окно"))
        NSApp.windowsMenu = win

        NSApp.mainMenu = main
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func submenu(_ menu: NSMenu, _ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        i.submenu = menu
        return i
    }

    @objc func openSettings(_ sender: Any?) { ui.page = .appearance }
    @objc func openTakes(_ sender: Any?) { ui.page = .takes }
    @objc func togglePlay(_ sender: Any?) { engine.togglePlay() }
    @objc func stopPlay(_ sender: Any?) { engine.stop() }
    @objc func rewind(_ sender: Any?) { engine.rewind() }
    @objc func prevSection(_ sender: Any?) { engine.jumpToSection(offset: -1) }
    @objc func nextSection(_ sender: Any?) { engine.jumpToSection(offset: 1) }
    @objc func fontBigger(_ sender: Any?) { changeFont(4) }
    @objc func fontSmaller(_ sender: Any?) { changeFont(-4) }
    @objc func toggleMirror(_ sender: Any?) { settings.output.mirrorHorizontal.toggle() }
    @objc func outputExternal(_ sender: Any?) {
        if DisplayManager.externalScreens().isEmpty {
            alert("Второй экран не найден", "Подключите монитор по HDMI. Для проверки можно открыть вывод в отдельном окне.")
        } else { display.showOnExternal() }
    }
    @objc func outputWindowed(_ sender: Any?) { display.showWindowed() }
    @objc func outputClose(_ sender: Any?) { display.userClosed() }

    /// 0 — как в системе, 1 — светлая, 2 — тёмная.
    @objc func setAppearanceMode(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: "rut.appearance")
        applyAppearance()
    }

    private func applyAppearance() {
        switch UserDefaults.standard.integer(forKey: "rut.appearance") {
        case 1: NSApp.appearance = NSAppearance(named: .aqua)
        case 2: NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    @objc func insertSample(_ sender: Any?) {
        if !script.text.isEmpty {
            let a = NSAlert()
            a.messageText = "Заменить текущий текст примером?"
            a.addButton(withTitle: "Заменить")
            a.addButton(withTitle: "Отмена")
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        script.text = ScriptStorage.sample
        engine.jump(to: 0, animated: false)
    }

    @objc func openScript(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard var text = try? String(contentsOf: url, encoding: .utf8) else {
            alert("Не удалось прочитать файл", "Нужен текстовый файл в кодировке UTF-8 (.txt или .md).")
            return
        }
        if url.pathExtension.lowercased() == "md" { text = PrompterDocument.cleanImportedMarkdown(text) }
        script.text = text
        engine.jump(to: 0, animated: false)
    }

    @objc func saveScript(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Скрипт.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try script.text.write(to: url, atomically: true, encoding: .utf8) }
        catch { alert("Не удалось сохранить", error.localizedDescription) }
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
