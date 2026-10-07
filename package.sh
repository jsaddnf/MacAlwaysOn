#!/bin/zsh
set -euo pipefail

bundle_dir="${0:A:h}"
version="$(<"$bundle_dir/VERSION")"
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'VERSION 必须为 x.y.z。'; exit 1; }
architecture="$(/usr/bin/uname -m)"
[[ "$architecture" == arm64 ]] || { print -u2 '当前发布包仅支持 Apple Silicon (arm64)。'; exit 1; }
stage_dir="$(/usr/bin/mktemp -d /private/tmp/mac-always-on-package.XXXXXX)"
trap '/bin/rm -rf "$stage_dir"' EXIT

/bin/zsh -f "$bundle_dir/build.sh"
/bin/zsh -f "$bundle_dir/build-launchers.sh"

product_dir="$stage_dir/MacAlwaysOn"
/bin/mkdir -p "$product_dir/bin" "$product_dir/Sources" "$product_dir/Tests" "$bundle_dir/dist"
for file in README.md README.en.md LICENSE CHANGELOG.md CONTRIBUTING.md VERSION \
            build.sh build-launchers.sh run-tests.sh run-ui.sh install.sh uninstall.sh package.sh; do
  /bin/cp "$bundle_dir/$file" "$product_dir/$file"
done
/bin/cp "$bundle_dir/Sources/"*.swift "$product_dir/Sources/"
/bin/cp "$bundle_dir/Tests/main.swift" "$product_dir/Tests/"
/bin/cp "$bundle_dir/bin/remote-power" "$product_dir/bin/"
for title in 安装 电源模式 开启远程 关闭远程 查看状态 卸载; do
  /usr/bin/ditto --norsrc --noextattr --noacl "$bundle_dir/$title.app" "$product_dir/$title.app"
  /usr/bin/codesign --verify --deep --strict "$product_dir/$title.app"
done

(
  cd "$product_dir"
  for file in **/*(D.); do
    [[ "$file" == SHA256SUMS ]] || /usr/bin/shasum -a 256 "$file"
  done > SHA256SUMS
  /usr/bin/shasum -a 256 -c SHA256SUMS --status
)
archive="MacAlwaysOn-v${version}-macos-${architecture}.zip"
/usr/bin/ditto -c -k --norsrc --noextattr --noacl --keepParent "$product_dir" "$bundle_dir/dist/$archive"
/usr/bin/unzip -tq "$bundle_dir/dist/$archive"
(
  cd "$bundle_dir/dist"
  /usr/bin/shasum -a 256 "$archive" > "$archive.sha256"
)
print "安装包：$bundle_dir/dist/$archive"
print "校验值：$bundle_dir/dist/$archive.sha256"
