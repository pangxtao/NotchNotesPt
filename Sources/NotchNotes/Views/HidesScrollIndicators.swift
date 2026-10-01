import AppKit
import SwiftUI

/// 关掉 SwiftUI `TextEditor` 底层 `NSScrollView` 的滚动条。
///
/// SwiftUI 没有提供关闭滚动条的入口。系统设置里把「显示滚动条」设为「始终」时，
/// `TextEditor` 会常驻一根竖条——即使内容根本没超长。滚轮、触控板与光标跟随
/// 滚动照常可用，只是不画那根条。
///
/// 只匹配 `documentView` 为 `NSTextView` 的 `NSScrollView`，避免误伤同一屏里
/// 其他滚动容器（译文区、笔记编辑器）。
struct HidesScrollIndicators: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ProbeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ProbeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            // SwiftUI 的视图树在本次布局后才稳定，下一轮 runloop 再找。
            DispatchQueue.main.async { [weak self] in
                self?.hideScrollers()
            }
        }

        private func hideScrollers() {
            var ancestor: NSView? = superview
            var depth = 0

            while let view = ancestor, depth < 4 {
                if let scrollView = Self.findTextViewScrollView(in: view) {
                    scrollView.scrollerStyle = .overlay
                    scrollView.autohidesScrollers = true
                    scrollView.hasVerticalScroller = false
                    scrollView.hasHorizontalScroller = false
                    return
                }
                ancestor = view.superview
                depth += 1
            }
        }

        private static func findTextViewScrollView(in view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView,
               scrollView.documentView is NSTextView {
                return scrollView
            }

            for subview in view.subviews {
                if let found = findTextViewScrollView(in: subview) {
                    return found
                }
            }

            return nil
        }
    }
}
