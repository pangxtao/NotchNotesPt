import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController?
    private var statusItem: NSStatusItem?
    private var statusContextMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = NotchPanelController()
        panelController?.showDocked()
        // 注册全局划词热键并开始监听设置变化。
        panelController?.services.startSelectionTranslation()
        buildStatusItem()
        buildMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.flush()
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }

        button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "NotchNotes")
        button.imagePosition = .imageOnly
        button.action = #selector(statusItemButtonClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Open NotchNotes"

        statusContextMenu = makeStatusContextMenu()
        statusItem = item
    }

    private func buildMenu() {
        let rootItem = NSMenuItem(title: "NotchNotes", action: nil, keyEquivalent: "")
        rootItem.submenu = makeAppMenu()

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = makeEditMenu()

        let mainMenu = NSMenu()
        mainMenu.addItem(rootItem)
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func makeAppMenu() -> NSMenu {
        let appMenu = NSMenu()
        let newItem = NSMenuItem(title: "New Note", action: #selector(newNote), keyEquivalent: "n")
        newItem.target = self
        appMenu.addItem(newItem)

        let showItem = NSMenuItem(title: "Show Notes", action: #selector(showNotes), keyEquivalent: "")
        showItem.target = self
        appMenu.addItem(showItem)

        let hideItem = NSMenuItem(title: "Hide Notes", action: #selector(hideNotes), keyEquivalent: "w")
        hideItem.target = self
        appMenu.addItem(hideItem)

        appMenu.addItem(.separator())

        let translateItem = NSMenuItem(
            title: "Translate Selected Text",
            action: #selector(translateSelection),
            keyEquivalent: ""
        )
        translateItem.target = self
        appMenu.addItem(translateItem)

        let translationSettingsItem = NSMenuItem(
            title: "Translation Settings…",
            action: #selector(openTranslationSettings),
            keyEquivalent: ","
        )
        translationSettingsItem.target = self
        appMenu.addItem(translationSettingsItem)

        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit NotchNotes", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)

        return appMenu
    }

    private func makeStatusContextMenu() -> NSMenu {
        let menu = NSMenu()

        let newItem = NSMenuItem(title: "New Note", action: #selector(newNote), keyEquivalent: "n")
        newItem.target = self
        menu.addItem(newItem)

        menu.addItem(.separator())

        let translateItem = NSMenuItem(
            title: "Translate Selected Text",
            action: #selector(translateSelection),
            keyEquivalent: ""
        )
        translateItem.target = self
        menu.addItem(translateItem)

        let translationSettingsItem = NSMenuItem(
            title: "Translation Settings…",
            action: #selector(openTranslationSettings),
            keyEquivalent: ""
        )
        translationSettingsItem.target = self
        menu.addItem(translationSettingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit NotchNotes",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func makeEditMenu() -> NSMenu {
        let editMenu = NSMenu(title: "Edit")

        let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        undoItem.target = nil
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        redoItem.target = nil
        editMenu.addItem(redoItem)

        editMenu.addItem(.separator())

        let cutItem = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        cutItem.target = nil
        editMenu.addItem(cutItem)

        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        copyItem.target = nil
        editMenu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        pasteItem.target = nil
        editMenu.addItem(pasteItem)

        editMenu.addItem(.separator())

        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        selectAllItem.target = nil
        editMenu.addItem(selectAllItem)

        editMenu.addItem(.separator())

        let findMenuItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: "Find")
        findMenu.addItem(findCommand(
            title: "Find…",
            action: .showFindInterface,
            keyEquivalent: "f"
        ))
        findMenu.addItem(findCommand(
            title: "Find Next",
            action: .nextMatch,
            keyEquivalent: "g"
        ))
        let previousItem = findCommand(
            title: "Find Previous",
            action: .previousMatch,
            keyEquivalent: "g"
        )
        previousItem.keyEquivalentModifierMask = [.command, .shift]
        findMenu.addItem(previousItem)
        findMenuItem.submenu = findMenu
        editMenu.addItem(findMenuItem)

        return editMenu
    }

    private func findCommand(
        title: String,
        action: NSTextFinder.Action,
        keyEquivalent: String
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(NSTextView.performFindPanelAction(_:)),
            keyEquivalent: keyEquivalent
        )
        item.tag = action.rawValue
        item.target = nil
        return item
    }

    @objc private func statusItemButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isContextClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if isContextClick {
            statusContextMenu?.popUp(
                positioning: nil,
                at: NSPoint(x: sender.bounds.midX, y: sender.bounds.minY),
                in: sender
            )
        } else {
            panelController?.expand(animated: true)
        }
    }

    @objc private func newNote() {
        panelController?.createNote()
    }

    @objc private func showNotes() {
        panelController?.expand(animated: true)
    }

    @objc private func hideNotes() {
        panelController?.collapse(animated: true)
    }

    /// 等价于在任意应用里选中文字后按下划词快捷键。
    @objc private func translateSelection() {
        panelController?.services.translateSelectionNow()
    }

    @objc private func openTranslationSettings() {
        panelController?.services.showTranslationSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
