import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = MainWindowController(model: AppModel())
        mainWindowController = controller
        configureMainMenu()
        configureStatusItem()
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        DaytonaBridgeProcess.shared.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu(title: "Main Menu")

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = makeApplicationMenu()
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(item("New Recording", action: #selector(newRecording(_:)), key: "n"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Close Window", action: #selector(closeWindow(_:)), key: "w"))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = makeEditMenu()
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApplication.shared.windowsMenu = windowMenu

        NSApplication.shared.mainMenu = mainMenu
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = Bundle.main.url(forResource: "pesu-logo", withExtension: "png").flatMap(NSImage.init(contentsOf:))
            image?.size = NSSize(width: 19, height: 19)
            image?.isTemplate = false
            button.image = image
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "Pēsu"
        }
        statusItem.menu = makeStatusMenu()
        self.statusItem = statusItem
    }

    private func makeApplicationMenu() -> NSMenu {
        let menu = NSMenu(title: "Pēsu")
        menu.addItem(item("About Pēsu", action: #selector(showAbout(_:))))
        menu.addItem(item("Check for Updates…", action: #selector(checkForUpdates(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", action: #selector(showSettings(_:)), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit Pēsu", action: #selector(quit(_:)), key: "q"))
        return menu
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu(title: "Pēsu")
        menu.addItem(item("New Recording", action: #selector(newRecording(_:))))
        menu.addItem(item("Show Pēsu", action: #selector(showApp(_:))))
        menu.addItem(item("Close Window", action: #selector(closeWindow(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", action: #selector(showSettings(_:))))
        menu.addItem(item("About Pēsu", action: #selector(showAbout(_:))))
        menu.addItem(item("Check for Updates…", action: #selector(checkForUpdates(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Pēsu", action: #selector(quit(_:))))
        return menu
    }

    private func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        menu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        return menu
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    private func showMainWindow() {
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func newRecording(_ sender: Any?) {
        showMainWindow()
        mainWindowController?.beginNewRecordingFromMenu()
    }

    @objc private func showApp(_ sender: Any?) {
        showMainWindow()
    }

    @objc private func closeWindow(_ sender: Any?) {
        mainWindowController?.window?.performClose(sender)
    }

    @objc private func showSettings(_ sender: Any?) {
        showMainWindow()
        mainWindowController?.showSettingsFromMenu()
    }

    @objc private func showAbout(_ sender: Any?) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Pēsu",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0",
            .credits: NSAttributedString(string: "Private meeting notes, recorded and processed locally on your Mac.")
        ])
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        showMainWindow()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let alert = NSAlert()
        alert.messageText = "Pēsu \(version)"
        alert.informativeText = "This local development build does not have a signed update feed yet. Update checking will become available with the first distributed release."
        alert.addButton(withTitle: "OK")
        if let window = mainWindowController?.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    @objc private func quit(_ sender: Any?) {
        NSApplication.shared.terminate(sender)
    }
}
