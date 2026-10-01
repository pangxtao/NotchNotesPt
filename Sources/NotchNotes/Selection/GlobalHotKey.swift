import AppKit
import Carbon.HIToolbox

/// 可选的划词快捷键预设。
///
/// 用 Carbon `RegisterEventHotKey` 而不是 `NSEvent` 全局监听：
/// `Option + Q` 在 macOS 上会输入 `œ` 字符，只有 Carbon 热键能**消费**该事件，
/// 否则会在用户正在编辑的文档里插入乱码。注册热键本身不需要辅助功能权限。
enum HotKeySpec: String, CaseIterable, Identifiable, Codable, Sendable {
    case optionQ
    case optionD
    case optionS
    case controlOptionT

    var id: String { rawValue }

    var keyCode: UInt32 {
        switch self {
        case .optionQ: return UInt32(kVK_ANSI_Q)
        case .optionD: return UInt32(kVK_ANSI_D)
        case .optionS: return UInt32(kVK_ANSI_S)
        case .controlOptionT: return UInt32(kVK_ANSI_T)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .optionQ, .optionD, .optionS:
            return UInt32(optionKey)
        case .controlOptionT:
            return UInt32(controlKey | optionKey)
        }
    }

    var displayString: String {
        switch self {
        case .optionQ: return "⌥Q"
        case .optionD: return "⌥D"
        case .optionS: return "⌥S"
        case .controlOptionT: return "⌃⌥T"
        }
    }
}

/// Carbon 全局热键封装。
@MainActor
final class GlobalHotKey {
    private static var sharedAction: (() -> Void)?
    private static var sharedHandler: EventHandlerRef?
    private static let signature: OSType = 0x4E_4F_54_45   // 'NOTE'

    private var hotKeyRef: EventHotKeyRef?
    private(set) var isRegistered = false

    /// 注册热键。重复调用会先注销旧的。
    func register(_ spec: HotKeySpec, action: @escaping () -> Void) {
        unregister()

        GlobalHotKey.sharedAction = action
        installHandlerIfNeeded()

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = Self.signature
        hotKeyID.id = 1

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            spec.keyCode,
            spec.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            GlobalHotKey.sharedAction = nil
            isRegistered = false
            return
        }

        hotKeyRef = reference
        isRegistered = true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        isRegistered = false
        GlobalHotKey.sharedAction = nil
    }

    private func installHandlerIfNeeded() {
        guard GlobalHotKey.sharedHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Carbon 回调是 C 函数指针，无法捕获上下文，因此把动作存在静态变量里。
        let callback: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr, hotKeyID.signature == GlobalHotKey.signature else {
                return noErr
            }

            DispatchQueue.main.async {
                GlobalHotKey.sharedAction?()
            }
            return noErr
        }

        InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &eventType,
            nil,
            &GlobalHotKey.sharedHandler
        )
    }
}
