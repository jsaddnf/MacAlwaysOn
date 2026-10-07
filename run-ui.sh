#!/bin/zsh
set -euo pipefail
bundle_dir="${0:A:h}"
helper_path='/Library/PrivilegedHelperTools/com.halo.remote-power'
stage_dir=''
finish() {
  local result=$?
  if [[ -n "$stage_dir" ]]; then /bin/rm -rf "$stage_dir"; fi
  if (( result != 0 )); then print -u2 '\n操作未完成，请查看上方信息；不要反复切换，请先查看状态。'; fi
  if [[ -t 0 ]]; then read -r '?按回车关闭此窗口…' || true; fi
  return "$result"
}
trap finish EXIT
[[ $# -eq 1 ]] || exit 1
case "$1" in
  install)
    if [[ -x "$helper_path" ]]; then
      print '程序已经安装，无需重复安装。当前状态：'
      "$helper_path" status
      exit
    fi
    print '将安装只为当前用户服务的电源辅助程序。首次安装需要管理员授权，安装后默认关闭。'
    stage_dir="$(/usr/bin/mktemp -d /private/tmp/remote-power-install.XXXXXX)"
    /bin/mkdir "$stage_dir/bin"
    /bin/cp "$bundle_dir/install.sh" "$stage_dir/install.sh"
    /bin/cp "$bundle_dir/bin/remote-power" "$stage_dir/bin/remote-power"
    /usr/bin/osascript - "$stage_dir/install.sh" "$UID" <<'APPLESCRIPT'
on run argv
    do shell script "/bin/zsh " & quoted form of (item 1 of argv) & " " & quoted form of (item 2 of argv) with administrator privileges
end run
APPLESCRIPT
    ;;
  uninstall)
    print '将停止后台程序、恢复本程序修改的设置并卸载。盖子合着时可能立即进入睡眠。'
    stage_dir="$(/usr/bin/mktemp -d /private/tmp/remote-power-uninstall.XXXXXX)"
    /bin/cp "$bundle_dir/uninstall.sh" "$stage_dir/uninstall.sh"
    /usr/bin/osascript - "$stage_dir/uninstall.sh" <<'APPLESCRIPT'
on run argv
    do shell script "/bin/zsh " & quoted form of (item 1 of argv) with administrator privileges
end run
APPLESCRIPT
    ;;
  on|off|toggle|status|doctor)
    if [[ ! -x "$helper_path" ]]; then
      if [[ "$1" == doctor ]]; then "$bundle_dir/bin/remote-power" doctor; exit; fi
      print -u2 '请先双击 安装.app。'; exit 1
    fi
    "$helper_path" "$1"
    ;;
  *) print -u2 '无效操作。'; exit 1 ;;
esac
