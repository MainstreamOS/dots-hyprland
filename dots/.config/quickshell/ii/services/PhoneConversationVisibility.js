.pragma library

// Local visibility only: the stock phone protocol does not send archive status.
// Keep IDs scoped to their phone, separately from the histories and refresh list.
function isHidden(state, device, thread) {
    const ids = state?.[device];
    return Array.isArray(ids) && ids.some(id => String(id) === String(thread));
}

function setHidden(state, device, thread, hidden) {
    if (!device || thread === null || thread === undefined || thread === ""
        || !Number.isSafeInteger(Number(thread)) || Number(thread) < 0)
        return state;
    if (isHidden(state, device, thread) === hidden) return state;
    const ids = Array.isArray(state?.[device]) ? state[device] : [];
    const updated = Object.assign({}, state);
    const remaining = ids.filter(id => String(id) !== String(thread));
    if (hidden) remaining.push(Number(thread));
    if (remaining.length) updated[device] = remaining;
    else delete updated[device];
    return updated;
}

function conversations(items, state, device, hidden) {
    return (items ?? []).filter(item => item && isHidden(state, device, item.thread) === hidden);
}

// Refreshes and cached history must not resurrect an entry. Only a new incoming
// message identified as live by the bridge brings it back to the inbox.
function afterMessage(state, event) {
    if (event.live !== true || event.message?.type !== 1) return state;
    return setHidden(state, event.device, event.message.thread, false);
}
