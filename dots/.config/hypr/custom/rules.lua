-- Custom window / layer / workspace rules.
-- Window: https://wiki.hypr.land/Configuring/Window-Rules/
-- Workspace: https://wiki.hypr.land/Configuring/Workspace-Rules/

-- ######## Layer rules ########

-- ######## Window rules ########

-- GTK file picker / portal chooser
hl.window_rule({ match = { class = "xdg-desktop-portal-gtk" }, float = true, center = true, size = "900 600" })

-- Login image picker (kdialog)
hl.window_rule({ match = { title = "^Choose login image$" }, float = true, center = true, pin = true, size = "900 600" })

-- Common file dialog titles
hl.window_rule({ match = { title = "^Open File$" }, float = true })
hl.window_rule({ match = { title = "^Open Folder$" }, float = true })
hl.window_rule({ match = { title = "^Save File$" }, float = true })
hl.window_rule({ match = { title = "^Save As$" }, float = true })

-- Satty screenshot annotator
hl.window_rule({ match = { class = "^(com\\.gabm\\.satty)$" }, float = true, center = true })
hl.window_rule({ match = { class = "^(satty)$" }, float = true, center = true })

-- Nautilus when its title still reads the bare app id (early-load state)
hl.window_rule({ match = { class = "^(org\\.gnome\\.Nautilus)$", title = "^(org\\.gnome\\.Nautilus)$" }, float = true, center = true })

-- Calamares installer
hl.window_rule({
    name = "calamares-by-class",
    match = { class = "^(io.calamares.calamares)$" },
    float = true,
    suppress_event = "fullscreen maximize",
    size = "1500 800",
    center = true,
})
