#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="Legado"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BUNDLE="${PROJECT_ROOT}/${APP_NAME}.app"
INFO_PLIST="${PROJECT_ROOT}/Resources/Info.plist"
DIST_DIR="${PROJECT_ROOT}/dist"
REPOSITORY="${REPOSITORY:-Kequans/legado-for-mac-pub}"
TAG=""
TITLE=""
NOTES_FILE=""
UPLOAD=false
REPLACE=false
DRAFT=false
PRERELEASE=false
ALLOW_DIRTY=false
SKIP_BUILD=false
SKIP_DMG=false

usage() {
    cat <<'EOF'
用法:
  ./release.sh [选项]

默认行为:
  构建 Legado.app，并在 dist/ 生成 ZIP、DMG 和 SHA-256 校验文件。

发布到 GitHub:
  ./release.sh --upload --tag v2.0.0

选项:
  --upload                 构建后使用 gh 创建 GitHub Release 并上传附件
  --repo OWNER/REPO       GitHub 仓库，默认 Kequans/legado-for-mac-pub
  --tag TAG                Release tag，默认根据 Info.plist 生成 v<版本号>
  --title TITLE            Release 标题，默认 Legado <版本号>
  --notes-file FILE        使用指定 Markdown 文件作为 Release 说明
  --generate-notes         使用 GitHub 自动生成 Release 说明（默认）
  --draft                  创建 Draft Release
  --prerelease              创建 Pre-release
  --replace                Release 已存在时使用 gh release upload --clobber 覆盖附件
  --allow-dirty             允许工作区有未提交改动后发布
  --skip-build              使用已有的 Legado.app，不重新构建
  --skip-dmg                只生成 ZIP，不生成 DMG
  -h, --help                显示帮助

环境变量:
  CODE_SIGN_IDENTITY        传给 build_app.sh 的签名身份，默认 ad-hoc 签名
  REPOSITORY                默认 GitHub 仓库
  CLANG_MODULE_CACHE_PATH   Swift/Clang 模块缓存目录
  SWIFT_MODULECACHE_PATH    Swift 模块缓存目录
EOF
}

fail() {
    echo "❌ $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "未找到命令: $1"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --upload)
            UPLOAD=true
            shift
            ;;
        --repo)
            [[ $# -ge 2 ]] || fail "--repo 需要参数"
            REPOSITORY="$2"
            shift 2
            ;;
        --tag)
            [[ $# -ge 2 ]] || fail "--tag 需要参数"
            TAG="$2"
            shift 2
            ;;
        --title)
            [[ $# -ge 2 ]] || fail "--title 需要参数"
            TITLE="$2"
            shift 2
            ;;
        --notes-file)
            [[ $# -ge 2 ]] || fail "--notes-file 需要参数"
            NOTES_FILE="$2"
            shift 2
            ;;
        --generate-notes)
            NOTES_FILE=""
            shift
            ;;
        --draft)
            DRAFT=true
            shift
            ;;
        --prerelease)
            PRERELEASE=true
            shift
            ;;
        --replace)
            REPLACE=true
            shift
            ;;
        --allow-dirty)
            ALLOW_DIRTY=true
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --skip-dmg)
            SKIP_DMG=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "未知选项: $1。使用 --help 查看用法。"
            ;;
    esac
done

cd "${PROJECT_ROOT}"

require_command plutil
require_command shasum
require_command ditto
require_command codesign
if [[ "${SKIP_DMG}" == false ]]; then
    require_command hdiutil
fi

if [[ "${UPLOAD}" == true ]]; then
    require_command gh
    require_command git

    if [[ "${ALLOW_DIRTY}" == false ]] && [[ -n "$(git status --porcelain)" ]]; then
        fail "工作区存在未提交改动。请先提交并推送，或使用 --allow-dirty 明确允许发布当前工作区。"
    fi
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "${INFO_PLIST}")"
[[ -n "${VERSION}" ]] || fail "无法从 ${INFO_PLIST} 读取版本号"

TAG="${TAG:-v${VERSION}}"
TITLE="${TITLE:-Legado ${VERSION}}"
ARCH="$(uname -m)"
case "${ARCH}" in
    arm64|x86_64) ;;
    *) fail "不支持的 macOS 架构: ${ARCH}" ;;
esac

if [[ -n "${NOTES_FILE}" ]] && [[ ! -f "${NOTES_FILE}" ]]; then
    fail "找不到 Release 说明文件: ${NOTES_FILE}"
fi

if [[ "${SKIP_BUILD}" == false ]]; then
    echo "🚀 构建 ${APP_NAME}.app"
    : "${CLANG_MODULE_CACHE_PATH:=/tmp/legado-clang-cache}"
    : "${SWIFT_MODULECACHE_PATH:=/tmp/legado-swift-cache}"
    export CLANG_MODULE_CACHE_PATH
    export SWIFT_MODULECACHE_PATH
    BUILD_CONFIGURATION=release "${PROJECT_ROOT}/build_app.sh"
fi

[[ -d "${APP_BUNDLE}" ]] || fail "找不到 ${APP_BUNDLE}，请先运行 build_app.sh"
plutil -lint "${APP_BUNDLE}/Contents/Info.plist" >/dev/null || fail "Info.plist 校验失败"
codesign --verify --deep --strict "${APP_BUNDLE}" || fail "应用代码签名校验失败"

mkdir -p "${DIST_DIR}"
ARTIFACT_NAME="${APP_NAME}-${VERSION}-macOS-${ARCH}"
ZIP_PATH="${DIST_DIR}/${ARTIFACT_NAME}.zip"
DMG_PATH="${DIST_DIR}/${ARTIFACT_NAME}.dmg"
CHECKSUM_PATH="${DIST_DIR}/${ARTIFACT_NAME}.sha256"

rm -f -- "${ZIP_PATH}" "${DMG_PATH}" "${CHECKSUM_PATH}"

echo "📦 生成 ZIP: ${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

ASSETS=("${ZIP_PATH}")
if [[ "${SKIP_DMG}" == false ]]; then
    echo "💿 生成 DMG: ${DMG_PATH}"
    hdiutil create \
        -volname "${APP_NAME} ${VERSION}" \
        -srcfolder "${APP_BUNDLE}" \
        -ov \
        -format UDZO \
        "${DMG_PATH}" >/dev/null
    ASSETS+=("${DMG_PATH}")
fi

(
    cd "${DIST_DIR}"
    for asset in "${ASSETS[@]}"; do
        shasum -a 256 "$(basename "${asset}")"
    done
) > "${CHECKSUM_PATH}"
ASSETS+=("${CHECKSUM_PATH}")

echo "✅ 本地产物已生成"
for asset in "${ASSETS[@]}"; do
    echo "   ${asset}"
done

if [[ "${UPLOAD}" == true ]]; then
    gh auth status >/dev/null 2>&1 || fail "GitHub CLI 尚未登录，请先运行 gh auth login"

    if [[ "${REPLACE}" == true ]]; then
        echo "☁️ 覆盖 Release ${TAG} 的附件"
        gh release upload "${TAG}" "${ASSETS[@]}" \
            --repo "${REPOSITORY}" \
            --clobber
    else
        echo "☁️ 创建 GitHub Release ${TAG}"
        RELEASE_ARGS=(
            "${TAG}"
            "${ASSETS[@]}"
            --repo "${REPOSITORY}"
            --title "${TITLE}"
        )
        if [[ -n "${NOTES_FILE}" ]]; then
            RELEASE_ARGS+=(--notes-file "${NOTES_FILE}")
        else
            RELEASE_ARGS+=(--generate-notes)
        fi
        if [[ "${DRAFT}" == true ]]; then
            RELEASE_ARGS+=(--draft)
        fi
        if [[ "${PRERELEASE}" == true ]]; then
            RELEASE_ARGS+=(--prerelease)
        fi
        gh release create "${RELEASE_ARGS[@]}"
    fi

    echo "🎉 GitHub Release 已处理: https://github.com/${REPOSITORY}/releases/tag/${TAG}"
fi
