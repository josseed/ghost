import AppKit
import Combine
import ServiceManagement
import SwiftUI

// Punto de entrada. Ghost es una app "agente" (LSUIElement): sin icono en el Dock,
// solo un NSStatusItem en la barra de menú con un popover SwiftUI.

@main
enum GhostApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: GhostController { .shared }
    private var settings: GhostSettings { .shared }

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Ciclo de vida

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        configurePopover()
        configureStatusItem()

        controller.onRequestClosePopover = { [weak self] in
            self?.popover.performClose(nil)
        }
        controller.start()

        controller.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusIcon() }
            .store(in: &cancellables)
        refreshStatusIcon()

        let welcomeKey = "didShowWelcome"
        if !UserDefaults.standard.bool(forKey: welcomeKey) {
            UserDefaults.standard.set(true, forKey: welcomeKey)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 700_000_000)
                self?.showPopover()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    /// Doble clic en Ghost.app estando ya abierta → muestra el popover.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    // MARK: URL scheme ghost://

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(handle)
    }

    private func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "ghost" else { return }
        switch GhostController.command(from: url) {
        case "settings", "preferences":
            showSettings()
        case "menu", "show":
            showPopover()
        case "login-on":
            _ = LoginItem.set(true)
        case "login-off":
            _ = LoginItem.set(false)
        case "quit":
            NSApp.terminate(nil)
        case "prepare-uninstall":
            _ = LoginItem.set(false)
            NSApp.terminate(nil)
        default:
            if !controller.handle(url: url) {
                NSLog("Ghost: URL no reconocida: %@", url.absoluteString)
            }
        }
    }

    // MARK: Barra de menú

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    /// Clic: popover · Clic derecho: alternar "mantener despierto" · ⌥+clic: Modo Ghost.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            controller.toggleAwake()
        } else if event?.modifierFlags.contains(.option) == true {
            controller.toggleGhostMode()
        } else {
            togglePopover()
        }
    }

    private func refreshStatusIcon() {
        guard let button = statusItem?.button else { return }
        button.image = GhostIcon.image(for: GhostIcon.state(
            isAwake: controller.isAwake,
            ghostMode: controller.ghostModeActive,
            lockout: controller.batteryLockout
        ))
        button.appearsDisabled = !controller.isAwake && !controller.ghostModeActive
        button.toolTip = "Ghost — \(controller.statusLine)\nClic derecho: alternar · ⌥ clic: Modo Ghost"
    }

    // MARK: Popover

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)

        let root = GhostMenuBarView(
            controller: controller,
            settings: settings,
            openSettings: { [weak self] in self?.showSettings() },
            quit: { NSApp.terminate(nil) }
        )
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
    }

    private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    private func showPopover() {
        guard let button = statusItem?.button, !popover.isShown else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: Ajustes

    @objc private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: GhostSettingsView(settings: settings, controller: controller))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Ajustes de Ghost"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Menú principal
    // Una app agente no tiene barra de menús visible, pero sin este menú los atajos
    // estándar (⌘C, ⌘V, ⌘W, ⌘Q) no funcionarían en la ventana de ajustes.

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: "Ghost")
        appMenu.addItem(withTitle: "Ajustes…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Cerrar ventana", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Salir de Ghost", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edición")
        editMenu.addItem(withTitle: "Deshacer", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Rehacer", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }
}
