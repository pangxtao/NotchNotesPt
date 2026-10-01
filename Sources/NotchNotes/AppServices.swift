import Foundation

/// 应用级依赖容器。
///
/// 把「谁持有谁」集中到一处，避免各控制器各自 new 一份 store 导致状态分裂。
/// 注意：划词控制器需要引用本容器（存笔记、切回笔记页），所以用 `lazy` 打破初始化循环。
@MainActor
final class AppServices {
    let noteStore: NoteStore
    let translationSettings: TranslationSettingsStore
    let workspaceState: NotebookWorkspaceState
    let translationSession: TranslationSessionStore

    private(set) lazy var selectionTranslation = SelectionTranslationController(services: self)
    private(set) lazy var settingsWindow = TranslationSettingsWindowController(
        settings: translationSettings
    )

    init(
        noteStore: NoteStore = NoteStore(),
        translationSettings: TranslationSettingsStore = TranslationSettingsStore(),
        workspaceState: NotebookWorkspaceState = NotebookWorkspaceState()
    ) {
        self.noteStore = noteStore
        self.translationSettings = translationSettings
        self.workspaceState = workspaceState
        translationSession = TranslationSessionStore(
            settings: translationSettings,
            noteStore: noteStore,
            workspaceState: workspaceState
        )
    }

    /// 启动划词翻译（注册全局热键、监听设置变化）。
    func startSelectionTranslation() {
        selectionTranslation.start()
    }

    func showTranslationSettings() {
        settingsWindow.show()
    }

    /// 菜单入口，等价于按下划词快捷键。
    func translateSelectionNow() {
        selectionTranslation.translateSelectionNow()
    }

    func flush() {
        noteStore.flush(waitForDisk: true)
    }
}
