-- ######## Window rules ########

-- Disable blur for xwayland context menus
hl.window_rule({match = {class = "^()$", title = "^()$" },                   no_blur = true })

-- Floating
hl.window_rule({match = {title = "^(Open File)(.*)$" },                      center = true})
hl.window_rule({match = {title = "^(Open File)(.*)$" },                      float = true})
hl.window_rule({match = {title = "^(Select a File)(.*)$" },                  center = true})
hl.window_rule({match = {title = "^(Select a File)(.*)$" },                  float = true})
hl.window_rule({match = {title = "^(Choose wallpaper)(.*)$" },               center = true})
hl.window_rule({match = {title = "^(Choose wallpaper)(.*)$" },               float = true})
hl.window_rule({match = {title = "^(Choose wallpaper)(.*)$" },               size = {"(monitor_w*0.60)", "(monitor_h*0.65)"} })
hl.window_rule({match = {title = "^(Open Folder)(.*)$" },                    center = true})
hl.window_rule({match = {title = "^(Open Folder)(.*)$" },                    float = true})
hl.window_rule({match = {title = "^(Save As)(.*)$" },                        center = true})
hl.window_rule({match = {title = "^(Save As)(.*)$" },                        float = true})
hl.window_rule({match = {title = "^(Library)(.*)$" },                        center = true})
hl.window_rule({match = {title = "^(Library)(.*)$" },                        float = true})
hl.window_rule({match = {title = "^(File Upload)(.*)$" },                    center = true})
hl.window_rule({match = {title = "^(File Upload)(.*)$" },                    float = true})
hl.window_rule({match = {title = "^(.*)(wants to save)$" },                  center = true})
hl.window_rule({match = {title = "^(.*)(wants to save)$" },                  float = true})
hl.window_rule({match = {title = "^(.*)(wants to open)$" },                  center = true})
hl.window_rule({match = {title = "^(.*)(wants to open)$" },                  float = true})
-- Keep hidden games rendering — alt-tabbing must not freeze multiplayer
-- ticks or starve OBS game capture (rate: misc:render_unfocused_fps).
hl.window_rule({match = {class = "^(steam_app_.*)$" },                       render_unfocused = true})

hl.window_rule({match = {class = "^(blueberry\\.py)$" },                     float = true})
hl.window_rule({match = {class = "^(guifetch)$" },                           float = true}) -- FlafyDev/guifetch
hl.window_rule({match = {class = "^(pavucontrol)$" },                        float = true})
hl.window_rule({match = {class = "^(pavucontrol)$" },                        size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
hl.window_rule({match = {class = "^(pavucontrol)$" },                        center = true})
hl.window_rule({match = {class = "^(org.pulseaudio.pavucontrol)$" },         float = true})
hl.window_rule({match = {class = "^(org.pulseaudio.pavucontrol)$" },         size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
hl.window_rule({match = {class = "^(org.pulseaudio.pavucontrol)$" },         center = true})
hl.window_rule({match = {class = "^(nm-connection-editor)$" },               float = true})
hl.window_rule({match = {class = "^(nm-connection-editor)$" },               size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
hl.window_rule({match = {class = "^(nm-connection-editor)$" },               center = true})
hl.window_rule({match = {class = ".*plasmawindowed.*" },                     float = true})
hl.window_rule({match = {class = "kcm_.*" },                                  float = true})
hl.window_rule({match = {class = ".*bluedevilwizard" },                      float = true})
hl.window_rule({match = {title = ".*Welcome" },                              float = true})
hl.window_rule({match = {title = "^(Mainstream Settings)$" },               float = true})
hl.window_rule({match = {title = ".*Shell conflicts.*" },                    float = true})
hl.window_rule({match = {class = "org.freedesktop.impl.portal.desktop.kde" }, float = true})
hl.window_rule({match = {class = "org.freedesktop.impl.portal.desktop.kde" }, size = {"(monitor_w*0.60)", "(monitor_h*0.65)"} })
hl.window_rule({match = {class = "^(Zotero)$" },                             float = true})
hl.window_rule({match = {class = "^(Zotero)$" },                             size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })

-- Move
-- kde-material-you-colors spawns a window when changing dark/light theme. This is to make sure it doesn't interfere at all.
hl.window_rule({match = {class = "^(plasma-changeicons)$" }, float = true})
hl.window_rule({match = {class = "^(plasma-changeicons)$" }, no_initial_focus = true})
hl.window_rule({match = {class = "^(plasma-changeicons)$" }, move = {999999, 999999}})
-- stupid dolphin copy
hl.window_rule({match = {title = "^(Copying — Dolphin)$" }, move = {40, 80}})

-- Tiling
hl.window_rule({match = {class = "^dev\\.warp\\.Warp$" }, tile = true})

-- Picture-in-Picture
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, float = true})
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, keep_aspect_ratio = true})
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, move = {"(monitor_w*0.73)", "(monitor_h*0.72)"} })
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, size = {"(monitor_w*0.25)", "(monitor_h*0.25)"} })
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, float = true})
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, pin = true})

-- Screen sharing
hl.window_rule({match = {title = ".*is sharing (a window|your screen).*" }, float = true})
hl.window_rule({match = {title = ".*is sharing (a window|your screen).*" }, pin = true})
hl.window_rule({match = {title = ".*is sharing (a window|your screen).*" }, move = {"(monitor_w*.5-window_w*.5)", "(monitor_h-window_h-12)"} })

-- --- Tearing ---
hl.window_rule({match = {title = ".*\\.exe" }, immediate = true})
hl.window_rule({match = {title = ".*minecraft.*" }, immediate = true})
hl.window_rule({match = {class = "^(steam_app).*" }, immediate = true})

-- No shadow for tiled windows
hl.window_rule({match = {float = 0 }, no_shadow = true})

-- Open a floating window somewhere its title bar can be reached. A float's
-- title bar is the only handle it has, and a client may ask to open at an
-- absolute position, so one can arrive with that bar beneath the bar or the
-- dock. The panels' own reservations are already in monitor.reserved; this
-- moves a new float to the near edge of the room they leave, and moves
-- nothing else. What size a window opens at is left to it, and where a
-- window is deliberately placed is left alone unless its title bar would
-- land somewhere it cannot be grabbed.
--
-- `window.open` fires once the floating layout has given the window its
-- initial geometry. hyprbars draws its bar above that geometry rather than
-- inside it, so the bar's own height is part of the room the window needs.
local function openFloatingWindowWithinReach(window)
    if not window or not window.floating or window.fullscreen ~= 0 then
        return
    end

    local monitor = window.monitor
    if not monitor then
        return
    end

    local reserved = monitor.reserved
    local at = window.at
    local size = window.size
    if not reserved or not at or not size then
        return
    end

    -- Parenthesized: hl.get_config answers (value, err), and in the last
    -- argument position both would reach tonumber, handing it the error
    -- string as a numeric base. A key that is absent -- bar_height whenever
    -- the plugin is not loaded -- would raise on every window.open.
    local border = tonumber((hl.get_config("general:border_size"))) or 0
    local titleBar = tonumber((hl.get_config("plugin:hyprbars:bar_height"))) or 0
    local gapsOut = hl.get_config("general:gaps_out") or {}
    -- The room a tiled window would be handed: the monitor, less what the
    -- panels reserve on each edge, less the gap and border every tile keeps.
    -- A float is given the same room, so where it may open does not depend on
    -- which edge the bar and the dock happen to sit on.
    local left = monitor.x + (reserved.left or 0) + (gapsOut.left or 0) + border
    local top = monitor.y + (reserved.top or 0) + (gapsOut.top or 0) + border
    local right = monitor.x + monitor.width - (reserved.right or 0) - (gapsOut.right or 0) - border
    local bottom = monitor.y + monitor.height - (reserved.bottom or 0) - (gapsOut.bottom or 0) - border

    -- A title bar is drawn above the position a window reports, so the room it
    -- needs comes off the top wherever the panels are. Counting it only under
    -- a top reservation is what walked the bar off screen once the panel moved
    -- to the other edge: with nothing reserved above, a window opened flush to
    -- the screen's own top and wore its title bar past it.
    local contentTop = top + titleBar
    if right <= left or bottom <= contentTop then
        return
    end

    -- Held inside the room, a window wears its title bar inside it too, however
    -- big the window is, and that bar is the one handle a float has. So moving
    -- is all it takes: what a window asked to be is its own business once it
    -- can be reached, and one larger than the room keeps that size and
    -- overhangs the far edge rather than being cut down to fit. The floors are
    -- what make this hold — without them a window too big for the room is
    -- pushed past the near edge instead of resting against it, which is the
    -- one way the title bar still gets away.
    local x = math.min(math.max(at.x, left), math.max(left, right - size.x))
    local y = math.min(math.max(at.y, contentTop), math.max(contentTop, bottom - size.y))

    if x ~= at.x or y ~= at.y then
        hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = window }))
    end
end

hl.on("window.open", openFloatingWindowWithinReach)

-- ######## Workspace rules ########
hl.workspace_rule({ workspace = "special:special", gaps_out = 30 })

-- ######## Layer rules ########
hl.layer_rule({ match = { namespace = ".*" }, xray = true})
hl.layer_rule({ match = { namespace = "walker" }, no_anim = true})
hl.layer_rule({ match = { namespace = "selection" }, no_anim = true})
hl.layer_rule({ match = { namespace = "overview" }, no_anim = true})
hl.layer_rule({ match = { namespace = "anyrun" }, no_anim = true})
hl.layer_rule({ match = { namespace = "indicator.*" }, no_anim = true})
hl.layer_rule({ match = { namespace = "osk" }, no_anim = true})
hl.layer_rule({ match = { namespace = "hyprpicker" }, no_anim = true})

hl.layer_rule({ match = { namespace = "noanim" }, no_anim = true})
hl.layer_rule({ match = { namespace = "gtk-layer-shell" }, blur = true})
hl.layer_rule({ match = { namespace = "gtk-layer-shell" }, ignore_alpha = 0})
hl.layer_rule({ match = { namespace = "launcher" }, blur = true})
hl.layer_rule({ match = { namespace = "launcher" }, ignore_alpha = 0.5})
hl.layer_rule({ match = { namespace = "notifications" }, blur = true})
hl.layer_rule({ match = { namespace = "notifications" }, ignore_alpha = 0.69})
hl.layer_rule({ match = { namespace = "logout_dialog" }, blur = true}) -- wlogout

-- ags
hl.layer_rule({ match = { namespace = "sideleft.*" }, animation = "slide left"})
hl.layer_rule({ match = { namespace = "sideright.*" }, animation = "slide right"})
hl.layer_rule({ match = { namespace = "session[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "bar[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "bar[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "barcorner.*" }, blur = true})
hl.layer_rule({ match = { namespace = "barcorner.*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "dock[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "dock[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "indicator.*" }, blur = true})
hl.layer_rule({ match = { namespace = "indicator.*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "overview[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "overview[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "cheatsheet[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "cheatsheet[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "sideright[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "sideright[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "sideleft[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "sideleft[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "indicator.*" }, blur = true})
hl.layer_rule({ match = { namespace = "indicator.*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "osk[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "osk[0-9]*" }, ignore_alpha = 0.6})

-- Quickshell
-- Quickshell: illogical-impulse
hl.layer_rule({ match = { namespace = "quickshell:.*" }, blur_popups = true})
hl.layer_rule({ match = { namespace = "quickshell:.*" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:.*" }, ignore_alpha = 0.79})
-- Blur stops at a fixed alpha, so with the shared 0.79 the bar loses its blur
-- between two neighboring steps of its own transparency slider, and where that
-- lands moves with the interface's transparency setting — around 7% of the
-- slider on a wallpaper the automatic setting reads as fairly vibrant. Held low
-- enough that the slider is smooth through the range anyone uses, and above the
-- shadow these surfaces cast. Their layer is larger than the shape drawn on it:
-- the rest is the room the shadow falls in, and a floor under the shadow's own
-- alpha sends the blur through that too, ringing every surface in a frosted
-- halo. The dock and sidebars ride the same floor, because the shared threshold
-- above sits inside the reach of their stock alpha — the automatic transparency
-- can land them a hair under it on a dark wallpaper, and a surface should not
-- lose its blur to settings nobody touched.
hl.layer_rule({ match = { namespace = "quickshell:(bar|verticalBar|dock[A-Za-z]*|sidebarLeft|sidebarRight)" }, ignore_alpha = 0.35})
-- The dock is lifted above the overview's dim while the overview is open, so
-- it is the one blurred surface here whose blur edge is ever seen against
-- anything but the wallpaper. Blurring the wallpaper alone punches a bright,
-- stepped outline through the dim, because that edge is decided per pixel with
-- nothing in between. Reading what is actually behind it puts the dim on both
-- sides of the line, and the line has nothing left to show.
hl.layer_rule({ match = { namespace = "quickshell:dock[A-Za-z]*" }, xray = false})
hl.layer_rule({ match = { namespace = "quickshell:bar" }, animation = "slide"})
hl.layer_rule({ match = { namespace = "quickshell:actionCenter" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:cheatsheet" }, animation = "slide bottom"})
hl.layer_rule({ match = { namespace = "quickshell:dock" }, animation = "slide bottom"})
hl.layer_rule({ match = { namespace = "quickshell:dockTop" }, animation = "slide top"})
hl.layer_rule({ match = { namespace = "quickshell:dockLeft" }, animation = "slide left"})
hl.layer_rule({ match = { namespace = "quickshell:dockRight" }, animation = "slide right"})
-- Arrangement order the shell itself depends on, so it belongs here and not in
-- custom/, which an existing install keeps its own copy of. A higher order is
-- handled first and so reserves its edge first: either bar outranks a pinned
-- dock sharing its layer, leaving the dock to be the one shortened.
hl.layer_rule({ match = { namespace = "quickshell:bar" }, order = 10 })
hl.layer_rule({ match = { namespace = "quickshell:verticalBar" }, order = 10 })
hl.layer_rule({ match = { namespace = "quickshell:screenCorners" }, animation = "popin 120%"})
hl.layer_rule({ match = { namespace = "quickshell:lockWindowPusher" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:notificationPopup" }, animation = "fade"})
hl.layer_rule({ match = { namespace = "quickshell:overlay" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:overlay" }, ignore_alpha = 1})
hl.layer_rule({ match = { namespace = "quickshell:overview" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:osk" }, animation = "slide bottom"})
hl.layer_rule({ match = { namespace = "quickshell:polkit" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:popup" }, xray = false}) -- No weird color for bar tooltips (this in theory should suffice)
hl.layer_rule({ match = { namespace = "quickshell:popup" }, ignore_alpha = 1}) -- No weird color for bar tooltips (but somehow this is necessary)
hl.layer_rule({ match = { namespace = "quickshell:mediaControls" }, ignore_alpha = 1}) -- Same as above
hl.layer_rule({ match = { namespace = "quickshell:reloadPopup" }, animation = "slide"})
hl.layer_rule({ match = { namespace = "quickshell:regionSelector" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:screenshot" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:session" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:session" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:session" }, ignore_alpha = 0})
-- Unnamed direction so the slide follows whichever edge the panel anchored to,
-- the way the vertical bar below is served on either side by one rule.
hl.layer_rule({ match = { namespace = "quickshell:sidebarRight" }, animation = "slide"})
hl.layer_rule({ match = { namespace = "quickshell:sidebarLeft" }, animation = "slide"})
hl.layer_rule({ match = { namespace = "quickshell:verticalBar" }, animation = "slide"})
hl.layer_rule({ match = { namespace = "quickshell:osk" }, order = -1})
-- Quickshell: waffles
hl.layer_rule({ match = { namespace = "quickshell:wallpaperSelector" }, animation = "slide top"})
hl.layer_rule({ match = { namespace = "quickshell:wNotificationCenter" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:wOnScreenDisplay" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:wStartMenu" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:wTaskView" }, ignore_alpha = 0})
hl.layer_rule({ match = { namespace = "quickshell:wTaskView" }, no_anim = true})

-- Launchers need to be FAST
hl.layer_rule({ match = { namespace = "gtk4-layer-shell" }, no_anim = true})

-- The settings page keeps its window rules in a file of its own, loaded after
-- everything above so a rule made there outranks a shipped one for the same
-- window. Absent or broken, nothing happens.
pcall(dofile, os.getenv("HOME") .. "/.config/hypr/hyprland/userrules.lua")
