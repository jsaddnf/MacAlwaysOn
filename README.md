# MacAlwaysOn

接电时一键保持 Mac 唤醒，用完恢复原来的睡眠设置。

[下载安装包](https://github.com/jsaddnf/MacAlwaysOn/releases/tag/v0.1.0) · [English](README.en.md) · [更新记录](CHANGELOG.md) · [MIT License](LICENSE)

MacAlwaysOn 适合需要让 Mac 留在桌面上运行远程开发、AI 工具或长任务的人。它提供原生 `.app` 开关和命令行接口，由一个小型 Swift 后台程序负责保存、修改和恢复电源设置。

**当前为 v0.1.0 预览版。** 已验证开关、恢复、辅助程序崩溃恢复和安装卸载；**接电、无外接显示器、合盖后的远程连接尚未完成实机验证**。请先在自己的设备上验收，再用于无人值守任务。本工具不提供远程连接服务，也不保证电脑永远在线。

## 能做什么

- **开启**：确认接电、温控正常且电池电量不低于要求后，保存恢复记录，再设置系统禁止睡眠。
- **关闭**：只恢复本程序管理的 `SleepDisabled` 设置，保留原有屏幕、磁盘、休眠及充电配置。
- **自动关闭**：收到供电或温控通知后，如已拔电、温控为 `serious` / `critical` / 未知，或电量不超过 20%，恢复设置。重新接电或降温不会自动开启。
- **异常恢复**：辅助程序退出后由 `launchd` 重新启动；启动时先处理恢复记录。重启后不自动继续远程运行模式。
- **日常免密码**：首次安装和卸载需要管理员授权；安装用户日常切换、查看状态无需重复输入密码。
- **本地控制**：仅接受安装用户或管理员的本地请求，不开放网络端口。

## 系统要求

| 项目 | 当前范围 |
| --- | --- |
| 预编译安装包 | Apple Silicon（arm64），macOS 26.0 或更高版本 |
| 已实际验证的系统 | macOS 26.4.1、Apple Silicon、Swift 6.2 |
| 其他系统和设备 | 其他 macOS 版本、Intel Mac 和不同机型尚未完成兼容性验证 |
| 使用条件 | 外接电源；若能读取电池电量，须高于 20%；系统温控为 `nominal` 或 `fair` |
| 从源码构建 | macOS、Swift 6.2 或更新编译器、macOS 26 SDK；可由 Xcode 或对应 Command Line Tools 提供 |

使用预编译包无需安装 Homebrew、Python 或 Swift 工具链。应用目前采用本地 ad-hoc 签名，**没有 Developer ID 签名和 Apple 公证**。

## 下载与安装

1. 在 [Releases](https://github.com/jsaddnf/MacAlwaysOn/releases/tag/v0.1.0) 下载 `MacAlwaysOn-v0.1.0-macos-arm64.zip`，解压后打开 `MacAlwaysOn` 文件夹。
2. 双击 **安装.app**，在 macOS 系统授权窗口输入管理员密码。安装后默认关闭。
3. 双击 **查看状态.app**，确认后台程序可以连接。
4. 接通电源，双击 **开启远程.app**。使用结束后双击 **关闭远程.app**。

可同时下载 `.zip.sha256` 文件，在下载目录核对压缩包：

```sh
shasum -a 256 -c MacAlwaysOn-v0.1.0-macos-arm64.zip.sha256
```

如果 macOS 因未验证开发者阻止打开，请先核对下载来源和校验值，再参考 [Apple 的应用安全打开说明](https://support.apple.com/zh-cn/102445)，或按下文从源码构建。校验值用于检查文件完整性，不等同于 Apple 公证。

### 六个双击入口

| 入口 | 作用 |
| --- | --- |
| `安装.app` | 首次安装；已安装时显示状态，不覆盖服务或恢复记录 |
| `电源模式.app` | 在开启和关闭之间切换 |
| `开启远程.app` | 明确开启；重复开启不会覆盖原始记录 |
| `关闭远程.app` | 明确关闭并恢复设置 |
| `查看状态.app` | 显示模式、系统睡眠设置、供电、温控和可读取的电量 |
| `卸载.app` | 先恢复设置，再移除辅助程序和服务 |

每个 `.app` 都包含自身需要的脚本，可以单独移动。它们直接弹窗显示结果，不经过交互式终端，避免 Oh My Zsh 更新提示读取启动路径的问题。

### 升级与卸载

升级前先关闭模式，使用旧版本的 `卸载.app` 完成卸载，再安装新版本。`安装.app` 不会静默升级已存在的服务。

不再使用时，双击 `卸载.app` 并完成管理员授权。**不要仅删除下载文件夹来卸载**，也不要在模式开启时手动删除系统服务或恢复记录。

早期名为 RemotePower 的版本使用相同服务标识；如已安装，按上述步骤先卸载旧版本。

## 命令行使用

在源码构建目录或解压目录中：

```sh
./bin/remote-power status
./bin/remote-power on
./bin/remote-power off
./bin/remote-power toggle
./bin/remote-power status --json
./bin/remote-power doctor
```

`doctor` 只读显示供电、电源设置、阻止睡眠的进程及计划电源事件，未安装后台服务时也可使用。

安装后也可以使用固定路径，例如：

```sh
/Library/PrivilegedHelperTools/com.halo.remote-power status
```

需要在终端安装或卸载时，从项目目录执行：

```sh
sudo /bin/zsh -f ./install.sh "$(id -u)"
sudo /bin/zsh -f ./uninstall.sh
```

以上两条分别执行安装、卸载，不要连续执行。请以要使用开关的普通用户登录终端，让 `id -u` 在提权前取得该用户的 UID。

## 使用前需要了解

### 合盖与远程连接

本项目通过 `pmset disablesleep` 修改系统级 `SleepDisabled` 设置，不是 Apple 官方的合盖工作方案。Apple 的[合盖使用说明](https://support.apple.com/zh-cn/102282)涉及外接显示器、键盘和鼠标；本项目“只接电源、不接显示器”的目标仍须逐机验证。

`SleepDisabled=1` 只能证明系统接受了设置，不能证明合盖后 Wi-Fi、Codex 或其他远程工具一定可用。远程工具需要另行配置并保持运行。合盖时关闭模式可能立即睡眠并断开连接；电脑睡眠后，无法依赖已经断开的同一条远程连接重新开启本工具。

### 睡眠、硬盘和电池

- `disablesleep` 作用范围较大，可能同时阻止手动睡眠。需要正常睡眠或将电脑放入包内前，先关闭本工具。
- 关闭表示撤销本程序的修改，**不等于立刻睡眠**。其他应用的 `caffeinate` 或系统任务仍可能阻止睡眠，可用 `doctor` 排查。
- 本工具不修改 `sleep`、`displaysleep`、`disksleep`、`hibernatemode`、优化充电或充电上限，不会结束其他应用的防休眠进程。
- 持续运行仍会耗电和发热，不能保证硬盘、电池寿命完全不受影响。使用时保持通风。
- 本工具不阻止用户关机、系统重启、网络中断或断电，不提供远程唤醒功能。
- 自动恢复依赖 macOS、`launchd`、系统通知及 `pmset` 正常工作；系统崩溃、事件未送达或命令挂起时，不能保证立即恢复。
- 如果其他工具已经把 `SleepDisabled` 设为 1，本工具拒绝接管；不建议多个工具同时修改这个全局设置。

## 工作原理

1. `.app` 或 CLI 把 `on`、`off`、`toggle`、`status` 发送到本地 Unix socket。
2. 以 root 身份运行的 Swift 辅助程序验证连接用户，并在主事件队列上处理指令。
3. 开启前保存原始设置，完成文件与目录同步，然后执行固定的 `pmset` 命令；读回确认后才报告成功。
4. 关闭时恢复保存的设置，读回确认后才删除恢复记录。恢复失败时保留记录，不报告成功。
5. 供电和温控通过系统通知监听；后台程序没有定时轮询。启动恢复发生在重新建立控制接口之前。

服务仅接受固定指令，不接受客户端指定可执行程序、任意命令或文件路径。恢复目录归 root 所有，权限为 `0700`；记录文件为 `0600`，拒绝符号链接和异常所有者。CLI 也会检查对端是否为 root。

为兼容已有安装，内部服务名称继续使用 RemotePower：

| 文件 | 用途 |
| --- | --- |
| `/Library/PrivilegedHelperTools/com.halo.remote-power` | Swift 辅助程序及 CLI |
| `/Library/LaunchDaemons/com.halo.remote-power.plist` | 系统服务配置 |
| `/Library/Application Support/RemotePower/session.json` | 本程序的恢复记录，仅开启期间需要 |
| `/private/var/run/com.halo.remote-power/control.sock` | 本地控制接口 |

## 从源码构建

```sh
git clone https://github.com/jsaddnf/MacAlwaysOn.git
cd MacAlwaysOn
./build.sh
./build-launchers.sh
./run-tests.sh
```

这些步骤只编译、生成入口并运行模拟测试，不安装后台服务，不修改真实电源设置。构建结果为 `bin/remote-power` 和根目录中的六个 `.app`。

生成完整安装包：

```sh
./package.sh
```

`package.sh` 会重新构建程序及入口，将源码、测试、文档、许可证、应用和文件校验清单装入 `dist/MacAlwaysOn-v<版本>-macos-arm64.zip`，另生成压缩包的 `.sha256` 文件。它不会上传文件或安装服务。版本号来自 `VERSION`。

## 验证范围

首个版本的本地验证环境为 macOS 26.4.1 / Apple Silicon。自动测试使用内存或临时文件模拟电源状态，不通过真实电源切换来测试。

| 检查 | 结果或范围 |
| --- | --- |
| Swift 编译、Shell 语法、应用签名、压缩包校验 | 已通过 |
| 自动测试 | 32 项，覆盖保存顺序、重复操作、供电与温控变化、写入失败、异常记录、目录权限和 socket 控制 |
| 模拟服务进程被 SIGKILL 后重启 | 已验证记录恢复；不修改真实电源 |
| 真实开关和恢复 | 已验证 `SleepDisabled` 从 0 → 1 → 0，其他电源设置保持不变 |
| 真实辅助程序被 SIGKILL 后由 launchd 重启 | 已验证恢复设置 |
| 安装、卸载、重新安装 | 已验证 |
| 原生入口 | 已验证查看状态、已有安装识别 |
| 无外接显示器合盖后远程连接、长时间空闲后连接 | 尚未实测 |
| 真实拔电、真实过热、整机重启 | 自动测试覆盖相关逻辑，尚未完成这些硬件场景的实测 |

物理设备的验证记录来自开源整理前的同一套电源控制实现；打包和文案调整没有改变其控制逻辑。自动测试通过不代表所有硬件都支持合盖联网。

### 在自己的设备上验收

1. 保存工作，在电脑旁开盖、接电，记录 `pmset -g custom`。
2. 开启模式，查看状态；关闭后确认 `pmset -g custom` 与之前一致。
3. 再次开启，先保持开盖。手机关闭 Wi-Fi，使用蜂窝网络，通过已配置的远程连接请求这台 Mac 执行 `date` 和 `pmset -g`，确认开盖时能收到结果。
4. 保持接电、不接外接显示器，合盖等待 1 分钟，再发起同样的请求。应返回新的时间和当前设置。
5. 保持合盖，至少 10 分钟不操作，再次发起请求。两次均正常返回，才算通过基本合盖验收；这不代表已经验证整夜或更长时间的稳定性。
6. 回到电脑旁开盖、拔电，确认自动关闭；重新接电后应仍保持关闭。
7. 再次开启、关闭，并检查正常睡眠是否恢复；若不能睡眠，先检查其他进程的请求。

个人使用也需要在自己的 Mac 上完成这次验收。若远程请求失败，开盖恢复连接，记录失败步骤、时间及状态；升级 macOS 或远程工具后，建议重新执行第 3～5 步。

不要故意制造过热来测试温控保护。

## 故障排查

**安装过，但无法连接辅助程序：**

```sh
launchctl print system/com.halo.remote-power
./bin/remote-power doctor
log show --last 10m --predicate 'process == "com.halo.remote-power"'
```

先检查安装时使用的用户是否正确。重复运行安装入口不会覆盖已有服务或未完成的恢复记录。

**辅助程序异常，系统仍显示 `SleepDisabled=1`：**

在本机开盖操作，先停止服务，再处理本程序保存的恢复记录：

```sh
sudo launchctl bootout system/com.halo.remote-power
sudo /Library/PrivilegedHelperTools/com.halo.remote-power recover
pmset -g
```

如果服务已经停止，第一条可能提示找不到服务，可继续检查恢复。`recover` 没有本程序记录时不会覆盖其他工具的设置。恢复后可正常卸载并重新安装；不要直接删除 `session.json`。

**旧 `.command` 入口报 `Users/…: no such file or directory`：**

终端启动时的 Oh My Zsh 更新询问可能读取绝对路径开头的 `/`，导致后面的路径失效。使用本项目提供的 `.app` 入口，无需修改全局 Shell 配置。

## 参与贡献

欢迎提交 Issue 和 Pull Request。请提供 macOS 版本、芯片架构、接电与合盖状态、复现步骤；公开诊断输出前删除个人路径、设备标识及与问题无关的信息。开发和验证要求见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

[MIT](LICENSE) · Copyright © 2026 jsaddnf。MacAlwaysOn 为独立项目，与 Apple、OpenAI 无关联或背书关系。
