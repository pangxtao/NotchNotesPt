import AppKit
import Combine
import Foundation

/// 翻译页的状态机：输入 → 防抖 → 请求 → 流式追加 → 完成 / 报错。
@MainActor
final class TranslationSessionStore: ObservableObject {
    /// 输入停顿多久后自动翻译。
    static let autoTranslateDelay: Duration = .milliseconds(600)

    @Published var inputText = "" {
        didSet {
            guard inputText != oldValue else { return }
            scheduleAutoTranslate()
        }
    }

    @Published private(set) var translatedText = ""
    @Published private(set) var isTranslating = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var source: TranslationLanguage = .english
    @Published private(set) var target: TranslationLanguage = .chinese
    @Published private(set) var isAutoDirection = true
    @Published private(set) var lastElapsed: TimeInterval?
    @Published private(set) var didCopyTranslation = false

    private let settings: TranslationSettingsStore
    private let noteStore: NoteStore
    private let workspaceState: NotebookWorkspaceState
    private let service = TranslationService()

    private var debounceTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private var copyResetTask: Task<Void, Never>?

    init(
        settings: TranslationSettingsStore,
        noteStore: NoteStore,
        workspaceState: NotebookWorkspaceState
    ) {
        self.settings = settings
        self.noteStore = noteStore
        self.workspaceState = workspaceState
    }

    // MARK: - Derived state

    var directionLabel: String {
        "\(source.shortName) → \(target.shortName)"
    }

    var modelName: String {
        settings.model.displayName
    }

    var isConfigured: Bool {
        settings.isConfigured
    }

    var hasTranslation: Bool {
        !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canTranslate: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var characterCount: Int {
        inputText.count
    }

    var elapsedLabel: String? {
        guard let lastElapsed else { return nil }
        return String(format: "Done in %.2fs", lastElapsed)
    }

    var canRetry: Bool {
        errorMessage != nil && canTranslate
    }

    // MARK: - Actions

    func scheduleAutoTranslate() {
        debounceTask?.cancel()

        guard settings.autoTranslate, canTranslate else { return }

        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autoTranslateDelay)
            guard !Task.isCancelled else { return }
            self?.translateNow()
        }
    }

    func translateNow() {
        debounceTask?.cancel()
        debounceTask = nil

        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if isAutoDirection {
            let detected = TranslationLanguageDetector.detect(text)
            source = detected
            target = detected.opposite
        }

        guard settings.isConfigured else {
            isTranslating = false
            translatedText = ""
            errorMessage = TranslationServiceError.missingAPIKey.errorDescription
            return
        }

        let sourceLanguage = source
        let targetLanguage = target
        let model = settings.model
        let apiKey = settings.apiKey
        let baseURLString = settings.baseURLString

        translationTask?.cancel()
        errorMessage = nil
        isTranslating = true

        let startedAt = Date()

        translationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let stream = self.service.translate(
                    text: text,
                    source: sourceLanguage,
                    target: targetLanguage,
                    model: model,
                    apiKey: apiKey,
                    baseURLString: baseURLString
                )

                var isFirstChunk = true
                for try await delta in stream {
                    if Task.isCancelled { return }
                    if isFirstChunk {
                        isFirstChunk = false
                        self.translatedText = delta
                    } else {
                        self.translatedText += delta
                    }
                }

                guard !Task.isCancelled else { return }
                self.isTranslating = false
                self.lastElapsed = Date().timeIntervalSince(startedAt)
                self.translationTask = nil
            } catch is CancellationError {
                // 被新的输入取代。
            } catch {
                guard !Task.isCancelled else { return }
                self.isTranslating = false
                self.translatedText = ""
                self.errorMessage = Self.message(for: error)
                self.translationTask = nil
            }
        }
    }

    func swapDirection() {
        let previousSource = source
        source = target
        target = previousSource
        isAutoDirection = false

        guard canTranslate else { return }
        translateNow()
    }

    func toggleAutoDirection() {
        isAutoDirection.toggle()
        guard isAutoDirection, canTranslate else { return }
        translateNow()
    }

    func selectModel(_ model: TranslationModel) {
        settings.model = model
        guard canTranslate else { return }
        translateNow()
    }

    func clear() {
        debounceTask?.cancel()
        translationTask?.cancel()
        translationTask = nil

        inputText = ""
        translatedText = ""
        errorMessage = nil
        isTranslating = false
        lastElapsed = nil
        isAutoDirection = true
    }

    func copyTranslation() {
        let text = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

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

        noteStore.addTab(
            text: TranslationNoteComposer.markdown(
                sourceText: inputText,
                translatedText: translation
            )
        )
        workspaceState.mode = .notes
    }

    /// 从划词弹窗等入口带入文本并立即翻译。
    func translate(text: String) {
        inputText = text
        translateNow()
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

/// 把「原文 + 译文」拼成一条笔记。
///
/// 用引用块承载原文，`NoteStore` 提取标题时会剥掉 `> `，标题即原文。
enum TranslationNoteComposer {
    static func markdown(sourceText: String, translatedText: String) -> String {
        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return "> \(source)\n\n\(translation)"
    }
}
