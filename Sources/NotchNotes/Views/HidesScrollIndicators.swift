import AppKit
import SwiftUI

/// 关掉 SwiftUI `TextEditor` 底层 `NSScrollView` 的滚动条。
///
/// SwiftUI 没有提供关闭滚动条的入口。系统设置里把「显示滚动条」设为「始终」时，
/// `TextEditor` 会常驻一根竖条（含轨道背景）——即使内容根本没超长。
/// 滚轮、触控板与光标跟随滚动照常可用，只是不画那根条。
///
/// 与递归搜索不同，这里只从 probe 自身向上找**最近的** `documentView` 为 `NSTextView`
/// 的 `NSScrollView`，避免同一屏里其他滚动容器（译文区）被误命中，导致本区没处理。
struct HidesScrollIndicators: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ProbeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ProbeView: NSView {
        private var attempts = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            attempts = 0
            schedule()
        }

        /// SwiftUI 可能在首次布局之后重建 `NSScrollView`，一次设置会被覆盖，
        /// 因此做有限次重试，直到确实找到并处理过 scrollView。
        private func schedule() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }

                if self.hideScrollers() { return }

                guard self.attempts < 12 else { return }
                self.attempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(self.attempts)) { [weak self] in
                    self?.schedule()
                }
            }
        }

        @discardableResult
        private func hideScrollers() -> Bool {
            guard let scrollView = findEnclosingTextViewScrollView() else { return false }
            Self.stripScrollers(scrollView)
            return true
        }

        /// 向上查找离自己最近、且包裹 NSTextView 的 NSScrollView。
        private func findEnclosingTextViewScrollView() -> NSScrollView? {
            var view: NSView? = self
            while let candidate = view {
                if let scrollView = candidate as? NSScrollView,
                   scrollView.documentView is NSTextView {
                    return scrollView
                }
                view = candidate.superview
            }
            return nil
        }

        private static func stripScrollers(_ scrollView: NSScrollView) {
            // `.overlay` 不占宽度；`legacy` 会常驻一条带轨道的竖条。
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false

            // 轨道背景来自 scrollView 自身，必须一并透明化。
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
            scrollView.borderType = .noBorder

            // 对所有名字里带 Scroller / Separator 的视图做兜底隐藏。
            hideScrollerArtifacts(in: scrollView)

            // 强制刷新布局，让 scroller 预留空间立即被回收。
            scrollView.needsLayout = true
            scrollView.layoutSubtreeIfNeeded()
            scrollView.setNeedsDisplay(scrollView.bounds)

            (scrollView.documentView as? NSTextView)?.drawsBackground = false
        }

        private static func hideScrollerArtifacts(in view: NSView) {
            for subview in view.subviews {
                let className = String(describing: type(of: subview))
                let isScrollerArtifact = className.contains("Scroller")
                    || className.contains("Separator")
                    || className.contains("Track")

                if isScrollerArtifact {
                    subview.isHidden = true
                    subview.alphaValue = 0
                    subview.wantsLayer = true
                    subview.layer?.backgroundColor = NSColor.clear.cgColor
                }
                hideScrollerArtifacts(in: subview)
            }
        }
    }
}
