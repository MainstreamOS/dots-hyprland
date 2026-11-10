This folder mainly contains data for the script `setup`.

## Install Mainstream

On an installed Arch-based system, run `./setup install` as your user. The installer offers Default, Custom, Gaming, and OS only. Use `--profile` to skip the picker. For a scripted Custom install, run `./setup install --profile custom --apps chromium,org.gimp.GIMP` and use `./setup install --list-apps` to look up IDs.

From the stock Arch USB, boot in UEFI mode and connect to the internet. Install Git in the live session with `pacman -Sy --needed git` if needed. Clone the installer, then run `./setup install --fresh` from that checkout in the live root console. Choose an app profile and a disk. Install alongside uses a contiguous unallocated GPT region of at least 32 GiB and creates a separate EFI partition for Mainstream. Prepare free space in the existing operating system first if needed. Archinstall shows the proposed layout and lets you set a LUKS passphrase for the Btrfs root.

Choose **Exit** when Archinstall finishes. Reboot into the new Arch system, sign in as the user you created, and run `mainstream-finish-install` to apply the chosen profile. If you use Wi-Fi, reconnect with `nmtui` first.

- TODO: output the logs to a temp file, then show the path of the file so users will be able to read it again or upload it to issue.
- TODO: unify the message output via functions (for example `log_error`, `log_warning`).
