import Foundation

/// OpenAI 兼容的 Chat Completions 请求体。
///
/// 注意：`translation_options` 不是 OpenAI 标准参数，必须放在**顶层**，
/// 官方 SDK 里对应 `extra_body`。
struct TranslationRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Options: Encodable {
        let sourceLang: String
        let targetLang: String

        enum CodingKeys: String, CodingKey {
            case sourceLang = "source_lang"
            case targetLang = "target_lang"
        }
    }

    struct StreamOptions: Encodable {
        let includeUsage: Bool

        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }

    let model: String
    let messages: [Message]
    let translationOptions: Options
    let stream: Bool
    let streamOptions: StreamOptions?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case translationOptions = "translation_options"
        case stream
        case streamOptions = "stream_options"
    }

    init(
        text: String,
        source: TranslationLanguage,
        target: TranslationLanguage,
        model: TranslationModel
    ) {
        self.model = model.rawValue
        messages = [Message(role: "user", content: text)]
        translationOptions = Options(
            sourceLang: source.apiValue,
            targetLang: target.apiValue
        )
        stream = model.supportsStreaming
        streamOptions = model.supportsStreaming ? StreamOptions(includeUsage: true) : nil
    }
}

/// 流式分片与一次性返回共用同一套解析结构。
struct TranslationChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }

        struct Message: Decodable {
            let content: String?
        }

        let delta: Delta?
        let message: Message?
    }

    struct Usage: Decodable {
        let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case totalTokens = "total_tokens"
        }
    }

    let choices: [Choice]?
    let usage: Usage?
    let error: APIErrorBody?
}

struct APIErrorBody: Decodable {
    let message: String?
    let code: String?
    let type: String?

    /// 取第一个非空描述，便于直接展示给用户。
    var preferredMessage: String {
        for candidate in [message, type, code] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return ""
    }
}

/// SSE 行的解析结果，单独抽出来便于单元测试。
enum TranslationSSEEvent: Equatable {
    case payload(String)
    case done
    case ignore

    static func parse(line: String) -> TranslationSSEEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // 空行是事件分隔符，以 `:` 开头的是注释行（部分服务用作心跳）。
        guard !trimmed.isEmpty, !trimmed.hasPrefix(":") else { return .ignore }
        guard trimmed.hasPrefix("data:") else { return .ignore }

        let value = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if value == "[DONE]" { return .done }
        guard !value.isEmpty else { return .ignore }
        return .payload(value)
    }
}

enum TranslationServiceError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidBaseURL
    case emptyInput
    case inputTooLong(Int)
    case unauthorized(String)
    case rateLimited(String)
    case badRequest(String)
    case server(String)
    case network(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key configured. Open Translation Settings to add your Model Studio key."
        case .invalidBaseURL:
            return "The API base URL is not valid. Check it in Translation Settings."
        case .emptyInput:
            return "Nothing to translate."
        case let .inputTooLong(limit):
            return "Text is too long. The limit is \(limit) characters per request."
        case .unauthorized:
            return "The API key was rejected. Check your Model Studio key."
        case .rateLimited:
            return "Too many requests. Wait a moment and try again."
        case let .badRequest(message):
            return message.isEmpty ? "The request was rejected." : message
        case let .server(message):
            return message.isEmpty ? "The translation service is unavailable." : message
        case let .network(message):
            return message.isEmpty ? "Network error. Check your connection." : message
        case .emptyResult:
            return "The service returned an empty translation."
        }
    }
}
