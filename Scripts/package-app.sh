#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# 构建产物名（来自 Package.swift 的 executable target），改 app 名时不要动它。
APP_NAME="NotchNotes"
# .app 包名 / 二进制名 / Info.plist 中的可执行文件名。
# Bundle Identifier 刻意保持不变（io.github.oiloil.NotchNotes），
# 否则 macOS 的 TCC 辅助功能授权记录会失效，需要重新授权。
BUNDLE_NAME="${BUNDLE_NAME:-NotchNotesPt}"
APP_VERSION="${APP_VERSION:-0.2.1}"
BUILD_NUMBER="${BUILD_NUMBER:-35}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/.build/release-universal}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist.noindex}"
APP_DIR="$DIST_DIR/$BUNDLE_NAME.app"
ZIP_PATH="$DIST_DIR/$BUNDLE_NAME.zip"
CHECKSUM_PATH="$ZIP_PATH.sha256"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SOURCE_ICON="$ROOT_DIR/Resources/AppIcon.png"
SOURCE_PLIST="$ROOT_DIR/Resources/Info.plist"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
# 供 CI 等特殊环境透传额外参数（本机开发留空即可）。
SWIFT_BUILD_ARGS="${SWIFT_BUILD_ARGS:-}"

# 优先使用 Apple Development 证书签名。
#
# ad-hoc 签名（"-"）下，macOS 的 TCC 权限（辅助功能等）与二进制的 cdhash 绑定，
# 每次重新构建后 cdhash 变化，已授予的权限会失效——表现为「系统设置里明明开着，
# 应用却仍提示没有权限」。使用带 Team ID 的开发者证书签名后，权限记录随身份
# 保持稳定，重新构建无需重复授权。
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -m1 'Apple Development' \
    | sed -E 's/.*"(.*)"/\1/')" || true

  if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="-"
    echo "提示：未找到 Apple Development 证书，回退到 ad-hoc 签名（辅助功能权限可能需重新授权）。" >&2
  else
    echo "签名身份：$SIGN_IDENTITY"
  fi
fi

cd "$ROOT_DIR"
# shellcheck disable=SC2086
swift build \
  $SWIFT_BUILD_ARGS \
  -c release \
  --arch arm64 \
  --arch x86_64 \
  --scratch-path "$BUILD_DIR"

# Swift 6 / Xcode 27 的产物目录结构为 out/Products/Release；旧版为 apple/Products/Release。
# 先做新路径 fallback，再兼容旧路径。
BINARY_PATH="$BUILD_DIR/out/Products/Release/$APP_NAME"
if [[ ! -x "$BINARY_PATH" ]]; then
  BINARY_PATH="$BUILD_DIR/apple/Products/Release/$APP_NAME"
fi
if [[ ! -x "$BINARY_PATH" ]]; then
  echo "找不到构建产物：$BINARY_PATH" >&2
  echo "请检查 swift build 是否成功，或产物目录结构是否变更。" >&2
  exit 1
fi

ARCHS="$(lipo -archs "$BINARY_PATH")"
if [[ "$ARCHS" != *"arm64"* || "$ARCHS" != *"x86_64"* ]]; then
  echo "构建产物不是通用架构：$ARCHS" >&2
  exit 1
fi

rm -rf "$APP_DIR"
rm -f "$ZIP_PATH" "$CHECKSUM_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY_PATH" "$MACOS_DIR/$BUNDLE_NAME"
cp "$SOURCE_PLIST" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleExecutable -string "$BUNDLE_NAME" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleName -string "$BUNDLE_NAME" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleDisplayName -string "$BUNDLE_NAME" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"

if [[ -f "$SOURCE_ICON" ]]; then
  TMP_ICON_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_ICON_DIR"' EXIT
  ICONSET_DIR="$TMP_ICON_DIR/AppIcon.iconset"
  mkdir -p "$ICONSET_DIR"

  sips -z 16 16 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
  rm -rf "$TMP_ICON_DIR"
  trap - EXIT
fi

xattr -cr "$APP_DIR"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP_DIR"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

create_archive() {
  rm -f "$ZIP_PATH"
  ditto --norsrc -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
}

create_archive

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "公证需要 Developer ID 签名，请设置 SIGN_IDENTITY。" >&2
    exit 1
  fi

  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_DIR"
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
  spctl --assess --type execute --verbose=2 "$APP_DIR"
  create_archive
fi

(
  cd "$DIST_DIR"
  shasum -a 256 "$BUNDLE_NAME.zip" > "$BUNDLE_NAME.zip.sha256"
)

echo "Built $APP_DIR"
echo "Architectures: $ARCHS"
echo "Archive: $ZIP_PATH"
echo "Checksum: $CHECKSUM_PATH"
