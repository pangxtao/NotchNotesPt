import AppKit

/// 划词弹窗的尺寸常量与文本测量。
///
/// 为什么需要它：结果态的译文用 `ScrollView` 承载，而 ScrollView 在 SwiftUI 的
/// `fittingSize` 计算中不贡献确定高度，于是窗口高度算得比实际内容矮，
/// **底部的操作按钮被裁到窗口外**（译文在上半部分，所以看起来"只有译文没有按钮"）。
///
/// 因此结果态高度改为「常量 + 文本测量」显式计算，视图与控制器共用同一套数值，
/// 保证窗口尺寸永远等于内容尺寸。
enum TranslationPopupMetrics {
    /// 正文左右各 13pt 内边距。
    static let horizontalPadding: CGFloat = 13

    /// 译文区高度上下限。
    static let minimumBodyHeight: CGFloat = 36
    static let maximumBodyHeight: CGFloat = 200

    // 固定区块高度（与 `TranslationPopupView` 的 padding 保持一致）。
    // 取值略大于自然高度，用 minHeight 撑开，保证内容不会被裁切。
    static let headerHeight: CGFloat = 40
    static let actionRowHeight: CGFloat = 38
    static let dividerHeight: CGFloat = 1

    /// 加载态与权限引导态的整体高度。
    static let loadingHeight: CGFloat = 110
    static let permissionHeight: CGFloat = 176

    /// 与 `TranslationPopupPanel.preferredWidth` 保持一致。
    /// 写成字面量而非引用：Panel 是 `@MainActor` 隔离的，本 enum 需要能在非隔离
    /// 上下文里被调用来测量文本。
    static let width: CGFloat = 360

    /// 正文可用宽度。
    static var bodyWidth: CGFloat { width - horizontalPadding * 2 }

    /// 测量一段文本的原始渲染高度（不含内边距）。
    private static func rawTextHeight(_ text: String, fontSize: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: bodyWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: fontSize)]
        )
        return ceil(bounding.height)
    }

    /// 译文/错误正文高度（含上下内边距），限制在上下限之间。
    static func bodyHeight(for text: String, fontSize: CGFloat, verticalPadding: CGFloat) -> CGFloat {
        let raw = rawTextHeight(text, fontSize: fontSize) + verticalPadding * 2 + 2
        return min(max(raw, minimumBodyHeight), maximumBodyHeight)
    }

    /// 错误态高度：主文案 + 可选的失败环节提示。
    static func errorBodyHeight(message: String, hint: String?) -> CGFloat {
        var raw = rawTextHeight(message, fontSize: 12) + 20 + 2
        if let hint, !hint.isEmpty {
            raw += rawTextHeight(hint, fontSize: 10) + 6
        }
        return min(max(raw, minimumBodyHeight), maximumBodyHeight)
    }

    /// 结果态整体高度：header + 分隔线 + 正文 + 分隔线 + 底部按钮。
    static func resultHeight(bodyHeight: CGFloat) -> CGFloat {
        headerHeight + dividerHeight + bodyHeight + dividerHeight + actionRowHeight
    }
}
