-- Overshoot and settle: everything lands a little past its mark and springs
-- back. The exits stay plain — an overshoot on the way out reads as a glitch.
hl.curve("bouncyOvershoot", {
    type = "bezier",
    points = {{0.34, 1.56}, {0.64, 1}}
})
hl.curve("bouncyLob", {
    type = "bezier",
    points = {{0.68, -0.3}, {0.32, 1.3}}
})
hl.curve("bouncyExit", {
    type = "bezier",
    points = {{0.36, 0}, {0.66, -0.36}}
})

-- windows
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 3.5,
    bezier = "bouncyOvershoot",
    style = "popin 60%"
})
hl.animation({
    leaf = "fadeIn",
    enabled = true,
    speed = 2.5,
    bezier = "bouncyOvershoot"
})
hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 2,
    bezier = "bouncyExit",
    style = "popin 80%"
})
hl.animation({
    leaf = "fadeOut",
    enabled = true,
    speed = 2,
    bezier = "bouncyExit"
})
hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 3.5,
    bezier = "bouncyOvershoot",
    style = "slide"
})
hl.animation({
    leaf = "border",
    enabled = true,
    speed = 10,
    bezier = "bouncyOvershoot"
})

-- layers
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 3,
    bezier = "bouncyOvershoot",
    style = "popin 85%"
})
hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 2,
    bezier = "bouncyExit",
    style = "popin 94%"
})

-- fade
hl.animation({
    leaf = "fadeLayersIn",
    enabled = true,
    speed = 0.5,
    bezier = "bouncyOvershoot"
})
hl.animation({
    leaf = "fadeLayersOut",
    enabled = true,
    speed = 2,
    bezier = "bouncyExit"
})

-- workspaces
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 7,
    bezier = "bouncyLob",
    style = "slide"
})

-- specialWorkspace
hl.animation({
    leaf = "specialWorkspaceIn",
    enabled = true,
    speed = 3.2,
    bezier = "bouncyOvershoot",
    style = "slidevert"
})
hl.animation({
    leaf = "specialWorkspaceOut",
    enabled = true,
    speed = 1.5,
    bezier = "bouncyExit",
    style = "slidevert"
})

-- zoom
hl.animation({
    leaf = "zoomFactor",
    enabled = true,
    speed = 3,
    bezier = "bouncyOvershoot"
})
