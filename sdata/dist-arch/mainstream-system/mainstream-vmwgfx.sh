# VMware's virtual GPU (vmwgfx, which VirtualBox's VMSVGA adapter emulates too)
# needs a small fix loaded into Hyprland, or Hyprland turns away every window an
# app draws on the GPU. The desktop session picks it up here, through the login
# shell SDDM starts it from; the library leaves the apps Hyprland starts alone.
# Machines without that GPU are left exactly as they are.
_mainstream_vmwgfx_lib=/usr/lib/mainstream/libmainstream-vmwgfx-close.so
_mainstream_vmwgfx_gpu() {
    # Every login shell runs this, so the files are read with the shell's own
    # read rather than a cat per device.
    for _mainstream_vmwgfx_dev in /sys/bus/pci/devices/*; do
        { read -r _mainstream_vmwgfx_id < "$_mainstream_vmwgfx_dev/vendor"; } 2>/dev/null || continue
        [ "$_mainstream_vmwgfx_id" = 0x15ad ] || continue
        { read -r _mainstream_vmwgfx_id < "$_mainstream_vmwgfx_dev/device"; } 2>/dev/null || continue
        case $_mainstream_vmwgfx_id in
            0x0405|0x0406) return 0 ;;
        esac
    done
    return 1
}
if [ -r "$_mainstream_vmwgfx_lib" ] && _mainstream_vmwgfx_gpu; then
    case ":${LD_PRELOAD-}:" in
        *":$_mainstream_vmwgfx_lib:"*) ;;
        *) export LD_PRELOAD="$_mainstream_vmwgfx_lib${LD_PRELOAD:+:$LD_PRELOAD}" ;;
    esac
fi
unset -f _mainstream_vmwgfx_gpu
unset _mainstream_vmwgfx_lib _mainstream_vmwgfx_dev _mainstream_vmwgfx_id
