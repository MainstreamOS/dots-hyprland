# Security Policy

## Supported Versions

Mainstream OS is a rolling-release operating system built on Arch Linux, paired with numbered desktop and system tooling releases (`MAJOR.MINOR.PATCH`). Security updates apply to the rolling system repositories and the current `4.x` release line.

| Component | Supported Version | Status |
| :--- | :--- | :--- |
| Mainstream OS System & `[mainstream]` Repo | Rolling | Supported |
| Mainstream Desktop & Shell (`dots-hyprland`) | `4.x` | Supported |
| Mainstream Desktop & Shell (`dots-hyprland`) | `< 4.0` | Unsupported — update via **Settings → Update** |
| Installation Media (`archiso`) | Latest published ISO | Point-in-time install media (installs update to current rolling state) |

## Scope: First-Party vs. Upstream Packages

- **Mainstream First-Party Components** (`MainstreamOS/dots-hyprland`, `MainstreamOS/packages`, `MainstreamOS/calamares`, `MainstreamOS/archiso`, `MainstreamOS/mpris-hyprland`, privileged helpers, Polkit rules, and `[mainstream]` packaging): Covered directly by this security policy.
- **Upstream Arch Linux Packages** (`[core]`, `[extra]`, `[multilib]`): Inherited unmodified from official Arch Linux mirrors and tracked by the [Arch Linux Security Tracker](https://security.archlinux.org/).

## Reporting a Vulnerability

**Please do not report security vulnerabilities in public GitHub issues or public Discord channels.**

1. **GitHub Private Vulnerability Reporting (Preferred):**
   Use the [**Report a vulnerability**](https://github.com/MainstreamOS/dots-hyprland/security/advisories/new) button under this repository's **Security** tab to open a private security advisory.
2. **Email:**
   If you cannot use GitHub Security Advisories, email [mainstreamlinuxos@gmail.com](mailto:mainstreamlinuxos@gmail.com) with `[SECURITY]` in the subject line.
3. **What to include:**
   - The affected component, script, or package and its version or commit SHA
   - Step-by-step reproduction instructions or a proof-of-concept
   - Impact assessment (for example: privilege escalation, arbitrary code execution, local service exposure, or package/build verification bypass)

### Response Timeline

- **Initial acknowledgment:** Within 72 hours
- **Triage & status update:** Within 7 days
- **Fix & disclosure:** Coordinated disclosure once a patched release or signed package update is published. Security releases are marked with the **Security** badge in the [Changelog](https://mainstreamos.org/#changelog) and surface an immediate red update indicator in the desktop bar.

## Build, Package & Update Integrity

- **Signed repositories only:** Fresh installations use Arch's signed `core`, `extra`, and `multilib` repositories plus the signed `[mainstream]` binary repository (`SigLevel = Required`). No AUR helper is installed or invoked by default.
- **Verified upstream sources:** Packages built in [`MainstreamOS/packages`](https://github.com/MainstreamOS/packages) verify upstream source checksums (`sha256sums` / `b2sums`) and upstream PGP signatures (`validpgpkeys`) before compilation, and every output package and database is signed with the Mainstream signing key (`D644 BEB9 C1B7 668E 3A6C 16DA 8D56 7345 B265 848E`, published at [`https://mainstreamos.org/mainstream.pub`](https://mainstreamos.org/mainstream.pub)).
- **Snapshot-backed updates:** Updates through **Settings → Update** (`mainstream-update-helper`) take automatic Btrfs snapshots via Snapper before and after package transactions so any update can be rolled back from the Limine boot menu.

For a full overview of Mainstream's default firewall rules, ISO verification steps, and repository model, see the [Security documentation on mainstreamos.org](https://mainstreamos.org/#security).
