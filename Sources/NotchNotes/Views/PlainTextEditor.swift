import AppKit
import SwiftUI

/// 完全自定义的纯文本输入框，替换 SwiftUI `TextEditor`。
///
/// 使用 AppKit `NSTextView` + `NSScrollView`，从源头上关闭滚动条、
/// 去掉轨道背景与边框，避免系统「始终显示滚动条」设置带来的深色竖条。
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isRichText = false
        textView.isSelectable = true
        textView.isEditable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textColor = NSColor.white.withAlphaComponent(0.92)
        textView.insertionPointColor = NSColor.white.withAlphaComponent(0.92)
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}
