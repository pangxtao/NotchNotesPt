import Foundation

/// 当前开放互译的语种。
///
/// Qwen-MT 原生支持 92 种语言，这里按产品要求只暴露中英两种。
/// 后续扩展只需补充 `case` 与对应文案，请求层与 UI 均无需修改。
enum TranslationLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case chinese
    case english

    var id: String { rawValue }

    /// 传给 Qwen-MT 的 `source_lang` / `target_lang`。
    var apiValue: String {
        switch self {
        case .chinese: return "Chinese"
        case .english: return "English"
        }
    }

    var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    /// 方向条上的紧凑写法。
    var shortName: String {
        switch self {
        case .chinese: return "中"
        case .english: return "EN"
        }
    }

    var opposite: TranslationLanguage {
        switch self {
        case .chinese: return .english
        case .english: return .chinese
        }
    }
}

/// 中英互译场景下，只需要区分「含中文」与「不含中文」两种输入。
enum TranslationLanguageDetector {
    static func detect(_ text: String) -> TranslationLanguage {
        containsCJK(text) ? .chinese : .english
    }

    static func containsCJK(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3000...0x303F,   // 中文标点
                 0x3400...0x4DBF,   // 扩展 A 区
                 0x4E00...0x9FFF,   // 基本汉字
                 0xF900...0xFAFF,   // 兼容表意文字
                 0xFF01...0xFF60:   // 全角字符
                return true
            default:
                continue
            }
        }

        return false
    }
}

/// Qwen-MT 可选模型。
enum TranslationModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case flash = "qwen-mt-flash"
    case plus = "qwen-mt-plus"
    case lite = "qwen-mt-lite"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var title: String {
        switch self {
        case .flash: return "Balanced"
        case .plus: return "Best quality"
        case .lite: return "Fastest"
        }
    }

    var detail: String {
        switch self {
        case .flash: return "General purpose. Streaming output, low cost."
        case .plus: return "Professional and formal documents. No streaming."
        case .lite: return "Latency sensitive scenarios. 31 languages."
        }
    }

    /// `qwen-mt-plus` 不支持增量流式输出，需要走一次性返回的通道。
    var supportsStreaming: Bool { self != .plus }
}
