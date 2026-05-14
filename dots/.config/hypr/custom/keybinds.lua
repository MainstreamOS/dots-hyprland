-- Add your own keybinds here.
-- https://wiki.hypr.land/Configuring/Binds/

-- Examples — uncomment and tweak as needed. The fork's defaults are in
-- hyprland/keybinds.lua and these run after, so anything here overrides.
--
-- hl.bind("SUPER + Return", hl.dsp.exec_cmd(terminal), {description = "Terminal"})
-- hl.bind("SUPER + T", hl.dsp.exec_cmd(terminal))
-- hl.bind("CTRL + ALT + T", hl.dsp.exec_cmd(terminal))
-- hl.bind("SUPER + E", hl.dsp.exec_cmd(fileManager), {description = "File manager"})
-- hl.bind("SUPER + B", hl.dsp.exec_cmd(browser), {description = "Browser"})
-- hl.bind("SUPER + C", hl.dsp.exec_cmd(codeEditor), {description = "Code editor"})
-- hl.bind("SUPER + X", hl.dsp.exec_cmd(textEditor), {description = "Text editor"})
-- hl.bind("CTRL + SUPER + V", hl.dsp.exec_cmd(volumeMixer), {description = "Volume mixer"})
-- hl.bind("SUPER + I", hl.dsp.exec_cmd(settingsApp), {description = "Settings app"})
-- hl.bind("CTRL + SHIFT + Escape", hl.dsp.exec_cmd(taskManager), {description = "Task manager"})

hl.bind("CTRL + SUPER + ALT + Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )
