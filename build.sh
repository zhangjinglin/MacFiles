#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MyFiles"
APP_BUNDLE="build/${APP_NAME}.app"

if [ -f "Resources/AppIcon-1024.png" ] && { [ ! -f "Resources/AppIcon.icns" ] || [ "Resources/AppIcon-1024.png" -nt "Resources/AppIcon.icns" ]; }; then
    ./make-icon.sh
fi

swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp "${BIN_PATH}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>local.myfiles.app</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>MyFiles 需要访问桌面文件夹以浏览其中的文件。</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>MyFiles 需要访问文稿文件夹以浏览其中的文件。</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>MyFiles 需要访问下载文件夹以浏览其中的文件。</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>MyFiles 需要访问外接磁盘以浏览其中的文件。</string>
    <key>NSNetworkVolumesUsageDescription</key>
    <string>MyFiles 需要访问网络磁盘以浏览其中的文件。</string>
</dict>
</plist>
EOF

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# A stable signing identity keeps macOS privacy (TCC) grants across rebuilds.
# Ad-hoc signatures change their identity every build, so the system treats
# each build as a new app and asks for folder access again.
# Override with: MYFILES_SIGN_IDENTITY="..." ./build.sh
if [ -n "${MYFILES_SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY="${MYFILES_SIGN_IDENTITY}"
elif security find-identity -v -p codesigning 2>/dev/null | grep -Fq '"MyFiles Dev"'; then
    SIGN_IDENTITY="MyFiles Dev"
else
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development: [^"]*"' | head -n 1 | tr -d '"')"
fi

if [ -n "${SIGN_IDENTITY}" ]; then
    codesign --force --sign "${SIGN_IDENTITY}" --identifier "local.myfiles.app" --timestamp=none "${APP_BUNDLE}" >/dev/null
    echo "Signed with: ${SIGN_IDENTITY}"
else
    echo "Warning: no code signing identity found; falling back to ad-hoc signing." >&2
    echo "Warning: macOS will ask for folder access again after every rebuild." >&2
    codesign --force --sign - "${APP_BUNDLE}" >/dev/null 2>&1
fi

echo "Built: ${APP_BUNDLE}"
