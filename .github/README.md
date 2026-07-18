<div align="center">

![](https://img.shields.io/github/last-commit/MainstreamOS/dots-hyprland/mainstream?style=for-the-badge&color=8ad7eb&logo=git&logoColor=D9E0EE&labelColor=1E202B)
![](https://img.shields.io/github/repo-size/MainstreamOS/dots-hyprland?color=86dbce&label=SIZE&logo=protondrive&style=for-the-badge&logoColor=D9E0EE&labelColor=1E202B)
![](https://img.shields.io/badge/license-GPLv3-86dbd7?style=for-the-badge&labelColor=1E202B)
<a href="https://mainstreamos.org"><img src="https://img.shields.io/badge/docs-mainstreamos.org-86dbc0?style=for-the-badge&labelColor=1E202B" alt="Documentation"></a>

</div>

<div align="center">
    <img src="assets/desktop.webp" alt="The Mainstream OS desktop">
</div>

Arch under the hood, Hyprland on the surface, and the polish of macOS on top — the kind of care that makes it feel at home on your mom's laptop and your rendering rig alike. Deeply featured. Genuinely friendly.

This repository is the desktop itself — the Quickshell shell, the Hyprland configuration, and the `./setup` tooling that turns a fresh Arch install into Mainstream OS. The ISO builder lives at [MainstreamOS/archiso](https://github.com/MainstreamOS/archiso) and the signed package repo at [MainstreamOS/packages](https://github.com/MainstreamOS/packages). Mainstream ships a lean, heavily modified version of end-4's [illogical-impulse](https://github.com/end-4/dots-hyprland) shell the way Ubuntu ships GNOME — as one credited, continuously-upstream-merged component of a full operating system.

## Install

- **The OS (recommended)** — [Download the ISO](https://mainstreamos.org/download) (x86_64 · 2.7 GB), flash it to a USB drive, boot and click through. Dual-boot and full-disk encryption are supported.
- **On an existing Arch install** — run `bash <(curl -fsSL https://mainstreamos.org/install.sh)`; about 10 minutes. It also takes options — `--os-only` (desktop only), `--console` (gaming/console), or `--verbose` (confirm each command before it runs) — see [all the options](https://mainstreamos.org/#install-script).
- Once you're in: `Super` + `Tab` opens the keybind list, `Super` + `T` opens a terminal.

See the [install guides](https://mainstreamos.org/#install-iso) for details.

## Features

- **Every setting lives in one place** — wallpaper and colors, the UI, display and layout switching, keybinds and updates — a settings app, not a config file, and never a terminal. Snapshots keep experimenting safe.
    - **Displays** — arrange monitors and set resolution, refresh rate, scale, and orientation.
    - **Layout switching** — dwindle, master, scrolling, monocle, or float, per workspace, on the fly.
    - **Keybinds** — view and remap every shortcut in a visual editor.
    - **Touchpad gestures** — remap every swipe and pinch, applied instantly.
    - **Title bars** — toggle window title bars on or off instantly.
    - **App management** — install and remove native packages and Flatpaks, no terminal.
    - **Auto drive mounting** — set a drive up once and it's ready every login; format blank disks and unlock encrypted ones in the app.
- **Gaming Mode** — one click swaps your desktop for a full-screen dedicated gamescope session running Steam Big Picture, the same Game Mode a Steam Deck boots into, and one click back. A full tiling desktop and a real console mode, in one system.
- **Themes you can save and schedule** — pick a wallpaper — a still image or a video — and the whole desktop recolors to match (Material You). Save a complete look — wallpaper, colors, and window decorations — as a named theme with a preview, switch between saved themes in one tap, and pair a Day and Night theme that follow Night Light or your own set hours.
- **A launcher that finds everything** — apps, folders, files, and quick math.
- **Scrolling overview** — a zoomed-out map of every workspace; drag windows, files, and folders between them.
- **Session restore** — log out or reboot and your windows come back: same apps, same workspaces.
- **Made with creators in mind** — one-click install for DaVinci Resolve and OBS, with GPU encoding on Wayland.
- **LocalSend built in** — drag a file onto the bar's media widget to send it to any device on your network; right-click to receive. No cloud.
- **Updates with a safety net** — automatic snapshots before every update, and rollbacks right from the boot menu.
- **Verified installs** — a post-install self-check runs 19 tests on the finished system and writes a health report, so a bad install tells you instead of failing silently.
- **A lean, native base** — native apps as defaults, and the AUR off by default in favor of the signed [\[mainstream\]](https://github.com/MainstreamOS/packages) repo.

## Screenshots

<div align="center">
    <b>Scrolling Overview</b>
    <br><br>
    <img src="assets/scrolling-overview.webp" width="100%" alt="Scrolling overview panning across workspaces">
</div>

<div align="center">
    <b>Theme Switching</b>
    <br><br>
    <img src="assets/theme-switching.webp" width="100%" alt="Switching between saved Material You themes">
</div>

<div align="center">
    <b>Gaming Mode</b>
    <br><br>
    <img src="assets/gaming-big-picture.webp" width="100%" alt="Big Picture gaming session">
</div>

| Custom Overview/App Launcher | Quick settings |
|:---:|:---:|
| <img src="assets/overview.webp" alt="Scrolling overview with launcher"> | <img src="assets/quick-settings.webp" alt="Quick settings page"> |
| **Native Display Settings** | **Layout Switching** |
| <img src="assets/display-settings.webp" alt="Display arrangement and modes"> | <img src="assets/layouts.webp" alt="Per-workspace layout switching"> |
| **One Click Full Update** | **Automatic Recovery** |
| <img src="assets/update.webp" alt="System update with automatic snapshot"> | <img src="assets/recovery.webp" alt="Snapshot rollback from Settings"> |
| **One Click Full Featured OBS Install** | **One Click DaVinci Resolve Setup** |
| <img src="assets/obs.webp" alt="OBS with the default scene collection"> | <img src="assets/davinci-resolve.webp" alt="DaVinci Resolve on Mainstream OS"> |

## Under the hood

| Software | Purpose |
| ------------- | ------------- |
| [Hyprland](https://github.com/hyprwm/hyprland) | The compositor (manages and renders windows) |
| [Quickshell](https://quickshell.outfoxxed.me/) | The shell: bar, dock, overview, settings, lock screen |
| [Calamares](https://github.com/MainstreamOS/calamares) | The graphical installer |
| [Limine](https://github.com/limine-bootloader/limine) + [Snapper](https://github.com/openSUSE/snapper) | Boot menu with snapshot rollbacks |
| [Mainstream Repo](https://github.com/MainstreamOS/packages) | Signed repo of prebuilt packages — no AUR builds on your machine |

## Support

- [Discord](https://discord.gg/WJ3AUK5Aqd) — live help and community
- [Documentation](https://mainstreamos.org) — install guides, every settings page, creative setup, and the security model
- [Issues](https://github.com/MainstreamOS/dots-hyprland/issues) for bugs, [Discussions](https://github.com/MainstreamOS/dots-hyprland/discussions) for questions and ideas

## Contributing

Contributions are welcome — code, docs, bug reports, or ideas. Two are especially wanted:

- **Translations.** Mainstream should feel native well beyond English. If you speak another language, help is genuinely appreciated.
- **Honest feedback.** Nobody working on Mainstream is above reproach — if a decision looks off or something needs addressing, open an issue or a discussion. Questions and criticism are how it gets better.

Fixes to the upstream shell go back to [illogical-impulse](https://github.com/end-4/dots-hyprland) as pull requests.

## Thank you

- [end-4](https://github.com/end-4) ([sponsor](https://github.com/sponsors/end-4)), for [illogical-impulse](https://github.com/end-4/dots-hyprland) — the starting point for Mainstream's shell
- [@clsty](https://github.com/clsty) for the original install tooling
- [@midn8hustlr](https://github.com/midn8hustlr) for the color generation system
- [@outfoxxed](https://github.com/outfoxxed/) for [Quickshell](https://quickshell.outfoxxed.me/)
- [@yayuuu](https://github.com/yayuuu) for [Scroll Overview](https://github.com/yayuuu/hyprland-scroll-overview), the plugin behind the scrolling overview
- The [Calamares](https://calamares.io) team for the installer framework
- [@ful1e5](https://github.com/ful1e5) ([sponsor](https://github.com/sponsors/ful1e5)) for the [Bibata](https://github.com/ful1e5/Bibata_Cursor) cursor theme
- [@xCaptaiN09](https://github.com/xCaptaiN09) for the [Pixie](https://github.com/xCaptaiN09/pixie-sddm) SDDM theme
- [@BlueManCZ](https://github.com/BlueManCZ) for [hyprmod](https://github.com/BlueManCZ/hyprmod), the base of the Keybinds settings
- [Arch Linux](https://archlinux.org) ([sponsor](https://github.com/sponsors/archlinux)) — the base distribution and archiso

The full project list, with sponsor links, also lives in Settings → About.

## License

[GPLv3](../LICENSE). Copying: absolutely, feel free — just follow the license and it's all good.
