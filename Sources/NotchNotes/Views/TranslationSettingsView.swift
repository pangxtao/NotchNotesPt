import AppKit
import SwiftUI

struct TranslationSettingsView: View {
    @ObservedObject var settings: TranslationSettingsStore
    var onClose: (() -> Void)?

    @State private var isKeyVisible = false
    @State private var isAccessibilityGranted = AccessibilityPermission.isTrusted
    @State private var didCopyHotKeyHint = false

    private let cardBackground = Color.white.opacity(0.04)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(.white.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    apiKeySection
                    modelSection
                    behaviourSection
                    selectionSection
                    permissionSection
                    advancedSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 480, height: 560)
        .background(Color(red: 0.07, green: 0.07, blue: 0.08))
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Translation Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            Spacer(minLength: 0)

            Button("Done") {
                onClose?()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.12))
            )
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
    }

    // MARK: - Sections

    private var apiKeySection: some View {
        section(title: "API Key", caption: "Stored in the macOS Keychain, never in a plist.") {
            HStack(spacing: 8) {
                Group {
                    if isKeyVisible {
                        TextField("sk-…", text: $settings.apiKey)
                    } else {
                        SecureField("sk-…", text: $settings.apiKey)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.black.opacity(0.28))
                )

                Button(isKeyVisible ? "Hide" : "Show") {
                    isKeyVisible.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 44)
            }

            Link(
                "Open Model Studio console ›",
                destination: URL(string: "https://bailian.console.aliyun.com/")!
            )
            .font(.system(size: 11))
            .foregroundStyle(Color(red: 0.45, green: 0.72, blue: 1.0))
        }
    }

    private var modelSection: some View {
        section(title: "Model", caption: nil) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(TranslationModel.allCases) { model in
                    Button {
                        settings.model = model
                    } label: {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: settings.model == model ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(settings.model == model ? 0.86 : 0.3))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(model.displayName) · \(model.title)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.88))

                                Text(model.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.4))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var behaviourSection: some View {
        section(title: "Behaviour", caption: nil) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $settings.autoTranslate) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Translate automatically")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.88))
                        Text("Starts translating 600 ms after you stop typing.")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    private var selectionSection: some View {
        section(
            title: "Translate Selected Text",
            caption: "Select text in any app, then press the shortcut."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $settings.isSelectionTranslationEnabled) {
                    Text("Enable selection translation")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.88))
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                HStack(spacing: 8) {
                    Text("Shortcut")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer(minLength: 0)

                    Picker("", selection: $settings.selectionHotKey) {
                        ForEach(HotKeySpec.allCases) { spec in
                            Text(spec.displayString).tag(spec)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 110)
                    .disabled(!settings.isSelectionTranslationEnabled)
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        settings.selectionHotKey.displayString,
                        forType: .string
                    )
                    didCopyHotKeyHint = true

                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.4))
                        didCopyHotKeyHint = false
                    }
                } label: {
                    Text(didCopyHotKeyHint ? "Copied" : "Copy shortcut")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var permissionSection: some View {
        section(title: "Accessibility Permission", caption: nil) {
            HStack(spacing: 9) {
                Circle()
                    .fill(isAccessibilityGranted
                          ? Color(red: 0.4, green: 0.78, blue: 0.5)
                          : Color(red: 1.0, green: 0.62, blue: 0.35))
                    .frame(width: 6, height: 6)

                Text(isAccessibilityGranted ? "Granted" : "Not granted")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.82))

                Spacer(minLength: 0)

                Button("Refresh") {
                    isAccessibilityGranted = AccessibilityPermission.isTrusted
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))

                Button("Open Settings") {
                    AccessibilityPermission.openSystemSettings()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
            }

            Text("Required to read the selected text. If the shortcut stops working after an update, remove NotchNotes from the list and re-add it.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.36))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var advancedSection: some View {
        section(title: "Advanced", caption: nil) {
            VStack(alignment: .leading, spacing: 6) {
                Text("API Base URL")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))

                TextField("https://dashscope.aliyuncs.com/compatible-mode/v1", text: $settings.baseURLString)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.black.opacity(0.28))
                    )

                Button("Reset to default") {
                    settings.baseURLString = TranslationSettingsStore.defaultBaseURL
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(
        title: String,
        caption: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.34))

                if let caption {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(cardBackground)
                )
        }
    }
}
