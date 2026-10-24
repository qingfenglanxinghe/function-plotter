#!/bin/bash
#
# 构建「函数画板.app」——纯命令行，不打开 Xcode。
#
#   bash macos/build.sh              通用二进制（arm64 + x86_64）
#   bash macos/build.sh --arm64      仅本机架构，构建更快
#   REBUILD_ICON=1 bash macos/build.sh   强制重新生成图标
#
# 产物：macos/build/函数画板.app
#
# 注意：本脚本不使用 rm / rm -rf。旧产物由 ditto 覆盖，无需删除。

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="函数画板"
EXEC_NAME="FunctionPlot"
BUNDLE_ID="cn.geoboard.functionplotter"
OUT="build"
APP="${OUT}/${APP_NAME}.app"

# shellcheck source=version.env
source ./version.env

UNIVERSAL=1
for arg in "$@"; do
	case "$arg" in
		--arm64) UNIVERSAL=0 ;;
		--universal) UNIVERSAL=1 ;;
		*) echo "未知参数：${arg}" >&2; exit 2 ;;
	esac
done

echo "==> 构建 ${APP_NAME} ${APP_VERSION}（${BUILD_NUMBER}）"

mkdir -p "${OUT}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"

# ---------------------------------------------------------------- 可执行文件

SRC="Sources/main.swift Sources/Scheme.swift"
if [ ! -f "Sources/main.swift" ] || [ ! -f "Sources/Scheme.swift" ]; then
	echo "找不到 Sources/main.swift 或 Sources/Scheme.swift" >&2
	exit 1
fi

if [ "${UNIVERSAL}" = "1" ]; then
	echo "==> 编译 arm64"
	swiftc -swift-version 5 -O -target arm64-apple-macosx12.0 \
		-o "${OUT}/${EXEC_NAME}-arm64" ${SRC}

	echo "==> 编译 x86_64"
	swiftc -swift-version 5 -O -target x86_64-apple-macosx12.0 \
		-o "${OUT}/${EXEC_NAME}-x86_64" ${SRC}

	lipo -create \
		-output "${OUT}/${EXEC_NAME}" \
		"${OUT}/${EXEC_NAME}-arm64" \
		"${OUT}/${EXEC_NAME}-x86_64"
else
	echo "==> 编译本机架构"
	swiftc -swift-version 5 -O -o "${OUT}/${EXEC_NAME}" ${SRC}
fi

chmod +x "${OUT}/${EXEC_NAME}"
ditto --norsrc --noextattr --noacl "${OUT}/${EXEC_NAME}" "${APP}/Contents/MacOS/${EXEC_NAME}"

# ---------------------------------------------------------------- 图标

ICON="${OUT}/AppIcon.icns"
if [ ! -f "${ICON}" ] || [ "${REBUILD_ICON:-0}" = "1" ]; then
	echo "==> 生成图标"
	swift make-icon.swift "${OUT}/AppIcon-1024.png"

	ICONSET="${OUT}/AppIcon.iconset"
	mkdir -p "${ICONSET}"

	for s in 16 32 128 256 512; do
		sips -z "${s}" "${s}" "${OUT}/AppIcon-1024.png" \
			--out "${ICONSET}/icon_${s}x${s}.png" >/dev/null
		d=$((s * 2))
		sips -z "${d}" "${d}" "${OUT}/AppIcon-1024.png" \
			--out "${ICONSET}/icon_${s}x${s}@2x.png" >/dev/null
	done

	iconutil -c icns "${ICONSET}" -o "${ICON}"
fi

ditto --norsrc --noextattr --noacl "${ICON}" "${APP}/Contents/Resources/AppIcon.icns"

# ---------------------------------------------------------------- 网页资源

WEB="$(cd .. && pwd)/index.html"
if [ ! -f "${WEB}" ]; then
	echo "找不到 ${WEB}" >&2
	exit 1
fi
echo "==> 打包网页资源"
ditto --norsrc --noextattr --noacl "${WEB}" "${APP}/Contents/Resources/index.html"

# ---------------------------------------------------------------- Info.plist

echo "==> 写入 Info.plist"
cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
	<key>CFBundleExecutable</key><string>${EXEC_NAME}</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key><string>${APP_NAME}</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>${APP_VERSION}</string>
	<key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
	<key>LSMinimumSystemVersion</key><string>12.0</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.education</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

# ---------------------------------------------------------------- 签名

echo "==> ad-hoc 签名"
codesign --force --sign - --timestamp=none "${APP}" 2>&1 | sed 's/^/    /' || true

# ---------------------------------------------------------------- 结果

echo ""
echo "==> 完成：${APP}"
if [ "${UNIVERSAL}" = "1" ]; then
	echo "    架构：$(lipo -archs "${APP}/Contents/MacOS/${EXEC_NAME}")"
else
	echo "    架构：$(lipo -archs "${APP}/Contents/MacOS/${EXEC_NAME}")"
fi
echo "    体积：$(du -sh "${APP}" | cut -f1)"
echo "    版本：${APP_VERSION}（${BUILD_NUMBER}）"
echo ""
echo "    打开：open \"${APP}\""
