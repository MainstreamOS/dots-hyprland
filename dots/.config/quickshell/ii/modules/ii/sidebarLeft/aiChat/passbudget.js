.pragma library

// Deferred rendering work (text chunks, code slices) shares one budget per run
// of back-to-back work, so several blocks catching up in the same event loop
// pass never add up to a long stall. Work that finds the budget spent waits
// for a later pass.

const BUDGET_MS = 8;
// Work that starts within this long of the previous piece's end is taken to
// belong to the same pass.
const SAME_PASS_MS = 2;

let runStart = 0;
let lastEnd = -1e9;

// Milliseconds still available to work starting now.
function remaining() {
    const now = Date.now();
    if (now - lastEnd > SAME_PASS_MS) runStart = now;
    return BUDGET_MS - (now - runStart);
}

function done() {
    lastEnd = Date.now();
}
