import AppKit
import SwiftUI

struct TranslationPopupView: View {
    @ObservedObject var controller: SelectionTranslationController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(.white.opacity(0.07))

            if controller.needsAccessibilityPermission {
                permissionBody
            } else if isWaitingForFirstToken {
                loadingBody
            } else {
                translationBody
                Divider().overlay(.white.opacity(0.07))
                actionRow
            }
        }
        .frame(width: TranslationPopupPanel.preferredWidth)
        .background(Color(red: 0.02, green: 0.02, blue: 0.025).opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
    }

    /// 已经开始翻译但还没拿到第一个字。
    private var isWaitingForFirstToken: Bool {
        controller.isTranslating
            && controller.translatedText.isEmpty
            && controller.errorMessage == nil
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 9) {
            if !controller.needsAccessibilityPermission {
                Text(controller.directionLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    }
            } else {
                Text("Accessibility")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
            }

            Text(controller.modelName)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.36))

            Spacer(minLength: 0)

            Button {
                controller.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, TranslationPopupMetrics.horizontalPadding)
        .padding(.top, 11)
        .padding(.bottom, 9)
        .frame(minHeight: TranslationPopupMetrics.headerHeight)
    }

    /// 等待首个字返回：只显示状态，不显示原文与按钮，避免弹窗尺寸来回跳。
    private var loadingBody: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.7)
                .frame(width: 12, height: 12)

            Text("Translating…")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(
            maxWidth: .infinity,
            minHeight: TranslationPopupMetrics.loadingHeight
                - TranslationPopupMetrics.headerHeight
                - TranslationPopupMetrics.dividerHeight,
            alignment: .leading
        )
        .padding(.horizontal, TranslationPopupMetrics.horizontalPadding)
    }

    @ViewBuilder
    private var translationBody: some View {
        if let errorMessage = controller.errorMessage {
            VStack(alignment: .leading, spacing: 6) {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.52))
                    .fixedSize(horizontal: false, vertical: true)

                if let hint = controller.failureHint {
                    Text(hint)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.32))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TranslationPopupMetrics.horizontalPadding)
            .padding(.vertical, 10)
            .frame(height: errorBodyHeight, alignment: .topLeading)
        } else {
            // ScrollView 必须配显式高度：否则 SwiftUI 算不出尺寸，
            // 窗口会比内容矮、底部按钮被裁掉。
            ScrollView {
                Text(controller.translatedText)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.95))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, TranslationPopupMetrics.horizontalPadding)
                    .padding(.vertical, 10)
            }
            .frame(height: translationBodyHeight)
        }
    }

    private var translationBodyHeight: CGFloat {
        TranslationPopupMetrics.bodyHeight(
            for: controller.translatedText,
            fontSize: 13,
            verticalPadding: 10
        )
    }

    private var errorBodyHeight: CGFloat {
        TranslationPopupMetrics.errorBodyHeight(
            message: controller.errorMessage ?? "",
            hint: controller.failureHint
        )
    }

    private var actionRow: some View {
        HStack(spacing: 14) {
            if controller.canRetry {
                Button("Retry") {
                    controller.retry()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
            }

            Button("Swap") {
                controller.swapAndRetranslate()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.46))

            Button("Save as note") {
                controller.saveAsNote()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.46))

            Spacer(minLength: 0)

            Button {
                controller.copyTranslation()
            } label: {
                Text(controller.didCopyTranslation ? "Copied" : "Copy")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(controller.hasTranslation ? 0.9 : 0.28))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.white.opacity(controller.hasTranslation ? 0.12 : 0.04))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!controller.hasTranslation)
        }
        .padding(.horizontal, TranslationPopupMetrics.horizontalPadding)
        .padding(.vertical, 9)
        .frame(minHeight: TranslationPopupMetrics.actionRowHeight)
    }

    private var permissionBody: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("NotchNotes needs Accessibility permission to read the selected text.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    AccessibilityPermission.request()
                } label: {
                    Text("Re-trigger Prompt")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.white.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    AccessibilityPermission.openSystemSettings()
                } label: {
                    Text("Open System Settings")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)

                Button("Try again") {
                    controller.retryAfterPermissionGrant()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
            }

            Text("If NotchNotes is already enabled in System Settings, the binary fingerprint may have changed. Remove it from the list and add it again.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.34))
                .fixedSize(horizontal: false, vertical: true)

            Text(AccessibilityPermission.currentBundlePath)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.22))
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(.horizontal, TranslationPopupMetrics.horizontalPadding)
        .padding(.top, 4)
        .padding(.bottom, 13)
        .frame(
            minHeight: TranslationPopupMetrics.permissionHeight
                - TranslationPopupMetrics.headerHeight
                - TranslationPopupMetrics.dividerHeight,
            alignment: .topLeading
        )
    }
}
