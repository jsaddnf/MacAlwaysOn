#!/bin/zsh
set -euo pipefail

service_label='com.halo.remote-power'
helper_path='/Library/PrivilegedHelperTools/com.halo.remote-power'
state_dir='/Library/Application Support/RemotePower'
runtime_dir='/private/var/run/com.halo.remote-power'
plist_path="/Library/LaunchDaemons/${service_label}.plist"

[[ $EUID -eq 0 ]] || { print -u2 '请双击 卸载.app，由系统请求管理员授权。'; exit 1; }
[[ $# -eq 0 ]] || { print -u2 '卸载不接受参数。'; exit 1; }
for target_path in "$helper_path" "$state_dir" "$runtime_dir" "$plist_path"; do
  [[ ! -L "$target_path" ]] || { print -u2 "路径异常，停止卸载：$target_path"; exit 1; }
done
if [[ ! -e "$helper_path" && ! -e "$state_dir" && ! -e "$plist_path" ]]; then
  print '未检测到本程序的安装。'
  exit 0
fi
[[ -x "$helper_path" && -d "$state_dir" ]] || {
  print -u2 '安装文件不完整，不能保证恢复设置，已保留全部记录。'; exit 1
}
if /bin/launchctl print "system/$service_label" >/dev/null 2>&1; then
  /bin/launchctl bootout "system/$service_label"
fi
"$helper_path" recover
[[ ! -e "$state_dir/session.json" ]] || { print -u2 '恢复记录仍在，停止卸载。'; exit 1; }
/bin/rm -f "$runtime_dir/control.sock" "$state_dir/service.lock"
[[ ! -d "$runtime_dir" ]] || /bin/rmdir "$runtime_dir"
/bin/rmdir "$state_dir"
/bin/rm -f "$plist_path" "$helper_path"
print '已恢复本程序修改的设置并卸载后台服务。其他应用的电源设置未修改。'
