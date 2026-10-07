#!/bin/zsh
set -euo pipefail
bundle_dir="${0:A:h}"
build_dir="$(/usr/bin/mktemp -d /private/tmp/remote-power-tests.XXXXXX)"
trap '/bin/rm -rf "$build_dir"' EXIT
/usr/bin/xcrun swiftc -module-cache-path "$build_dir/cache" \
  "$bundle_dir/Sources/PowerController.swift" "$bundle_dir/Sources/MacPowerBackend.swift" \
  "$bundle_dir/Sources/ControlSocket.swift" "$bundle_dir/Sources/ServiceDirectory.swift" "$bundle_dir/Tests/main.swift" \
  -o "$build_dir/tests"
"$build_dir/tests"
