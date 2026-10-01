import Combine
import Foundation

@MainActor
final class TranslationSettingsStore: ObservableObject {
    /// 中国内地（北京）地域的 OpenAI 兼容入口。
    static let defaultBaseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"

    private static let apiKeyAccount = "dashscope.apiKey"
    private static let modelKey = "notchNotes.translation.model"
    private static let baseURLKey = "notchNotes.translation.baseURL"
    private static let autoTranslateKey = "notchNotes.translation.autoTranslate"
    private static let selectionEnabledKey = "notchNotes.translation.selectionEnabled"
    private static let hotKeyKey = "notchNotes.translation.hotKey"

    /// API Key 只写 Keychain，不落 UserDefaults。
    @Published var apiKey: String {
        didSet {
            guard apiKey != oldValue else { return }
            if apiKey.isEmpty {
                KeychainStore.delete(account: Self.apiKeyAccount)
            } else {
                KeychainStore.save(apiKey, account: Self.apiKeyAccount)
            }
        }
    }

    @Published var model: TranslationModel {
        didSet {
            defaults.set(model.rawValue, forKey: Self.modelKey)
        }
    }

    @Published var baseURLString: String {
        didSet {
            defaults.set(baseURLString, forKey: Self.baseURLKey)
        }
    }

    /// 输入停顿后自动翻译。关闭后需手动触发。
    @Published var autoTranslate: Bool {
        didSet {
            defaults.set(autoTranslate, forKey: Self.autoTranslateKey)
        }
    }

    @Published var isSelectionTranslationEnabled: Bool {
        didSet {
            defaults.set(isSelectionTranslationEnabled, forKey: Self.selectionEnabledKey)
        }
    }

    @Published var selectionHotKey: HotKeySpec {
        didSet {
            guard let data = try? JSONEncoder().encode(selectionHotKey) else { return }
            defaults.set(data, forKey: Self.hotKeyKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        apiKey = KeychainStore.read(account: Self.apiKeyAccount) ?? ""
        model = defaults.string(forKey: Self.modelKey)
            .flatMap(TranslationModel.init(rawValue:)) ?? .flash
        baseURLString = defaults.string(forKey: Self.baseURLKey) ?? Self.defaultBaseURL

        autoTranslate = defaults.object(forKey: Self.autoTranslateKey) as? Bool ?? true
        isSelectionTranslationEnabled = defaults.object(forKey: Self.selectionEnabledKey) as? Bool ?? true

        let storedHotKey = defaults.data(forKey: Self.hotKeyKey)
            .flatMap { try? JSONDecoder().decode(HotKeySpec.self, from: $0) }
        selectionHotKey = storedHotKey ?? .optionQ
    }

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canTranslateWithSelection: Bool {
        isSelectionTranslationEnabled
    }
}
