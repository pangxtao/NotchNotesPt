import Foundation

/// 展开面板的两个工作区。
///
/// 尺寸与模式无关：笔记页与翻译页共用同一档展开宽度（见 `NotchGeometry.layout(for:)`），
/// 切换时只替换内容区，窗口不做任何尺寸变化。
enum WorkspaceMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case notes
    case translate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: return "Notes"
        case .translate: return "Translate"
        }
    }
}
