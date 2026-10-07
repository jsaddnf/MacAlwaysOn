# MacAlwaysOn

Keep your Mac awake while connected to power, then restore its previous sleep setting when you are done.

[Download](https://github.com/jsaddnf/MacAlwaysOn/releases/tag/v0.1.0) · [简体中文](README.md) · [MIT License](LICENSE)

MacAlwaysOn provides six native `.app` launchers and a command-line interface backed by a small Swift system service. It is intended for remote development, AI tools and long-running work on a Mac left on a ventilated desk.

**v0.1.0 is a preview release.** Power toggling, restoration, service crash recovery, installation and removal have been tested. **Remote connectivity with the lid closed and no external display has not been physically verified.** Test your own device before unattended use. This utility does not provide remote access or guarantee continuous connectivity.

## Requirements

- The downloadable package targets **Apple Silicon (arm64), macOS 26.0 or later**.
- Local validation used macOS 26.4.1 and Swift 6.2. Other macOS versions, Intel Macs and other hardware remain unverified.
- Enabling requires confirmed AC power, a `nominal` or `fair` thermal state, and battery charge above 20% when available.
- Building requires Swift 6.2 or newer and the macOS 26 SDK, supplied by Xcode or corresponding Command Line Tools.
- The prebuilt package needs no Homebrew, Python or Swift toolchain.

Applications use **ad-hoc signatures**, without Developer ID signing or Apple notarization. If Gatekeeper blocks a download, verify the source and checksum, consult [Apple's guidance](https://support.apple.com/102445), or build locally. A checksum checks integrity; it is not notarization.

## Install and use

1. Download `MacAlwaysOn-v0.1.0-macos-arm64.zip` from [Releases](https://github.com/jsaddnf/MacAlwaysOn/releases/tag/v0.1.0) and extract it.
2. Open `安装.app` and authorize installation using the macOS administrator prompt. The mode starts **off**.
3. Open `查看状态.app` to check the service.
4. Connect power and open `开启远程.app`. Open `关闭远程.app` when finished.

The launchers currently display Chinese text:

| Launcher | Action |
| --- | --- |
| `安装.app` | Install; show status if already installed |
| `电源模式.app` | Toggle on/off |
| `开启远程.app` | Enable |
| `关闭远程.app` | Disable and restore |
| `查看状态.app` | Show status |
| `卸载.app` | Restore settings and uninstall |

Each app includes its own scripts and can be moved independently. The apps bypass interactive Terminal startup, including Oh My Zsh update prompts. Installation and removal require administrator authorization; routine control by the installing user does not.

Download the matching `.zip.sha256` file to verify the archive:

```sh
shasum -a 256 -c MacAlwaysOn-v0.1.0-macos-arm64.zip.sha256
```

To upgrade, disable the mode, uninstall the old version, then install the new one. The installer deliberately does not overwrite an existing service or recovery record. Earlier RemotePower builds use the same service identifier and must be removed first. Deleting the downloaded folder does **not** uninstall the service.

## CLI

From the extracted or built directory:

```sh
./bin/remote-power status
./bin/remote-power on
./bin/remote-power off
./bin/remote-power toggle
./bin/remote-power status --json
./bin/remote-power doctor
```

`doctor` only reads system settings and sleep assertions; it also works before installation. Once installed, the executable is available at `/Library/PrivilegedHelperTools/com.halo.remote-power`.

For terminal installation, run `sudo /bin/zsh -f ./install.sh "$(id -u)"` from a normal user's shell. To uninstall, run `sudo /bin/zsh -f ./uninstall.sh` instead.

## What changes

The service saves a recovery record before setting `pmset disablesleep 1`. Disabling restores the recorded `SleepDisabled` value, verifies it and removes the record. If another tool already disabled system sleep, MacAlwaysOn refuses to take ownership.

On power or thermal notifications, the service restores sleep if AC power is lost, thermal conditions are no longer allowed, or battery charge is at most 20%. Reconnecting power or cooling down does not automatically enable it again. `launchd` restarts a crashed service, which processes recovery records before accepting new requests. A reboot does not resume an active session.

Only the installing user and root can send fixed commands over the local Unix socket. The client checks the server's identity as well. There are no network listeners and no arbitrary executable or path arguments. State is stored in a root-owned `0700` directory, with `0600` records and checks against symlinks and unexpected ownership. Power and thermal monitoring use system notifications rather than polling.

The internal RemotePower identifiers are retained for compatibility:

| Path | Purpose |
| --- | --- |
| `/Library/PrivilegedHelperTools/com.halo.remote-power` | Service executable and CLI |
| `/Library/LaunchDaemons/com.halo.remote-power.plist` | Launch daemon configuration |
| `/Library/Application Support/RemotePower/session.json` | Recovery record |
| `/private/var/run/com.halo.remote-power/control.sock` | Local control socket |

## Limitations

- `SleepDisabled=1` confirms the setting, not closed-lid network access. Apple's [closed-lid guidance](https://support.apple.com/102282) describes external peripherals. This project's no-display scenario requires device testing.
- Remote access software must be configured and running separately. Disabling while the lid is closed may immediately suspend the Mac and disconnect a remote session. The disconnected session cannot turn the mode back on.
- This setting can prevent manual sleep too. Disable the mode before putting the Mac in a bag.
- Disabling does not force immediate sleep. Other applications or system tasks may still prevent it; use `doctor` to inspect them.
- The utility does not change display/disk idle timers, hibernation settings or charging policy, and does not stop other apps' keep-awake processes. Staying awake still uses energy and produces heat; zero effect on battery or hardware lifetime is not guaranteed.
- It does not prevent shutdowns, reboots, power loss or network outages, and does not implement wake-on-demand.
- Recovery depends on a functioning OS, `launchd`, system notifications and `pmset`; a system crash, missing notification or hung command can delay recovery.
- Avoid multiple utilities changing the same global setting simultaneously.

## Build, test and package

```sh
git clone https://github.com/jsaddnf/MacAlwaysOn.git
cd MacAlwaysOn
./build.sh
./build-launchers.sh
./run-tests.sh
./package.sh
```

These commands do not install a service or change real power settings. Tests use memory and temporary files. `package.sh` rebuilds and produces an arm64 ZIP and checksum under `dist/`, including applications, sources, tests, documentation, license and a per-file checksum manifest. The version is read from `VERSION`.

Validation includes 32 automated tests, local compilation and app signatures, real `SleepDisabled` changes from 0 to 1 and back to 0 with other settings unchanged, real service SIGKILL recovery, install/uninstall, and the status and existing-installation dialogs. Physical power-management checks were performed on the same control implementation before the public packaging changes.

Closed-lid remote access, long idle connectivity, physical power disconnection, actual thermal stress and whole-machine reboot remain unverified. Automated tests of restoration logic are not substitutes for those hardware checks.

For device acceptance, including personal use:

1. Save work, record `pmset -g custom`, test on/off and compare settings.
2. Enable the mode with the lid open. From a phone on cellular data with Wi-Fi disabled, use your configured remote connection to ask this Mac to run `date` and `pmset -g`. Confirm this baseline works first.
3. Keep AC connected with no external display. Close the lid, wait one minute, and repeat the request. Check that a fresh timestamp returns.
4. Leave the closed Mac idle for at least ten minutes, then repeat. Both successful requests establish basic closed-lid acceptance, not overnight reliability.
5. Return to the Mac, open the lid and unplug power. Confirm the mode turns off and stays off after reconnecting power.
6. Check normal sleep after disabling; inspect other apps' assertions if necessary.

If a request fails, reopen the lid and record which step failed. Repeat the connectivity checks after macOS or remote-tool updates. Do not deliberately overheat your device.

## Troubleshooting

```sh
launchctl print system/com.halo.remote-power
./bin/remote-power doctor
log show --last 10m --predicate 'process == "com.halo.remote-power"'
```

If the service is failing while sleep is still disabled, open the lid and recover locally:

```sh
sudo launchctl bootout system/com.halo.remote-power
sudo /Library/PrivilegedHelperTools/com.halo.remote-power recover
pmset -g
```

The first command may report that an already stopped service is absent. Recovery only changes settings when this utility has its own record. Keep the record if restoration fails. After successful recovery, uninstall and reinstall normally rather than deleting system files manually.

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md). Include the OS version, architecture, power/lid conditions and reproduction steps when reporting an issue. Remove private paths, identifiers and unrelated diagnostics before posting logs.

[MIT](LICENSE), copyright © 2026 jsaddnf. This is an independent project, not affiliated with or endorsed by Apple or OpenAI.
