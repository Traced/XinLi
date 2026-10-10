#!/bin/bash
# 为仓库中的 docs/ 目录准备某个心历 GitHub Release 的安装包与版本信息。
#
# 用法: scripts/publish-website.sh v1
#   - 从 GitHub Release 下载 Apple 芯片和 Intel 芯片两个安装包
#   - 检查每个安装包的架构、版本号和签名
#   - 复制为 docs/心历-AppleSilicon.zip、docs/心历-Intel.zip
#   - 更新 docs/version.json（网页上显示的版本号）
# 历史页面的下载区域需另行更新；此脚本不部署网站。可用 RELEASE_REPO 指定来源仓库。
# 只能在 macOS 上运行（用到 ditto、lipo、codesign、BSD sed），需要 gh（GitHub CLI）。
set -euo pipefail
cd "$(dirname "$0")/../.."

TAG=${1:?usage: publish-website.sh <tag>, e.g. v1}
VERSION=${TAG#v}
NORMALIZED_VERSION=$VERSION
while [[ "$NORMALIZED_VERSION" == *.0 ]]; do NORMALIZED_VERSION=${NORMALIZED_VERSION%.0}; done
DISPLAY_VERSION="v$NORMALIZED_VERSION"
REPO=${RELEASE_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

gh release download "$TAG" -R "$REPO" -D "$WORK" -p "心历-$DISPLAY_VERSION-*.zip"

check() {  # check <zip> <arch>
    local zip=$1 arch=$2 dir
    [ -f "$zip" ] || { echo "missing $(basename "$zip") in release $TAG" >&2; exit 1; }
    dir=$(mktemp -d "$WORK/check.XXXX")
    ditto -x -k "$zip" "$dir"
    local app="$dir/心历.app"
    local archs version
    archs=$(lipo -archs "$app/Contents/MacOS/XinLi")
    version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
    [ "$archs" = "$arch" ] || { echo "$(basename "$zip"): expected $arch, got $archs" >&2; exit 1; }
    local normalized_version=$version
    while [[ "$normalized_version" == *.0 ]]; do normalized_version=${normalized_version%.0}; done
    [ "$normalized_version" = "$NORMALIZED_VERSION" ] || { echo "$(basename "$zip"): expected version $VERSION, got $version" >&2; exit 1; }
    codesign --verify "$app"
    echo "ok  $(basename "$zip"): $archs, version $version"
}

check "$WORK/心历-$DISPLAY_VERSION-AppleSilicon.zip" arm64
check "$WORK/心历-$DISPLAY_VERSION-Intel.zip" x86_64

cp "$WORK/心历-$DISPLAY_VERSION-AppleSilicon.zip" docs/心历-AppleSilicon.zip
cp "$WORK/心历-$DISPLAY_VERSION-Intel.zip" docs/心历-Intel.zip
cat > docs/version.json <<JSON
{
  "version": "$VERSION",
  "tag": "$TAG",
  "files": {
    "AppleSilicon": "心历-AppleSilicon.zip",
    "Intel": "心历-Intel.zip"
  }
}
JSON
# 网页中的后备版本号（version.json 读取失败时显示）
sed -i '' -E "s#(<span class=\"app-version\">)[^<]*(</span>)#\1$VERSION\2#g" docs/index.html
grep -q "<span class=\"app-version\">$VERSION</span>" docs/index.html ||
    { echo "docs/index.html: <span class=\"app-version\"> not found, update the fallback version by hand" >&2; exit 1; }

echo "Website updated to $VERSION. Review and commit:"
git status --short docs/
