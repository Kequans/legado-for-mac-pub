#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="Legado"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BUNDLE="${PROJECT_ROOT}/${APP_NAME}.app"
ICON_SOURCE_DIR="${PROJECT_ROOT}/Resources/Assets.xcassets/AppIcon.appiconset"
ICONSET_DIR="${PROJECT_ROOT}/.build/${APP_NAME}.iconset"
INFO_PLIST="${PROJECT_ROOT}/Resources/Info.plist"

cleanup() {
    rm -rf -- "${ICONSET_DIR}"
}
trap cleanup EXIT

cd "${PROJECT_ROOT}"

case "${BUILD_CONFIGURATION}" in
    debug|release) ;;
    *)
        echo "❌ BUILD_CONFIGURATION 必须是 debug 或 release，当前值: ${BUILD_CONFIGURATION}" >&2
        exit 2
        ;;
esac

for command in swift iconutil codesign plutil; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "❌ 未找到构建依赖: ${command}" >&2
        exit 1
    fi
done

echo "🚀 开始构建 ${APP_NAME}.app"
echo "📦 编译配置: ${BUILD_CONFIGURATION}"

echo "📦 编译 SwiftPM 产品..."
swift build \
    --configuration "${BUILD_CONFIGURATION}" \
    --product "${APP_NAME}"

BIN_DIR="$(swift build --show-bin-path --configuration "${BUILD_CONFIGURATION}")"
BINARY_PATH="${BIN_DIR}/${APP_NAME}"

if [[ ! -x "${BINARY_PATH}" ]]; then
    echo "❌ 找不到可执行文件: ${BINARY_PATH}" >&2
    exit 1
fi

if [[ ! -f "${INFO_PLIST}" ]]; then
    echo "❌ 找不到应用 Info.plist: ${INFO_PLIST}" >&2
    exit 1
fi

echo "🧹 清理旧的应用包..."
rm -rf -- "${APP_BUNDLE}"
mkdir -p \
    "${APP_BUNDLE}/Contents/MacOS" \
    "${APP_BUNDLE}/Contents/Resources"

echo "📋 写入应用文件..."
cp "${BINARY_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${INFO_PLIST}" "${APP_BUNDLE}/Contents/Info.plist"
chmod 755 "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

echo "🎨 生成 AppIcon.icns..."
mkdir -p "${ICONSET_DIR}"
icon_names=(
    "icon_16x16.png"
    "icon_16x16@2x.png"
    "icon_32x32.png"
    "icon_32x32@2x.png"
    "icon_128x128.png"
    "icon_128x128@2x.png"
    "icon_256x256.png"
    "icon_256x256@2x.png"
    "icon_512x512.png"
    "icon_512x512@2x.png"
)

for icon_name in "${icon_names[@]}"; do
    icon_path="${ICON_SOURCE_DIR}/${icon_name}"
    if [[ ! -f "${icon_path}" ]]; then
        echo "❌ 缺少图标资源: ${icon_path}" >&2
        exit 1
    fi
    cp "${icon_path}" "${ICONSET_DIR}/${icon_name}"
done

iconutil -c icns "${ICONSET_DIR}" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

echo "🔐 使用代码签名..."
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
codesign \
    --force \
    --deep \
    --sign "${CODE_SIGN_IDENTITY}" \
    "${APP_BUNDLE}"

echo "✅ 验证应用包..."
plutil -lint "${APP_BUNDLE}/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "${APP_BUNDLE}"

required_files=(
    "${APP_BUNDLE}/Contents/Info.plist"
    "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
    "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
)
for required_file in "${required_files[@]}"; do
    if [[ ! -e "${required_file}" ]]; then
        echo "❌ 应用包缺少文件: ${required_file}" >&2
        exit 1
    fi
done

echo
echo "🎉 构建完成"
echo "📦 应用位置: ${APP_BUNDLE}"
echo "📊 应用大小: $(du -sh "${APP_BUNDLE}" | awk '{print $1}')"
echo
echo "运行方式:"
echo "  open \"${APP_BUNDLE}\""
echo
echo "自定义签名证书:"
echo "  CODE_SIGN_IDENTITY=\"Developer ID Application: Your Name\" ./build_app.sh"
