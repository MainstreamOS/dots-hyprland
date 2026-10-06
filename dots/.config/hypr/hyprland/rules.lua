-- ######## Window rules ########

-- Disable blur for xwayland context menus
hl.window_rule({match = {class = "^()$", title = "^()$" },                   no_blur = true })
-- Menus and dropdowns of X11 apps such as Steam are windows of their own with
-- no title, drawn square to the edge; window rounding would clip their corners.
hl.window_rule({match = {xwayland = true, title = "^()$" },                  rounding = 0 })

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
-- Headset input never reaches the compositor, so the idle timers would lock, blank and
-- suspend mid-session. SteamVR opens its status window, XWayland or native, every session.
hl.window_rule({name = "steamvr-idle-inhibit", match = {class = "^(vrmonitor|com\\.valvesoftware\\.vrmonitor)$" }, idle_inhibit = "always"})

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

-- Keep a floating window somewhere its title bar can be reached. A float's
-- title bar is the only handle it has, and a client may ask to open at an
-- absolute position, so one can arrive with that bar beneath the bar or the
-- dock. The panels' own reservations are already in monitor.reserved; this
-- moves a float to the near edge of the room they leave. Where a window is
-- deliberately placed is left alone unless its title bar would land
-- somewhere it cannot be grabbed.
--
-- The room is what a tiled window would be handed: the monitor, less what
-- the panels reserve on each edge, less the gap and border every tile keeps.
-- A float is given the same room, so where it may sit does not depend on
-- which edge the bar and the dock happen to be on. hyprbars draws its bar
-- above the position a window reports rather than inside it, so the bar's
-- own height comes off the top wherever the panels are. Counting it only
-- under a top reservation is what walked the bar off screen once the panel
-- moved to the other edge: with nothing reserved above, a window sat flush
-- to the screen's own top and wore its title bar past it.
local function reachableRoom(monitor)
    local reserved = monitor and monitor.reserved
    if not reserved then
        return nil
    end

    -- A monitor's width and height arrive in physical pixels, while its
    -- position, what it reserves, and every window's place and size are in
    -- logical ones, so the room is measured in logical pixels as well. Taken
    -- as they come, the far edges of a scaled monitor sat well past the
    -- screen and never held anything.
    local scale = tonumber(monitor.scale) or 1
    if scale <= 0 then
        scale = 1
    end
    local width = monitor.width / scale
    local height = monitor.height / scale

    -- An option that does not exist, such as the title bar's while its plugin
    -- is not loaded, comes back as nil and an error message. Passed on whole,
    -- tonumber would take that message as its base and throw, so only the
    -- value is kept.
    local border = tonumber((hl.get_config("general:border_size"))) or 0
    local titleBar = tonumber((hl.get_config("plugin:hyprbars:bar_height"))) or 0
    local gapsOut = hl.get_config("general:gaps_out") or {}
    local left = monitor.x + (reserved.left or 0) + (gapsOut.left or 0) + border
    local top = monitor.y + (reserved.top or 0) + (gapsOut.top or 0) + border + titleBar
    local right = monitor.x + width - (reserved.right or 0) - (gapsOut.right or 0) - border
    local bottom = monitor.y + height - (reserved.bottom or 0) - (gapsOut.bottom or 0) - border
    if right <= left or bottom <= top then
        return nil
    end

    return { left = left, top = top, right = right, bottom = bottom }
end

-- Held inside the room, a window wears its title bar inside it too, however
-- big the window is, and that bar is the one handle a float has. The floors
-- are what make this hold: without them a window too big for the room is
-- pushed past the near edge instead of resting against it, which is the
-- one way the title bar still gets away.
local function withinReach(room, x, y, size)
    return math.min(math.max(x, room.left), math.max(room.left, room.right - size.x)),
           math.min(math.max(y, room.top), math.max(room.top, room.bottom - size.y))
end

local function keepFloatingWindowWithinReach(window, fitOnOpen)
    if not window or not window.floating or window.fullscreen ~= 0 then
        return
    end

    local at = window.at
    local size = window.size
    local room = reachableRoom(window.monitor)
    if not at or not size or not room then
        return
    end

    -- Apps that remember being maximized reopen at the whole screen's size,
    -- which overhangs the dock, so they open fitted to the room instead.
    if fitOnOpen then
        local w = math.min(size.x, room.right - room.left)
        local h = math.min(size.y, room.bottom - room.top)
        if w ~= size.x or h ~= size.y then
            hl.dispatch(hl.dsp.window.resize({ x = w, y = h, window = window }))
            size = { x = w, y = h }
        end
    end

    local x, y = withinReach(room, at.x, at.y, size)
    if x ~= at.x or y ~= at.y then
        hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = window }))
    end
end

-- Some events are announced before Hyprland acts on them. The next turn of the loop
-- comes after that and before anything is drawn.
local function nextTurn(fn)
    hl.timer(fn, { timeout = 1, type = "oneshot" })
end

-- `window.open` fires once the floating layout has given the window its
-- initial geometry.
hl.on("window.open", function(window)
    keepFloatingWindowWithinReach(window, true)
end)

-- A float can end up under a panel later as well: moved to a workspace on a
-- monitor whose panels sit elsewhere, or dropped there by an overview. Both
-- announce the move before the window is put in its new place.
hl.on("window.move_to_workspace", function(window)
    nextTurn(function()
        keepFloatingWindowWithinReach(window)
    end)
end)

-- A float restored from maximized that still fills the room would look as if
-- nothing happened, so the title bar's scroll down hands it a quarter of the
-- room, centered. A float with a smaller size of its own keeps it.
function MainstreamShrinkRoomFillingFloat(window)
    if not window or not window.floating or window.fullscreen ~= 0 then
        return
    end
    local size = window.size
    local room = reachableRoom(window.monitor)
    if not size or not room then
        return
    end
    local roomW, roomH = room.right - room.left, room.bottom - room.top
    if size.x < roomW - 1 or size.y < roomH - 1 then
        return
    end
    local w, h = math.floor(roomW / 2), math.floor(roomH / 2)
    hl.dispatch(hl.dsp.window.resize({ x = w, y = h, window = window }))
    hl.dispatch(hl.dsp.window.move({
        x = math.floor(room.left + (roomW - w) / 2),
        y = math.floor(room.top + (roomH - h) / 2),
        window = window,
    }))
end

-- The launcher's overview drops a floating window where the pointer let go
-- and asks here for the move to make, so the drop lands within reach. x and
-- y are relative to the window's monitor; the answer is the move in global
-- coordinates, unclamped when the window cannot be found.
function MainstreamFloatMoveWithinReach(selector, x, y)
    local window = hl.get_window(selector)
    local monitor = window and window.monitor
    if not monitor then
        return hl.dsp.window.move({ x = x, y = y, window = selector })
    end

    local gx, gy = monitor.x + x, monitor.y + y
    local room = reachableRoom(monitor)
    if room and window.size then
        gx, gy = withinReach(room, gx, gy, window.size)
    end
    return hl.dsp.window.move({ x = gx, y = gy, window = selector })
end

-- Hyprland draws every float allowed over a floating fullscreen window on top of it, but clicks
-- follow the stack. One stacked below it is raised if it has focus or belongs with it, else sent behind.
local settlePending = false
local settleWatch = nil

-- X11 menus and tooltips have no title and close on their own, so they are left alone.
local function shownOverFullscreen(window)
    return window.allowed_over_fullscreen and not window.pinned and not window.hidden
        and not (window.xwayland and window.title == "")
end

-- Lua cannot see a dialog's parent, so the app's own windows and portal file choosers stay up;
-- hiding a modal dialog would leave its parent looking frozen.
local function staysWith(window, fullscreen)
    local pid, class = fullscreen.pid, window.class or ""
    return (pid ~= nil and pid > 1 and window.pid == pid)
        or class:find("^xdg%-desktop%-portal") ~= nil or class:find("^org%.freedesktop%.impl%.portal%.") ~= nil
end

local function settleWorkspace(workspace, activeWindow)
    local fullscreen = workspace and workspace.fullscreen_window
    if not fullscreen or not fullscreen.floating then
        return false
    end

    local active = activeWindow()
    local below, shownOver, focused, raise, hide = true, false, nil, {}, {}
    for _, window in ipairs(hl.get_windows({ workspace = workspace, floating = true })) do
        if window == fullscreen then
            below = false
        elseif shownOverFullscreen(window) then
            if not below then
                shownOver = true
            elseif window == active then
                focused = window
            elseif staysWith(window, fullscreen) then
                raise[#raise + 1] = window
            else
                hide[#hide + 1] = window
            end
        end
    end
    if focused then
        raise[#raise + 1] = focused
    end

    -- Each one lowered lands at the very bottom, so the topmost goes first to keep their order.
    for i = #hide, 1, -1 do
        hl.dispatch(hl.dsp.window.alter_zorder({ mode = "bottom", window = hide[i] }))
    end
    for _, window in ipairs(raise) do
        hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = window }))
    end

    return shownOver or #raise > 0
end

local function settleFloatsOverFullscreen()
    -- Focus is looked up only once a floating fullscreen window turns up, and only once
    -- per pass, as a raise can move it.
    local active
    local function activeWindow()
        if active == nil then
            active = hl.get_active_window() or false
        end
        return active
    end

    local shownOver = false
    for _, monitor in ipairs(hl.get_monitors()) do
        shownOver = settleWorkspace(monitor.active_workspace, activeWindow) or shownOver
        shownOver = settleWorkspace(monitor.active_special_workspace, activeWindow) or shownOver
    end

    -- While a float shows over one, this also catches raises no event reports, such as a title bar click.
    if shownOver and not settleWatch then
        settleWatch = hl.timer(settleFloatsOverFullscreen, { timeout = 250, type = "repeat" })
    elseif settleWatch and settleWatch:is_enabled() ~= shownOver then
        settleWatch:set_enabled(shownOver)
    end
end

local function settleQueued()
    settlePending = false
    settleFloatsOverFullscreen()
end

-- Binds run before a click raises its window, and focus can come before a raise.
local function settleSoon()
    if settlePending then
        return
    end
    settlePending = true
    nextTurn(settleQueued)
end

-- A reload drops the watch, so it is checked again after one.
for _, event in ipairs({
    "window.active", "window.open", "window.fullscreen", "window.move_to_workspace", "window.pin",
    "workspace.active", "workspace.special_active", "workspace.move_to_monitor", "monitor.added", "config.reloaded",
}) do
    hl.on(event, settleSoon)
end
for button = 272, 276 do
    hl.bind("mouse:" .. button, settleSoon, { non_consuming = true, ignore_mods = true, dont_inhibit = true, submap_universal = true })
end

-- The dock's raise can cover a float shown over a fullscreen one, so it settles after.
function MainstreamRaiseFloat(selector)
    settleSoon()
    return hl.dsp.window.alter_zorder({ mode = "top", window = selector })
end

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
-- The catch-all above also blurs surfaces nothing is ever seen through: the
-- wallpaper layer itself, the corner masks and the hot-corner ripple. The
-- wallpaper covers the whole screen, and the blur pass runs over its full
-- extent on every damaged frame although none of it reaches the screen.
-- Measured on a 4K desktop, that was most of what blur cost, with the bar,
-- dock and sidebars a fraction of it. The overview's dim stays blurred: what
-- it frosts behind the overview is very much seen.
hl.layer_rule({ match = { namespace = "quickshell:(background|screenCorners|hotCornerRipple)" }, blur = false})
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
-- The dock and the app list sit above the overview's dim while the overview is
-- open, so they are the blurred surfaces here whose blur edge is ever seen
-- against anything but the wallpaper. Blurring the wallpaper alone punches a
-- bright, stepped outline through the dim, because that edge is decided per
-- pixel with nothing in between. Reading what is actually behind them puts the
-- dim on both sides of the line, and the line has nothing left to show. The
-- app list wears the dock's surface besides, so the two have to frost the same
-- way or they stop reading as one material. The dim itself is there to obscure
-- the apps behind the launcher; with xray it would frost the wallpaper and
-- leave every window legible through it.
hl.layer_rule({ match = { namespace = "quickshell:(dock[A-Za-z]*|overview[A-Za-z]*)" }, xray = false})
hl.layer_rule({ match = { namespace = "quickshell:bar" }, animation = "slide"})
hl.layer_rule({ match = { namespace = "quickshell:actionCenter" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:cheatsheet" }, animation = "slide bottom"})
-- A menu belongs under the pointer at once. The stock layer animation
-- scales it up from 93%, which reads as the menu arriving from somewhere.
hl.layer_rule({ match = { namespace = "quickshell:desktopMenu" }, animation = "fade"})
hl.layer_rule({ match = { namespace = "quickshell:dock" }, animation = "slide bottom"})
hl.layer_rule({ match = { namespace = "quickshell:dockTop" }, animation = "slide top"})
hl.layer_rule({ match = { namespace = "quickshell:dockLeft" }, animation = "slide left"})
hl.layer_rule({ match = { namespace = "quickshell:dockRight" }, animation = "slide right"})
-- Arrangement order the shell itself depends on, so it belongs here and not in
-- custom/, which an existing install keeps its own copy of. A higher order is
-- handled first and so reserves its edge first: either bar outranks a pinned
-- dock sharing its layer, leaving the dock to be the one shortened. A pinned
-- left sidebar comes after everything else, so it only pushes windows and fits
-- between the bar and the dock instead of shortening either of them.
hl.layer_rule({ match = { namespace = "quickshell:bar" }, order = 10 })
hl.layer_rule({ match = { namespace = "quickshell:verticalBar" }, order = 10 })
hl.layer_rule({ match = { namespace = "quickshell:sidebarLeft" }, order = -1 })
hl.layer_rule({ match = { namespace = "quickshell:screenCorners" }, animation = "popin 120%"})
hl.layer_rule({ match = { namespace = "quickshell:lockWindowPusher" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:notificationPopup" }, animation = "fade"})
hl.layer_rule({ match = { namespace = "quickshell:overlay" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:overlay" }, ignore_alpha = 1})
hl.layer_rule({ match = { namespace = "quickshell:overview" }, no_anim = true})
-- The dim grows from a pixel to the screen on every open; animated, that
-- reads as blur spreading outward. It appears in one step, like the launcher.
hl.layer_rule({ match = { namespace = "quickshell:overviewDim" }, no_anim = true})
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
hl.layer_rule({ match = { namespace = "quickshell:wallpaperSelector" }, animation = "slide top"})

-- Launchers need to be FAST
hl.layer_rule({ match = { namespace = "gtk4-layer-shell" }, no_anim = true})

-- The settings page keeps its window rules in a file of its own, loaded after
-- everything above so a rule made there outranks a shipped one for the same
-- window. Absent or broken, nothing happens.
pcall(dofile, os.getenv("HOME") .. "/.config/hypr/hyprland/userrules.lua")
