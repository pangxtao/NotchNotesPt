import AppKit
import SwiftUI

/// 翻译页：顶栏方向条 + 左右分栏（左输入 / 右结果）。
struct TranslationView: View {
    @ObservedObject var session: TranslationSessionStore
    @ObservedObject var settings: TranslationSettingsStore
    var onOpenSettings: (() -> Void)?

    private let panelBackground = Color(red: 0.06, green: 0.06, blue: 0.07)
    private let columnHeaderHeight: CGFloat = 26
    private let footerHeight: CGFloat = 30

    var body: some View {
        VStack(spacing: 0) {
            directionBar
            Divider().overlay(.white.opacity(0.07))

            HStack(spacing: 0) {
                sourceColumn
                Divider().overlay(.white.opacity(0.07))
                translationColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(panelBackground)
    }

    // MARK: - Direction bar

    private var directionBar: some View {
        HStack(spacing: 10) {
            Button {
                session.swapDirection()
            } label: {
                HStack(spacing: 6) {
                    Text(session.directionLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Swap direction")

            Button {
                session.toggleAutoDirection()
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(session.isAutoDirection
                              ? Color(red: 0.42, green: 0.72, blue: 1.0)
                              : Color.white.opacity(0.22))
                        .frame(width: 5, height: 5)

                    Text("Auto")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(session.isAutoDirection ? 0.82 : 0.34))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Detect direction automatically")

            Spacer(minLength: 0)

            Menu {
                ForEach(TranslationModel.allCases) { model in
                    Button {
                        session.selectModel(model)
                    } label: {
                        if model == settings.model {
                            Label("\(model.displayName) · \(model.title)", systemImage: "checkmark")
                        } else {
                            Text("\(model.displayName) · \(model.title)")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(session.modelName)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.32))
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }

    // MARK: - Source column

    private var sourceColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader(title: "SOURCE") {
                Button("Clear") {
                    session.clear()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(session.inputText.isEmpty ? 0.24 : 0.46))
                .disabled(session.inputText.isEmpty)
            }

            Divider().overlay(.white.opacity(0.05))

            ZStack(alignment: .topLeading) {
                TextEditor(text: $session.inputText)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.92))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .background(Color.clear)
                    .background(HidesScrollIndicators())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                if session.inputText.isEmpty {
                    Text("Type or paste text…")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.22))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(.white.opacity(0.05))

            HStack(spacing: 8) {
                Text("\(session.characterCount) characters")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))

                Spacer(minLength: 0)

                Button {
                    session.translateNow()
                } label: {
                    Text(session.isTranslating && session.hasTranslation ? "Translating…" : "Translate")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(session.canTranslate ? 0.9 : 0.28))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.white.opacity(session.canTranslate ? 0.13 : 0.05))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!session.canTranslate)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Translate now (⌘↩)")
            }
            .padding(.horizontal, 12)
            .frame(height: footerHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Translation column

    private var translationColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if session.isConfigured {
                columnHeader(title: "TRANSLATION") {
                    HStack(spacing: 12) {
                        Button("Save as note") {
                            session.saveAsNote()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(session.hasTranslation ? 0.46 : 0.22))
                        .disabled(!session.hasTranslation)

                        Button(session.didCopyTranslation ? "Copied" : "Copy") {
                            session.copyTranslation()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(session.hasTranslation ? 0.72 : 0.22))
                        .disabled(!session.hasTranslation)
                    }
                }

                Divider().overlay(.white.opacity(0.05))

                translationContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider().overlay(.white.opacity(0.05))

                HStack(spacing: 8) {
                    if let errorMessage = session.errorMessage {
                        Text(errorMessage.split(separator: ".").first.map(String.init) ?? errorMessage)
                            .font(.system(size: 10))
                            .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.52))
                            .lineLimit(1)
                    } else if session.isTranslating {
                        HStack(spacing: 5) {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.55)
                                .frame(width: 9, height: 9)
                            Text("Translating…")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.38))
                        }
                    } else if let elapsed = session.elapsedLabel {
                        Text(elapsed)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                    }

                    Spacer(minLength: 0)

                    if session.canRetry {
                        Button("Retry") {
                            session.translateNow()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: footerHeight)
            } else {
                notConfiguredCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var translationContent: some View {
        if let errorMessage = session.errorMessage {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.52))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        } else if session.hasTranslation {
            ScrollView {
                Text(session.translatedText)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.95))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        } else {
            Text("Translation appears here.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.22))
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var notConfiguredCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("API key required")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))

            Text("Add your Alibaba Cloud Model Studio (DashScope) key to start translating. It is stored in the macOS Keychain.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onOpenSettings?()
            } label: {
                Text("Open Translation Settings…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.white.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Building blocks

    private func columnHeader<Trailing: View>(
        title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.3))

            Spacer(minLength: 0)

            trailing()
        }
        .padding(.horizontal, 12)
        .frame(height: columnHeaderHeight)
    }
}
