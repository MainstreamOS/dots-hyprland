.pragma library

// How fast the network is moving and what it is connected through, apart
// from the singleton so the counting can be run against made-up readings in
// a test.

// Readings averaged into one rate. Two one-second readings steady a number
// that would otherwise jump with every burst, and it still falls to nothing
// two seconds after traffic stops.
var windowReadings = 2;

// A gap this much longer than a tick means the machine slept: timers stop
// while it does, but the clock does not, and averaging over the gap would
// report a speed nobody saw.
var maxGapSeconds = 3;

// Two reads this close together came from one moment: the read the file
// makes when it is created, and the timer's first a few milliseconds later.
// A burst divided by almost no time would show as a spike, so the later one
// is dropped.
var minGapSeconds = 0.5;

function lines(text) {
    return String(text ?? "").split("\n").filter(line => line.trim() !== "");
}

// Every interface's received and sent byte totals in /proc/net/dev, by name.
// The two header lines carry no colon, and an interface name cannot hold one.
function parseCounters(text) {
    const counters = {};
    for (const line of lines(text)) {
        const colon = line.indexOf(":");
        if (colon < 0)
            continue;
        const name = line.slice(0, colon).trim();
        const fields = line.slice(colon + 1).trim().split(/\s+/);
        const rx = Number(fields[0]);
        const tx = Number(fields[8]);
        if (name === "" || !Number.isFinite(rx) || !Number.isFinite(tx))
            continue;
        counters[name] = { rx: rx, tx: tx };
    }
    return counters;
}

// Only interfaces with hardware behind them are counted. A VPN tunnel's
// traffic also crosses the card beneath it, whatever the tunnel is named, so
// counting both shows every byte twice; loopback, bridges and container links
// never leave the machine. Until the hardware list is known nothing counts.
// A machine where nothing reports hardware counts all but loopback, so the
// widget does not sit at zero. Traffic passed from one card to another, as
// when this machine shares its connection as a hotspot, shows as both a
// download and an upload, since each card really did move it.
function countedInterfaces(counters, physical) {
    if (!physical)
        return [];
    const present = Object.keys(counters);
    if (physical.length === 0)
        return present.filter(name => name !== "lo");
    return present.filter(name => physical.indexOf(name) !== -1);
}

// Bytes moved between two readings over the counted interfaces. Only one
// present both times adds anything, so a new interface starts from its next
// reading rather than from everything it moved before. A counter that went
// backwards (a 32-bit counter wrapped, or the interface was made again) adds
// nothing for that reading instead of a spike.
function bytesMoved(before, after, counted) {
    let rx = 0;
    let tx = 0;
    for (const name of counted) {
        const was = before[name];
        const now = after[name];
        if (!was || !now)
            continue;
        rx += Math.max(0, now.rx - was.rx);
        tx += Math.max(0, now.tx - was.tx);
    }
    return { rx: rx, tx: tx };
}

// Folds one reading into the state the last call returned, or into nothing
// to start over, and returns the new state with the rates in bytes per
// second. The first reading only sets the baseline.
function advance(state, counters, nowMs, counted) {
    const next = { counters: counters, time: nowMs, window: [], download: 0, upload: 0 };
    if (!state)
        return next;
    const seconds = (nowMs - state.time) / 1000;
    if (seconds <= 0 || seconds > maxGapSeconds)
        return next;
    if (seconds < minGapSeconds)
        return state;
    const moved = bytesMoved(state.counters, counters, counted);
    next.window = state.window.concat([{ rx: moved.rx, tx: moved.tx, seconds: seconds }]).slice(-windowReadings);
    const span = next.window.reduce((sum, r) => sum + r.seconds, 0);
    next.download = next.window.reduce((sum, r) => sum + r.rx, 0) / span;
    next.upload = next.window.reduce((sum, r) => sum + r.tx, 0) / span;
    return next;
}

// Binary steps under the KB/MB/GB labels, the way the rest of the shell
// reports sizes, and never more than three figures, so the widest reading
// is known ahead and the bar can keep a slot that wide.
function scaled(bytesPerSecond) {
    let value = Math.max(0, Number(bytesPerSecond) || 0);
    let step = 0;
    while (value >= 999.5 && step < 4) {
        value /= 1024;
        step++;
    }
    const figures = step > 0 && value < 9.95 ? value.toFixed(1) : Math.round(value).toString();
    return { figures: figures, step: step };
}

// "3.8 KB/s". The widest it gets is "888 MB/s".
function formatRate(bytesPerSecond) {
    const s = scaled(bytesPerSecond);
    return s.figures + " " + ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"][s.step];
}

// "3.8K", for the vertical bar, which has room for about four characters.
function formatRateShort(bytesPerSecond) {
    const s = scaled(bytesPerSecond);
    return s.figures + ["B", "K", "M", "G", "T"][s.step];
}

function parseJson(text) {
    try {
        const value = JSON.parse(String(text ?? "").trim());
        return Array.isArray(value) ? value : [];
    } catch (e) {
        return [];
    }
}

// nmcli's terse output escapes a colon inside a value as "\:", so only the
// first two bare colons split DEVICE:TYPE:NAME and the name keeps the rest.
function parseConnections(text) {
    const unescape = value => value.replace(/\\(.)/g, "$1");
    return lines(text).map(line => {
        const fields = line.match(/^((?:[^:\\]|\\.)*):((?:[^:\\]|\\.)*):(.*)$/);
        return fields ? { device: unescape(fields[1]), type: unescape(fields[2]), name: unescape(fields[3]) } : null;
    }).filter(c => c);
}

// The in-use row of `nmcli -t -f IN-USE,SIGNAL device wifi list`, or -1.
function parseSignal(text) {
    const row = lines(text).find(line => line.startsWith("*:"));
    const signal = row ? parseInt(row.slice(2)) : NaN;
    return Number.isFinite(signal) ? signal : -1;
}

// NetworkManager's names for links that carry traffic for another one: a
// tunnel, or a dummy that holds a route only to keep traffic off the real
// link. Their address is not the one the local network knows this machine by.
var tunnelTypes = ["wireguard", "tun", "ip-tunnel", "dummy", "loopback"];

// What the hover card says about the connection, from one run of `ip` and
// `nmcli` whose five answers are split by lines of "---": the IPv4 and IPv6
// default routes, the global addresses, the active connections and the
// Wi-Fi list. The hardware link with the lowest-metric default route is the
// one in use, asked of IPv4 first and of IPv6 for a network without it. A
// VPN is routed above that link by rule, so the tunnel is passed over. When
// no hardware link holds the route, the link that does is used unless it is
// a tunnel: a bridge for virtual machines, a bond or a PPPoE dial-up carries
// the machine's traffic in place of the card beneath it.
function readDetails(output, physical) {
    const sections = String(output ?? "").split(/^---$/m);
    const byMetric = (a, b) => (a.metric ?? 0) - (b.metric ?? 0);
    const routes = parseJson(sections[0]).sort(byMetric)
        .concat(parseJson(sections[1]).sort(byMetric))
        .filter(r => r.dev);
    const links = parseJson(sections[2]);
    const connections = parseConnections(sections[3]);
    const hardware = name => !physical || physical.length === 0 || physical.indexOf(name) !== -1;
    // A VPN plugin's connection is listed on the card it runs over, beside
    // the card's own, and only the card's names the link.
    const connectionOf = dev => connections.find(c => c.device === dev && c.type !== "vpn");
    const tunnel = dev => {
        const linkType = links.find(l => l.ifname === dev)?.link_type;
        return linkType === "none" || linkType === "loopback"
            || tunnelTypes.indexOf(connectionOf(dev)?.type) !== -1;
    };
    // IPv4 where the link has it, otherwise a lasting IPv6 address rather
    // than one of the short-lived private ones.
    const addressOf = dev => {
        const info = (links.find(l => l.ifname === dev)?.addr_info ?? []).filter(a => a.local);
        return (info.find(a => a.family === "inet")
            ?? info.find(a => a.family === "inet6" && !a.temporary && !a.deprecated)
            ?? info[0])?.local ?? "";
    };
    const route = routes.find(r => hardware(r.dev)) ?? routes.find(r => !tunnel(r.dev));
    // A network with no way out (no gateway) still has a link worth naming.
    const device = route?.dev
        ?? links.find(l => hardware(l.ifname) && addressOf(l.ifname) !== "")?.ifname
        ?? "";
    const connection = device !== "" ? connectionOf(device) : undefined;
    const wifi = connection?.type === "802-11-wireless";
    return {
        device: device,
        name: connection?.name ?? device,
        address: route?.prefsrc ?? addressOf(device),
        wifi: wifi,
        signal: wifi ? parseSignal(sections[4]) : -1
    };
}
