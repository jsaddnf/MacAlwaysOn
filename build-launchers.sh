#!/bin/zsh
set -euo pipefail

bundle_dir="${0:A:h}"
version="$(<"$bundle_dir/VERSION")"
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'VERSION 必须为 x.y.z。'; exit 1; }
[[ -x "$bundle_dir/bin/remote-power" ]] || { print -u2 '请先运行 ./build.sh。'; exit 1; }
build_dir="$(/usr/bin/mktemp -d /private/tmp/mac-always-on-app.XXXXXX)"
trap '/bin/rm -rf "$build_dir"' EXIT
app_path="$bundle_dir/MacAlwaysOn.app"
architecture="$(/usr/bin/uname -m)"

if [[ -e "$app_path" ]]; then
  [[ -d "$app_path" && ! -L "$app_path" ]] || { print -u2 "应用路径异常：$app_path"; exit 1; }
  /bin/rm -rf "$app_path"
fi
/bin/mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources/Payload/bin"
/usr/bin/xcrun swiftc -O -parse-as-library -target "${architecture}-apple-macosx26.0" \
  -module-cache-path "$build_dir/cache" \
  "$bundle_dir/Sources/PowerController.swift" "$bundle_dir/Sources/ControlSocket.swift" \
  "$bundle_dir/App/main.swift" -o "$app_path/Contents/MacOS/MacAlwaysOn"
/bin/cat > "$app_path/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.jsaddnf.MacAlwaysOn</string>
  <key>CFBundleName</key><string>MacAlwaysOn</string>
  <key>CFBundleDisplayName</key><string>MacAlwaysOn</string>
  <key>CFBundleExecutable</key><string>MacAlwaysOn</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/bin/cp "$bundle_dir/"{run-ui.sh,install.sh,uninstall.sh} "$app_path/Contents/Resources/Payload/"
/bin/cp "$bundle_dir/bin/remote-power" "$app_path/Contents/Resources/Payload/bin/"
/usr/bin/plutil -lint "$app_path/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app_path/Contents/Resources/Payload/bin/remote-power"
/usr/bin/codesign --force --sign - "$app_path"
/usr/bin/codesign --verify --deep --strict "$app_path"
print '已生成 MacAlwaysOn.app，所有操作共用一个窗口和应用身份。'
