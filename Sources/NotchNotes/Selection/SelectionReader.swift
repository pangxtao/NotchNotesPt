import AppKit
import ApplicationServices
import Carbon.HIToolbox

// MARK: - 权限

enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 触发系统授权引导（每个应用只会弹一次）。
    ///
    /// 注意：`kAXTrustedCheckOptionPrompt` 在 Swift 6 下是共享可变全局量，
    /// 引用它会编译失败，因此这里直接用字符串字面量。
    static func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// 当前运行进程对应的 bundle 路径（用于权限诊断）。
    static var currentBundlePath: String {
        Bundle.main.bundlePath
    }

    /// 当前运行进程是否为 .app bundle（命令行 `swift run` 跑的则不是）。
    static var isRunningAsAppBundle: Bool {
        currentBundlePath.hasSuffix(".app")
    }
}

// MARK: - 文本归一化

enum SelectionTextNormalizer {
    static let maximumLength = 5000

    /// 折叠各种空白（含不换行空格与全角空格）并去除首尾空白。
    static func normalize(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{3000}", with: " ")

        let collapsed = normalized
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard collapsed.count > maximumLength else { return collapsed }
        return String(collapsed.prefix(maximumLength))
    }
}

// MARK: - 选区切片

/// AX 的 `AXSelectedTextRange` 以 **UTF-16 码元**为单位。
///
/// 按 `Character` 切会在含 emoji 的文本上偏移——这正是「取到的文本
/// 比选中的多/少一截」的根源，所以统一按 `utf16` 视图切片。
enum SelectionRangeSlicer {
    static func slice(_ text: String, location: Int, length: Int) -> String? {
        guard location >= 0, length > 0 else { return nil }

        let units = Array(text.utf16)
        guard location + length <= units.count else { return nil }

        return String(decoding: units[location..<(location + length)], as: UTF16.self)
    }
}

// MARK: - 取词

/// 一次取词的结果。`diagnostic` 用于定位「按了没反应」到底卡在哪一环。
struct SelectionReadResult: Sendable {
    let text: String?
    let diagnostic: String

    static func success(_ text: String, via stage: String) -> SelectionReadResult {
        SelectionReadResult(text: text, diagnostic: stage)
    }

    static func failure(_ diagnostic: String) -> SelectionReadResult {
        SelectionReadResult(text: nil, diagnostic: diagnostic)
    }
}

/// 读取其他应用中被选中的文本。
///
/// 双路径：辅助功能 API 优先，剪贴板兜底（Electron / Chrome 系应用经常不实现
/// `kAXSelectedTextAttribute`，只走 AX 会「经常失败」）。
enum SelectionReader {
    /// AX 调用是同步阻塞的，默认 messaging timeout 高达 6 秒。
    /// 目标应用一卡，主线程就被拖满，表现就是「按了快捷键毫无反应」。
    private static let messagingTimeout: Float = 0.35

    /// 剪贴板兜底的等待窗口。单窗口 0.6s 不够（不少应用先抬 changeCount 再异步写内容），
    /// 因此做两轮，总耗时仍控制在 1.4s 内。
    private static let clipboardWaitWindows: [TimeInterval] = [0.6, 0.8]

    static func read() async -> SelectionReadResult {
        guard AccessibilityPermission.isTrusted else {
            return .failure("Accessibility not granted")
        }

        // 必须在第一次取值前设置，否则不生效。
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)

        if let text = readViaAccessibility() {
            return .success(text, via: "AX: ok")
        }

        if let text = await readViaClipboard() {
            return .success(text, via: "Clipboard: ok")
        }

        return .failure("AX: no selected text · Clipboard: ⌘C did not register")
    }

    // MARK: AX path

    private static func readViaAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef else {
            return nil
        }

        // 焦点常落在包装层（Web Area / Group）上，真正的可选文本在相邻层级，
        // 因此沿父链回溯若干层做多候选。
        var candidate: AXUIElement? = unsafeBitCast(focusedRef, to: AXUIElement.self)
        for _ in 0..<3 {
            guard let element = candidate else { break }
            if let text = selectedText(from: element) { return text }
            candidate = parent(of: element)
        }

        return nil
    }

    private static func selectedText(from element: AXUIElement) -> String? {
        // 首选：直接读选中文本属性。
        var selectedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        ) == .success,
           let selected = selectedRef as? String,
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selected
        }

        // 兜底：只给「选区 range + 全文」的应用（Electron / Java / 部分 PDF 阅读器）。
        var rangeRef: CFTypeRef?
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeRef,
              AXUIElementCopyAttributeValue(
                element,
                kAXValueAttribute as CFString,
                &valueRef
              ) == .success, let valueRef,
              let fullText = valueRef as? String else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(rangeRef, to: AXValue.self), .cfRange, &range) else {
            return nil
        }

        return SelectionRangeSlicer.slice(
            fullText,
            location: range.location,
            length: range.length
        )
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        var parentRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &parentRef
        ) == .success, let parentRef else {
            return nil
        }

        return unsafeBitCast(parentRef, to: AXUIElement.self)
    }

    // MARK: Clipboard fallback

    private static func readViaClipboard() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)
        let startingChangeCount = pasteboard.changeCount

        // 投递 ⌘C 前先让物理按住的 Option 松开，否则有概率被拼成 ⌥⌘C。
        try? await Task.sleep(for: .milliseconds(60))

        postCommandC()

        var captured: String?
        for window in clipboardWaitWindows {
            let deadline = Date().addingTimeInterval(window)

            while Date() < deadline {
                // 关键：changeCount 变了 ≠ 数据写完了。很多应用先抬 changeCount
                // 再异步写内容，此处读到空串必须继续等，而不是立刻放弃。
                if pasteboard.changeCount != startingChangeCount,
                   let string = pasteboard.string(forType: .string),
                   !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    captured = string
                    break
                }

                try? await Task.sleep(for: .milliseconds(40))
            }

            if captured != nil { break }
        }

        // 无论成功与否都要还原，避免顶掉用户自己的剪贴板内容。
        restorePasteboard(pasteboard, snapshot: snapshot)

        return captured
    }

    private static func postCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_C)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type] = data
                }
            }
            return contents
        }
    }

    private static func restorePasteboard(
        _ pasteboard: NSPasteboard,
        snapshot: [[NSPasteboard.PasteboardType: Data]]
    ) {
        pasteboard.clearContents()

        let items = snapshot.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents {
                item.setData(data, forType: type)
            }
            return item
        }

        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }
}
