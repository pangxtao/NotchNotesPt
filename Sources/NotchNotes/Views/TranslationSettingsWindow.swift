import AppKit
import SwiftUI

/// 翻译设置窗口（独立窗口，非模态）。
@MainActor
final class TranslationSettingsWindowController {
    private var window: NSWindow?
    private let settings: TranslationSettingsStore

    init(settings: TranslationSettingsStore) {
        self.settings = settings
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingView(
            rootView: TranslationSettingsView(settings: settings) { [weak self] in
                self?.close()
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Translation Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.center()
        window.appearance = NSAppearance(named: .darkAqua)

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }
}
