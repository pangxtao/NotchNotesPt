import AppKit
import Combine
import SwiftUI

/// 划词翻译的编排者：全局热键 → 取词 → 翻译 → 光标旁弹窗。
@MainActor
final class SelectionTranslationController: ObservableObject {
    @Published private(set) var sourceText = ""
    @Published private(set) var translatedText = ""
    @Published private(set) var isTranslating = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var source: TranslationLanguage = .chinese
    @Published private(set) var target: TranslationLanguage = .english
    @Published private(set) var needsAccessibilityPermission = false
    @Published private(set) var didCopyTranslation = false
    /// 取词失败时给出具体环节（权限 / AX / 剪贴板），用于定位「按了没反应」到底卡在哪。
    @Published private(set) var failureHint: String?

    private let services: AppServices
    private let settings: TranslationSettingsStore
    private let service = TranslationService()
    private let hotKey = GlobalHotKey()

    private var panel: TranslationPopupPanel?
    private var hostingView: NSHostingView<TranslationPopupView>?
    private var selectionTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private var dismissWorkItem: DispatchWorkItem?
    private var copyResetTask: Task<Void, Never>?
    private var eventMonitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()
    private var anchorPoint = NSPoint.zero
    private var isVisible = false

    init(services: AppServices) {
        self.services = services
        settings = services.translationSettings
    }

    var directionLabel: String {
        "\(source.shortName) → \(target.shortName)"
    }

    var modelName: String {
        settings.model.displayName
    }

    var hasTranslation: Bool {
        !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canRetry: Bool {
        errorMessage != nil && !needsAccessibilityPermission
    }

    // MARK: - Lifecycle

    func start() {
        registerHotKey()

        settings.$selectionHotKey
            .removeDuplicates()
            .sink { [weak self] _ in self?.registerHotKey() }
            .store(in: &cancellables)

        settings.$isSelectionTranslationEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard let self else { return }
                self.registerHotKey()
                if !isEnabled { self.dismiss() }
            }
            .store(in: &cancellables)
    }

    private func registerHotKey() {
        hotKey.unregister()

        guard settings.isSelectionTranslationEnabled else { return }

        hotKey.register(settings.selectionHotKey) { [weak self] in
            self?.handleHotKey()
        }
    }

    // MARK: - Hot key flow

    /// 菜单等外部入口，等价于按下快捷键。
    func translateSelectionNow() {
        handleHotKey()
    }

    private func handleHotKey() {
        guard settings.isSelectionTranslationEnabled else { return }

        // 弹窗里已经有译文时，再按一次当作「关闭」；其余情况一律重新取词。
        //
        // 旧实现是「只要弹窗可见就只关闭」，于是第一次取词失败后，第二次按键只是把
        // 提示关掉、什么都不做——用户会认为快捷键彻底坏了，只能靠 Esc 或点击别处重来。
        if isVisible, hasTranslation, !isTranslating {
            dismiss()
            return
        }

        guard AccessibilityPermission.isTrusted else {
            // 第一次使用时触发系统授权弹窗，同时在弹窗里给出解释。
            AccessibilityPermission.request()
            presentPermissionPrompt()
            return
        }

        // 重置状态。取词期间先不显示弹窗，避免"一闪而过"；
        // 取词成功后再以固定 loading 尺寸出现，随后随译文平滑展开。
        anchorPoint = NSEvent.mouseLocation
        sourceText = ""
        translatedText = ""
        errorMessage = nil
        failureHint = nil
        needsAccessibilityPermission = false
        didCopyTranslation = false
        isTranslating = false

        selectionTask?.cancel()
        selectionTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let result = await SelectionReader.read()
            guard !Task.isCancelled else { return }

            guard let text = result.text else {
                self.isTranslating = false
                self.presentEmptySelectionNotice(diagnostic: result.diagnostic)
                return
            }

            self.beginTranslation(of: text, anchor: self.anchorPoint)
        }
    }

    private func beginTranslation(of text: String, anchor: NSPoint) {
        anchorPoint = anchor
        sourceText = SelectionTextNormalizer.normalize(text)
        translatedText = ""
        errorMessage = nil
        failureHint = nil
        needsAccessibilityPermission = false
        didCopyTranslation = false

        let detected = TranslationLanguageDetector.detect(sourceText)
        source = detected
        target = detected.opposite

        // 先把固定 loading 弹窗挂出来，避免后续 resize 从最小高度跳变。
        isTranslating = true
        showPanel()

        guard settings.isConfigured else {
            isTranslating = false
            errorMessage = TranslationServiceError.missingAPIKey.errorDescription
            resizePanelForContent(animate: true)
            return
        }

        let sourceLanguage = source
        let targetLanguage = target
        let textToTranslate = sourceText

        translationTask?.cancel()
        translationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let stream = self.service.translate(
                    text: textToTranslate,
                    source: sourceLanguage,
                    target: targetLanguage,
                    model: self.settings.model,
                    apiKey: self.settings.apiKey,
                    baseURLString: self.settings.baseURLString
                )

                var becameNonEmpty = false
                for try await delta in stream {
                    if Task.isCancelled { return }

                    let wasEmpty = self.translatedText.isEmpty
                    self.translatedText += delta
                    if wasEmpty, !self.translatedText.isEmpty, !becameNonEmpty {
                        becameNonEmpty = true
                        self.resizePanelForContent(animate: true)
                    }
                }

                guard !Task.isCancelled else { return }
                self.isTranslating = false
                self.translationTask = nil
                self.resizePanelForContent(animate: true)
            } catch is CancellationError {
                // 被新的调用取代。
            } catch {
                guard !Task.isCancelled else { return }
                self.isTranslating = false
                self.errorMessage = Self.message(for: error)
                self.translationTask = nil
                self.resizePanelForContent(animate: true)
            }
        }
    }

    private func presentPermissionPrompt() {
        anchorPoint = NSEvent.mouseLocation
        sourceText = ""
        translatedText = ""
        errorMessage = nil
        failureHint = nil
        isTranslating = false
        needsAccessibilityPermission = true
        showPanel()
    }

    private func presentEmptySelectionNotice(diagnostic: String) {
        anchorPoint = NSEvent.mouseLocation
        translatedText = ""
        isTranslating = false
        needsAccessibilityPermission = false
        failureHint = diagnostic
        errorMessage = "No selected text found. Select some text first, then press \(settings.selectionHotKey.displayString)."
        showPanel()
    }

    // MARK: - Actions

    func retry() {
        guard !needsAccessibilityPermission else {
            retryAfterPermissionGrant()
            return
        }

        guard !sourceText.isEmpty else {
            handleHotKey()
            return
        }

        beginTranslation(of: sourceText, anchor: anchorPoint)
    }

    func retryAfterPermissionGrant() {
        guard AccessibilityPermission.isTrusted else {
            AccessibilityPermission.openSystemSettings()
            return
        }

        // 权限已授予：重新走一次完整的取词流程。
        dismiss()
        handleHotKey()
    }

    func swapAndRetranslate() {
        let previousSource = source
        source = target
        target = previousSource
        beginTranslation(of: sourceText, anchor: anchorPoint)
    }

    func copyTranslation() {
        let translation = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translation.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(translation, forType: .string)

        didCopyTranslation = true
        copyResetTask?.cancel()
        copyResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            self?.didCopyTranslation = false
        }
    }

    func saveAsNote() {
        let translation = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translation.isEmpty else { return }

        services.noteStore.addTab(
            text: TranslationNoteComposer.markdown(
                sourceText: sourceText,
                translatedText: translation
            )
        )
        services.workspaceState.mode = .notes
        dismiss()
    }

    func dismiss() {
        selectionTask?.cancel()
        selectionTask = nil

        translationTask?.cancel()
        translationTask = nil

        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        copyResetTask?.cancel()
        copyResetTask = nil

        removeEventMonitors()

        guard isVisible else { return }
        isVisible = false
        panel?.orderOut(nil)
    }

    // MARK: - Panel plumbing

    private func showPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel

        isVisible = true
        // 直接以目标高度出现，避免「先小后大」的跳变。
        let size = NSSize(
            width: TranslationPopupPanel.preferredWidth,
            height: computeHeight()
        )
        panel.setFrame(positionedFrame(for: size), display: true)
        panel.orderFrontRegardless()
        installEventMonitors()
        scheduleAutoDismiss()
    }

    private func makePanel() -> TranslationPopupPanel {
        let panel = TranslationPopupPanel()
        let host = NSHostingView(rootView: TranslationPopupView(controller: self))
        host.frame = NSRect(
            x: 0,
            y: 0,
            width: TranslationPopupPanel.preferredWidth,
            height: TranslationPopupPanel.loadingHeight
        )
        panel.contentView = host
        hostingView = host
        return panel
    }

    private func resizePanelForContent(animate: Bool = false) {
        guard isVisible, let panel else { return }

        let size = NSSize(
            width: TranslationPopupPanel.preferredWidth,
            height: computeHeight()
        )
        let frame = positionedFrame(for: size)

        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = .init(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    /// 显式计算窗口高度。
    ///
    /// 不用 `hostingView.fittingSize`：结果态的译文由 `ScrollView` 承载，
    /// ScrollView 在 fittingSize 里不贡献确定高度，会把窗口算矮、裁掉底部按钮。
    private func computeHeight() -> CGFloat {
        if needsAccessibilityPermission {
            return TranslationPopupMetrics.permissionHeight
        }

        if isTranslating, translatedText.isEmpty, errorMessage == nil {
            return TranslationPopupMetrics.loadingHeight
        }

        let bodyHeight: CGFloat
        if let errorMessage {
            bodyHeight = TranslationPopupMetrics.errorBodyHeight(
                message: errorMessage,
                hint: failureHint
            )
        } else {
            bodyHeight = TranslationPopupMetrics.bodyHeight(
                for: translatedText,
                fontSize: 13,
                verticalPadding: 10
            )
        }

        let total = TranslationPopupMetrics.resultHeight(bodyHeight: bodyHeight)
        return min(total, TranslationPopupPanel.maximumHeight)
    }

    private func positionedFrame(for size: NSSize) -> NSRect {
        let margin: CGFloat = 14
        let edge: CGFloat = 8
        let anchor = anchorPoint

        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // 默认落在光标右下；右侧或下方空间不足时翻到另一侧。
        var origin = NSPoint(
            x: anchor.x + margin,
            y: anchor.y - size.height - margin
        )

        if origin.x + size.width > visibleFrame.maxX - edge {
            origin.x = anchor.x - size.width - margin
        }
        if origin.y < visibleFrame.minY + edge {
            origin.y = anchor.y + margin
        }

        origin.x = min(max(origin.x, visibleFrame.minX + edge), visibleFrame.maxX - size.width - edge)
        origin.y = min(max(origin.y, visibleFrame.minY + edge), visibleFrame.maxY - size.height - edge)

        return NSRect(origin: origin, size: size)
    }

    private func scheduleAutoDismiss(after seconds: TimeInterval = 14) {
        dismissWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }

            // 鼠标还停在弹窗上就先不关，等它离开。
            if let frame = self.panel?.frame,
               frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) {
                self.scheduleAutoDismiss(after: 4)
                return
            }

            self.dismiss()
        }

        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func installEventMonitors() {
        removeEventMonitors()

        var monitors: [Any] = []

        // 点击弹窗以外的地方收起。全局监视器看不到本应用自己的事件，
        // 所以额外挂一个本地监视器，覆盖用户点回 NotchNotes 面板的情况。
        if let globalClick = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.dismissIfClickIsOutside() }
        } {
            monitors.append(globalClick)
        }

        if let localClick = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            Task { @MainActor in self?.dismissIfClickIsOutside() }
            return event
        } {
            monitors.append(localClick)
        }

        // Esc 关闭。Carbon 热键已经吞掉 Option+Q，这里只关心 Esc。
        if let globalKey = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in self?.dismiss() }
        } {
            monitors.append(globalKey)
        }

        eventMonitors = monitors
    }

    private func removeEventMonitors() {
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
    }

    private func dismissIfClickIsOutside() {
        guard isVisible, let frame = panel?.frame else { return }
        guard !frame.contains(NSEvent.mouseLocation) else { return }
        dismiss()
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
