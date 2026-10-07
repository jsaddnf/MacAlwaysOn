#!/bin/zsh
set -euo pipefail

bundle_dir="${0:A:h}"
version="$(<"$bundle_dir/VERSION")"
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'VERSION 必须为 x.y.z。'; exit 1; }
[[ -x "$bundle_dir/bin/remote-power" ]] || { print -u2 '请先运行 ./build.sh。'; exit 1; }
build_dir="$(/usr/bin/mktemp -d /private/tmp/remote-power-launchers.XXXXXX)"
trap '/bin/rm -rf "$build_dir"' EXIT

build_launcher() {
  local app_title="$1"
  local action="$2"
  local app_path="$bundle_dir/$app_title.app"
  if [[ -e "$app_path" ]]; then
    [[ -d "$app_path" && ! -L "$app_path" ]] || { print -u2 "入口路径异常：$app_path"; exit 1; }
    /bin/rm -rf "$app_path"
  fi
  /bin/cat > "$build_dir/launcher.applescript" <<APPLESCRIPT
on run
    try
        set applicationPath to POSIX path of (path to me)
        set scriptPath to applicationPath & "Contents/Resources/Payload/run-ui.sh"
        set resultText to do shell script "/bin/zsh -f " & quoted form of scriptPath & " $action"
        display dialog resultText with title "$app_title" buttons {"好"} default button "好"
    on error errorText number errorNumber
        if errorNumber is not -128 then
            display dialog errorText with title "$app_title · 操作未完成" buttons {"好"} default button "好" with icon caution
        end if
    end try
end run
APPLESCRIPT
  /usr/bin/osacompile -o "$app_path" "$build_dir/launcher.applescript"
  /usr/bin/defaults write "$app_path/Contents/Info" CFBundleIdentifier "com.halo.remote-power.launcher.$action"
  /usr/bin/defaults write "$app_path/Contents/Info" CFBundleDisplayName "$app_title"
  /usr/bin/defaults write "$app_path/Contents/Info" CFBundleShortVersionString "$version"
  /usr/bin/defaults write "$app_path/Contents/Info" CFBundleVersion "$version"
  /usr/bin/defaults write "$app_path/Contents/Info" LSMinimumSystemVersion '26.0'
  /usr/bin/defaults write "$app_path/Contents/Info" LSUIElement -bool true
  /bin/mkdir -p "$app_path/Contents/Resources/Payload"
  /bin/cp "$bundle_dir/run-ui.sh" "$app_path/Contents/Resources/Payload/"
  if [[ "$action" == install ]]; then
    /bin/mkdir "$app_path/Contents/Resources/Payload/bin"
    /bin/cp "$bundle_dir/install.sh" "$app_path/Contents/Resources/Payload/"
    /bin/cp "$bundle_dir/bin/remote-power" "$app_path/Contents/Resources/Payload/bin/"
  elif [[ "$action" == uninstall ]]; then
    /bin/cp "$bundle_dir/uninstall.sh" "$app_path/Contents/Resources/Payload/"
  fi
  /usr/bin/codesign --force --sign - "$app_path"
  /usr/bin/codesign --verify --deep "$app_path"
}

build_launcher '安装' install
build_launcher '电源模式' toggle
build_launcher '开启远程' on
build_launcher '关闭远程' off
build_launcher '查看状态' status
build_launcher '卸载' uninstall
print '已生成 6 个原生双击入口。它们不打开交互式终端。'
