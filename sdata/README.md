This folder mainly contains data for the script `setup`.

## Install Mainstream

On an installed Arch-based system, run `./setup install` as your user. The installer offers Default, Custom, Gaming, and OS only. Use `--profile` to skip the picker. For a scripted Custom install, run `./setup install --profile custom --apps chromium,org.gimp.GIMP` and use `./setup install --list-apps` to look up IDs.

From the stock Arch USB, boot in UEFI mode and connect to the internet. Run this at the live root console.

```bash
bash <(curl -fsSL https://mainstreamos.org/install.sh) --fresh
```

Choose an app profile, pick the disk and installation mode, and decide whether to encrypt the system. Create your account and review your choices. Install alongside uses a contiguous unallocated GPT region of at least 32 GiB and creates a separate EFI partition for Mainstream. Prepare free space in the existing operating system first if needed.

When prompted, press Enter to restart and remove the USB as the screen goes blank. Mainstream finishes setting up the desktop automatically and restarts to the sign-in screen. If you enabled encryption, enter your disk passphrase at each boot. If the network does not reconnect, the installer opens a connection picker.

- TODO: output the logs to a temp file, then show the path of the file so users will be able to read it again or upload it to issue.
- TODO: unify the message output via functions (for example `log_error`, `log_warning`).
