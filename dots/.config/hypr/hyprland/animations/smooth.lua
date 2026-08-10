-- Long, even glides: symmetric ease in and out, longer travel, slides over pops.
hl.curve("smoothFlow", {
    type = "bezier",
    points = {{0.65, 0}, {0.35, 1}}
})
hl.curve("smoothSettle", {
    type = "bezier",
    points = {{0.23, 1}, {0.32, 1}}
})

-- windows
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 4.5,
    bezier = "smoothSettle",
    style = "slide"
})
hl.animation({
    leaf = "fadeIn",
    enabled = true,
    speed = 4.5,
    bezier = "smoothFlow"
})
hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 3.5,
    bezier = "smoothFlow",
    style = "slide"
})
hl.animation({
    leaf = "fadeOut",
    enabled = true,
    speed = 3.5,
    bezier = "smoothFlow"
})
hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 4.5,
    bezier = "smoothFlow",
    style = "slide"
})
hl.animation({
    leaf = "border",
    enabled = true,
    speed = 12,
    bezier = "smoothFlow"
})

-- layers
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 4,
    bezier = "smoothSettle",
    style = "slide"
})
hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 3.5,
    bezier = "smoothFlow",
    style = "slide"
})

-- fade
hl.animation({
    leaf = "fadeLayersIn",
    enabled = true,
    speed = 2,
    bezier = "smoothFlow"
})
hl.animation({
    leaf = "fadeLayersOut",
    enabled = true,
    speed = 3,
    bezier = "smoothFlow"
})

-- workspaces
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 9,
    bezier = "smoothFlow",
    style = "slidefade 15%"
})

-- specialWorkspace
hl.animation({
    leaf = "specialWorkspaceIn",
    enabled = true,
    speed = 4,
    bezier = "smoothSettle",
    style = "slidevert"
})
hl.animation({
    leaf = "specialWorkspaceOut",
    enabled = true,
    speed = 3,
    bezier = "smoothFlow",
    style = "slidevert"
})

-- zoom
hl.animation({
    leaf = "zoomFactor",
    enabled = true,
    speed = 4.5,
    bezier = "smoothFlow"
})
