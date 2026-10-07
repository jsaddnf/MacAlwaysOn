#!/bin/zsh
set -euo pipefail

bundle_dir="${0:A:h}"
service_label='com.halo.remote-power'
helper_path='/Library/PrivilegedHelperTools/com.halo.remote-power'
state_dir='/Library/Application Support/RemotePower'
runtime_dir='/private/var/run/com.halo.remote-power'
plist_path="/Library/LaunchDaemons/${service_label}.plist"

[[ $EUID -eq 0 ]] || { print -u2 '请双击 安装.app，由系统请求管理员授权。'; exit 1; }
[[ $# -eq 1 && $1 == <501-> ]] || { print -u2 '必须指定普通用户的数字 UID。'; exit 1; }
target_uid="$1"
/usr/bin/id -nu "$target_uid" >/dev/null
[[ -f "$bundle_dir/bin/remote-power" && ! -L "$bundle_dir/bin/remote-power" ]] || {
  print -u2 '未找到编译好的程序，请先运行 build.sh。'; exit 1
}
/usr/bin/codesign --verify "$bundle_dir/bin/remote-power"
for target_path in "$helper_path" "$state_dir" "$runtime_dir" "$plist_path"; do
  if [[ -e "$target_path" || -L "$target_path" ]]; then
    print -u2 "已有安装或恢复文件：$target_path。请先运行卸载，不会覆盖原来的恢复记录。"
    exit 1
  fi
done
if /bin/launchctl print "system/$service_label" >/dev/null 2>&1; then
  print -u2 '已有同名后台服务，安装已停止。'
  exit 1
fi

installation_complete=0
cleanup_failed_install() {
  local result=$?
  if (( installation_complete == 0 )); then
    print -u2 '安装未完成，正在撤销本次安装。'
    if /bin/launchctl print "system/$service_label" >/dev/null 2>&1; then
      /bin/launchctl bootout "system/$service_label" || return
    fi
    if [[ -x "$helper_path" && -d "$state_dir" ]]; then
      "$helper_path" recover || { print -u2 '恢复未完成，已保留程序和记录，请检查。'; return; }
    fi
    /bin/rm -f "$plist_path" "$helper_path"
    /bin/rm -f "$runtime_dir/control.sock" "$state_dir/service.lock"
    [[ ! -d "$runtime_dir" ]] || /bin/rmdir "$runtime_dir"
    [[ ! -d "$state_dir" ]] || /bin/rmdir "$state_dir"
  fi
  return "$result"
}
trap cleanup_failed_install EXIT

/usr/bin/install -d -o root -g wheel -m 0755 /Library/PrivilegedHelperTools
/usr/bin/install -d -o root -g wheel -m 0700 "$state_dir"
/usr/bin/install -o root -g wheel -m 0755 "$bundle_dir/bin/remote-power" "$helper_path"
umask 022
/bin/cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$service_label</string>
  <key>ProgramArguments</key>
  <array><string>$helper_path</string><string>daemon</string><string>$target_uid</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>5</integer>
  <key>ExitTimeOut</key><integer>15</integer>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
PLIST
/usr/sbin/chown root:wheel "$plist_path"
/bin/chmod 0644 "$plist_path"
/usr/bin/plutil -lint "$plist_path"
/bin/launchctl bootstrap system "$plist_path"
installation_complete=1
print '安装完成，远程运行模式默认关闭。'
print '先运行 查看状态.app；准备好合盖测试后再运行 开启远程.app。'
