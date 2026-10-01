import AppKit

/// 划词翻译弹窗。
///
/// 关键点：`.nonactivatingPanel` 让它在不激活应用的前提下接收鼠标事件，
/// 用户的选区和输入焦点都不会被打断。
@MainActor
final class TranslationPopupPanel: NSPanel {
    static let preferredWidth: CGFloat = 360
    static let minimumHeight: CGFloat = 96
    static let maximumHeight: CGFloat = 340
    static let loadingHeight: CGFloat = 110

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.preferredWidth,
                height: Self.loadingHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)
        animationBehavior = .utilityWindow
        acceptsMouseMovedEvents = true
    }
}
