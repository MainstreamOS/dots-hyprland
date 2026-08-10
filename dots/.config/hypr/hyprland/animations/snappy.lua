-- Quick and decisive: short travel, hard deceleration, nothing lingers.
hl.curve("snappyDecel", {
    type = "bezier",
    points = {{0.16, 1}, {0.3, 1}}
})
hl.curve("snappyAccel", {
    type = "bezier",
    points = {{0.4, 0}, {1, 1}}
})

-- windows
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 1.8,
    bezier = "snappyDecel",
    style = "popin 90%"
})
hl.animation({
    leaf = "fadeIn",
    enabled = true,
    speed = 1.8,
    bezier = "snappyDecel"
})
hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 1.4,
    bezier = "snappyAccel",
    style = "popin 95%"
})
hl.animation({
    leaf = "fadeOut",
    enabled = true,
    speed = 1.4,
    bezier = "snappyAccel"
})
hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 2,
    bezier = "snappyDecel",
    style = "slide"
})
hl.animation({
    leaf = "border",
    enabled = true,
    speed = 6,
    bezier = "snappyDecel"
})

-- layers
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 1.6,
    bezier = "snappyDecel",
    style = "popin 95%"
})
hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 1.4,
    bezier = "snappyAccel",
    style = "popin 96%"
})

-- fade
hl.animation({
    leaf = "fadeLayersIn",
    enabled = true,
    speed = 0.5,
    bezier = "snappyDecel"
})
hl.animation({
    leaf = "fadeLayersOut",
    enabled = true,
    speed = 1.4,
    bezier = "snappyAccel"
})

-- workspaces
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 3.5,
    bezier = "snappyDecel",
    style = "slide"
})

-- specialWorkspace
hl.animation({
    leaf = "specialWorkspaceIn",
    enabled = true,
    speed = 1.8,
    bezier = "snappyDecel",
    style = "slidevert"
})
hl.animation({
    leaf = "specialWorkspaceOut",
    enabled = true,
    speed = 1.2,
    bezier = "snappyAccel",
    style = "slidevert"
})

-- zoom
hl.animation({
    leaf = "zoomFactor",
    enabled = true,
    speed = 2,
    bezier = "snappyDecel"
})
