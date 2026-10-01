import Foundation

/// 阿里云百炼 Qwen-MT 的 HTTP 客户端。
///
/// - `qwen-mt-flash` / `qwen-mt-lite` 支持增量流式，逐字返回。
/// - `qwen-mt-plus` 不支持流式，走一次性返回通道。
final class TranslationService: Sendable {
    static let maximumInputLength = 5000

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func translate(
        text: String,
        source: TranslationLanguage,
        target: TranslationLanguage,
        model: TranslationModel,
        apiKey: String,
        baseURLString: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(
                        text: text,
                        source: source,
                        target: target,
                        model: model,
                        apiKey: apiKey,
                        baseURLString: baseURLString
                    ) { delta in
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Request pipeline

    private func run(
        text: String,
        source: TranslationLanguage,
        target: TranslationLanguage,
        model: TranslationModel,
        apiKey: String,
        baseURLString: String,
        onDelta: (String) -> Void
    ) async throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw TranslationServiceError.missingAPIKey }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { throw TranslationServiceError.emptyInput }
        guard trimmedText.count <= Self.maximumInputLength else {
            throw TranslationServiceError.inputTooLong(Self.maximumInputLength)
        }

        let request = try makeRequest(
            url: try endpointURL(from: baseURLString),
            apiKey: trimmedKey,
            body: TranslationRequest(
                text: trimmedText,
                source: source,
                target: target,
                model: model
            )
        )

        TranslationLogger.log(
            "Request: model=\(model.rawValue), source=\(source.apiValue), target=\(target.apiValue), " +
            "baseURL=\(baseURLString), key=\(TranslationLogger.maskedAPIKey(apiKey))"
        )

        do {
            if model.supportsStreaming {
                try await consumeStream(request: request, onDelta: onDelta)
            } else {
                try await consumeWholeResponse(request: request, onDelta: onDelta)
            }
        } catch let error as TranslationServiceError {
            TranslationLogger.log("Service error: \(error)")
            throw error
        } catch is CancellationError {
            TranslationLogger.log("Request cancelled.")
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            TranslationLogger.log("Network error: \(error.localizedDescription)")
            throw TranslationServiceError.network(error.localizedDescription)
        } catch let error as DecodingError {
            TranslationLogger.log("Decoding error: \(error)")
            throw TranslationServiceError.server(error.localizedDescription)
        } catch {
            TranslationLogger.log("Unexpected error: \(error)")
            throw TranslationServiceError.server(error.localizedDescription)
        }
    }

    private func makeRequest(url: URL, apiKey: String, body: TranslationRequest) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func endpointURL(from baseURLString: String) throws -> URL {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let base = URL(string: trimmed),
              base.scheme != nil,
              base.host != nil else {
            throw TranslationServiceError.invalidBaseURL
        }

        return base.appendingPathComponent("chat/completions")
    }

    private func consumeStream(
        request: URLRequest,
        onDelta: (String) -> Void
    ) async throws {
        let (bytes, response) = try await session.bytes(for: request)
        let decoder = JSONDecoder()

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            let body = String(data: data, encoding: .utf8) ?? "(non-utf8)"
            TranslationLogger.log("HTTP \(http.statusCode): \(body.prefix(500))")
            throw Self.mapError(status: http.statusCode, data: data)
        }

        var producedAny = false
        var lineCount = 0

        for try await line in bytes.lines {
            try Task.checkCancellation()
            lineCount += 1

            switch TranslationSSEEvent.parse(line: line) {
            case .ignore:
                continue
            case .done:
                TranslationLogger.log("Stream ended after \(lineCount) lines. producedAny=\(producedAny)")
                return
            case let .payload(payload):
                guard let data = payload.data(using: .utf8),
                      let chunk = try? decoder.decode(TranslationChunk.self, from: data) else {
                    TranslationLogger.log("Failed to decode payload: \(payload.prefix(200))")
                    continue
                }

                if let error = chunk.error {
                    TranslationLogger.log("API error in stream: \(error)")
                    throw Self.mapAPIError(error)
                }

                guard let content = chunk.choices?.first?.delta?.content,
                      !content.isEmpty else {
                    continue
                }

                producedAny = true
                TranslationLogger.log("Stream delta: \(content.count) chars")
                onDelta(content)
            }
        }

        TranslationLogger.log("Stream exhausted. lines=\(lineCount), producedAny=\(producedAny)")
        guard producedAny else { throw TranslationServiceError.emptyResult }
    }

    private func consumeWholeResponse(
        request: URLRequest,
        onDelta: (String) -> Void
    ) async throws {
        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "(non-utf8)"
            TranslationLogger.log("HTTP \(http.statusCode): \(body.prefix(500))")
            throw Self.mapError(status: http.statusCode, data: data)
        }

        let chunk = try JSONDecoder().decode(TranslationChunk.self, from: data)
        if let error = chunk.error {
            TranslationLogger.log("API error in whole response: \(error)")
            throw Self.mapAPIError(error)
        }

        guard let content = chunk.choices?.first?.message?.content,
              !content.isEmpty else {
            TranslationLogger.log("Empty whole response: \(data.count) bytes")
            throw TranslationServiceError.emptyResult
        }

        TranslationLogger.log("Whole response: \(content.count) chars")
        onDelta(content)
    }

    // MARK: - Error mapping

    static func mapError(status: Int, data: Data) -> TranslationServiceError {
        let decoded = try? JSONDecoder().decode(TranslationChunk.self, from: data)
        let body = decoded?.error
        let message = body?.preferredMessage ?? String(data: data, encoding: .utf8) ?? ""
        let code = body?.code ?? ""

        if code == "invalid_api_key" || message.localizedCaseInsensitiveContains("api key") {
            return .unauthorized(message)
        }

        switch status {
        case 401, 403:
            return .unauthorized(message)
        case 429:
            return .rateLimited(message)
        case 400...499:
            return .badRequest(message)
        default:
            return .server(message)
        }
    }

    static func mapAPIError(_ body: APIErrorBody) -> TranslationServiceError {
        let code = body.code ?? ""
        let message = body.preferredMessage

        if code == "invalid_api_key" || message.localizedCaseInsensitiveContains("api key") {
            return .unauthorized(message)
        }

        if code.contains("throttl") || code.contains("rate") {
            return .rateLimited(message)
        }

        return .server(message)
    }
}
