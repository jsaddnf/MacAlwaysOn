#!/bin/zsh
set -euo pipefail
bundle_dir="${0:A:h}"
build_dir="$(/usr/bin/mktemp -d /private/tmp/remote-power-build.XXXXXX)"
trap '/bin/rm -rf "$build_dir"' EXIT
/bin/mkdir -p "$bundle_dir/bin"
architecture="$(/usr/bin/uname -m)"
/usr/bin/xcrun swiftc -O -target "${architecture}-apple-macosx26.0" -module-cache-path "$build_dir/cache" \
  "$bundle_dir/Sources/PowerController.swift" "$bundle_dir/Sources/MacPowerBackend.swift" \
  "$bundle_dir/Sources/ControlSocket.swift" "$bundle_dir/Sources/ServiceDirectory.swift" "$bundle_dir/Sources/main.swift" \
  -o "$bundle_dir/bin/remote-power"
/usr/bin/codesign --force --sign - "$bundle_dir/bin/remote-power"
/usr/bin/codesign --verify "$bundle_dir/bin/remote-power"
print '编译完成。'
