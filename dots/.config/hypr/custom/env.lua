-- Put extra environment variables here
-- https://wiki.hypr.land/Configuring/Environment-variables/

-- Input method (uncomment as needed)
-- See https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland
-- hl.env("QT_IM_MODULE", "fcitx")
-- hl.env("XMODIFIERS", "@im=fcitx")
-- hl.env("SDL_IM_MODULE", "fcitx")
-- hl.env("GLFW_IM_MODULE", "ibus")
-- hl.env("INPUT_METHOD", "fcitx")

-- Wayland
-- Tearing
-- hl.env("WLR_DRM_NO_ATOMIC", "1")
-- hl.env("WLR_NO_HARDWARE_CURSORS", "1")

-- Editor
-- hl.env("EDITOR", "vim")

-- Input / mouse / touchpad
-- Settings → Mouse panel rewrites these via Python regex; keep the shape
-- (one key per line, touchpad as a nested table).
hl.config({
    input = {
        sensitivity = 0.0,
        left_handed = false,
        accel_profile = "flat",
        natural_scroll = false,
        touchpad = {
            natural_scroll = true,
        },
    },
})
