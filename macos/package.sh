#!/bin/bash
#
# 打包分发产物：DMG（拖拽安装）+ PKG（装到 /Applications）+ SHA256。
#
#   bash macos/package.sh              通用二进制
#   bash macos/package.sh --arm64      仅本机架构
#
# 产物在 dist/：
#   function-plotter-<版本>.dmg
#   function-plotter-<版本>.pkg
#   SHA256SUMS.txt
#
# 说明：
# - 未签名公证的产物在其他机器上首次打开会被 Gatekeeper 拦，
#   需要右键「打开」或在「系统设置 → 隐私与安全性」里放行。
# - 本脚本不使用 rm；重复打包由 hdiutil -ov / pkgbuild 覆盖。

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="函数画板"
EXEC_NAME="FunctionPlot"
BUNDLE_ID="cn.geoboard.functionplotter"
SLUG="function-plotter"

# shellcheck source=version.env
source ./version.env

DIST="../dist"
APP="build/${APP_NAME}.app"

ARCH_ARG="--universal"
for arg in "$@"; do
	case "$arg" in
		--arm64) ARCH_ARG="--arm64" ;;
		--universal) ARCH_ARG="--universal" ;;
		*) echo "未知参数：${arg}" >&2; exit 2 ;;
	esac
done

# ---------------------------------------------------------------- 先构建

echo "==> 构建应用"
bash ./build.sh "${ARCH_ARG}"

if [ ! -d "${APP}" ]; then
	echo "构建产物不存在：${APP}" >&2
	exit 1
fi

mkdir -p "${DIST}"

DMG="${DIST}/${SLUG}-${APP_VERSION}.dmg"
PKG="${DIST}/${SLUG}-${APP_VERSION}.pkg"
SUMS="${DIST}/SHA256SUMS.txt"

# ---------------------------------------------------------------- DMG
# 卷标用中文，文件名保持 ASCII，避免跨平台与命令行转义问题。
# 暂存目录用 mktemp：每次全新，不残留上一轮的文件，也不涉及删除操作。

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/fp-dmg.XXXXXX")"
ditto --norsrc --noextattr --noacl "${APP}" "${STAGE}/${APP_NAME}.app"
ln -sfn /Applications "${STAGE}/Applications"

echo "==> 生成 DMG"
hdiutil create \
	-volname "${APP_NAME}" \
	-srcfolder "${STAGE}" \
	-ov -format UDZO \
	"${DMG}" 2>&1 | sed 's/^/    /'

# ---------------------------------------------------------------- PKG
# PKG 只装 .app，安装位置 /Applications

PKG_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/fp-pkg.XXXXXX")"
ditto --norsrc --noextattr --noacl "${APP}" "${PKG_ROOT}/${APP_NAME}.app"

echo "==> 生成 PKG"
pkgbuild \
	--root "${PKG_ROOT}" \
	--identifier "${BUNDLE_ID}" \
	--version "${APP_VERSION}" \
	--install-location "/Applications" \
	"${PKG}" 2>&1 | sed 's/^/    /' || {
	echo ""
	echo "!! PKG 生成失败（通常是权限或组件路径问题），DMG 仍可用。" >&2
}

# ---------------------------------------------------------------- 校验和

echo "==> 计算校验和"
: > "${SUMS}"
for f in "${DMG}" "${PKG}"; do
	if [ -f "${f}" ]; then
		( cd "${DIST}" && shasum -a 256 "$(basename "${f}")" >> SHA256SUMS.txt )
	fi
done

# ---------------------------------------------------------------- 结果

echo ""
echo "==> 打包完成"
echo "    版本：${APP_VERSION}（${BUILD_NUMBER}）"
echo "    架构：$(lipo -archs "${APP}/Contents/MacOS/${EXEC_NAME}")"
for f in "${DMG}" "${PKG}"; do
	if [ -f "${f}" ]; then
		printf "    %s  %s\n" "$(du -h "${f}" | cut -f1)" "$(basename "${f}")"
	fi
done
echo ""
cat "${SUMS}" | sed 's/^/    /'
