#!/bin/zsh
set -euo pipefail

bundle_dir="${0:A:h}"
build_dir="$(/usr/bin/mktemp -d /private/tmp/mac-always-on-icon.XXXXXX)"
trap '/bin/rm -rf "$build_dir"' EXIT

/usr/bin/xcrun swiftc -O -module-cache-path "$build_dir/cache" \
  "$bundle_dir/App/Assets/RenderIcon.swift" -o "$build_dir/render-icon"
"$build_dir/render-icon" "$build_dir/AppIcon.iconset"
/usr/bin/iconutil --convert icns "$build_dir/AppIcon.iconset" \
  --output "$bundle_dir/App/Assets/AppIcon.icns"
/bin/cp "$build_dir/AppIcon.iconset/icon_512x512@2x.png" "$bundle_dir/App/Assets/AppIcon.png"
print '已生成 AppIcon.icns 与 1024 像素预览图，包含 16 至 1024 像素图标。'
