-- Nothing moves, things appear: fades only, kept short. popin 100% starts a
-- window at full size, which leaves the fade as the whole entrance.
hl.curve("minimalEase", {
    type = "bezier",
    points = {{0.25, 0.1}, {0.25, 1}}
})

-- windows
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 1.5,
    bezier = "minimalEase",
    style = "popin 100%"
})
hl.animation({
    leaf = "fadeIn",
    enabled = true,
    speed = 1.5,
    bezier = "minimalEase"
})
hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 1.2,
    bezier = "minimalEase",
    style = "popin 100%"
})
hl.animation({
    leaf = "fadeOut",
    enabled = true,
    speed = 1.2,
    bezier = "minimalEase"
})
hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 1.5,
    bezier = "minimalEase",
    style = "slide"
})
hl.animation({
    leaf = "border",
    enabled = true,
    speed = 4,
    bezier = "minimalEase"
})

-- layers
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 1.2,
    bezier = "minimalEase",
    style = "popin 100%"
})
hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 1.2,
    bezier = "minimalEase",
    style = "popin 100%"
})

-- fade
hl.animation({
    leaf = "fadeLayersIn",
    enabled = true,
    speed = 1.2,
    bezier = "minimalEase"
})
hl.animation({
    leaf = "fadeLayersOut",
    enabled = true,
    speed = 1.2,
    bezier = "minimalEase"
})

-- workspaces
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 3,
    bezier = "minimalEase",
    style = "fade"
})

-- specialWorkspace
hl.animation({
    leaf = "specialWorkspaceIn",
    enabled = true,
    speed = 1.5,
    bezier = "minimalEase",
    style = "fade"
})
hl.animation({
    leaf = "specialWorkspaceOut",
    enabled = true,
    speed = 1.2,
    bezier = "minimalEase",
    style = "fade"
})

-- zoom
hl.animation({
    leaf = "zoomFactor",
    enabled = true,
    speed = 2,
    bezier = "minimalEase"
})
