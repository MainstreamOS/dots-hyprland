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

// A desktop deletion keeps a per-thread cutoff, so reconnects cannot refill it
// from the phone's older history. Messages after the cutoff remain available.
function isDeleted(state, device, message) {
    const before = Number(state?.[device]?.[message?.thread]);
    return before > 0 && Number(message?.date ?? message?.time ?? 0) <= before;
}

function deleteBefore(state, device, threads, before) {
    if (!device || !Number.isSafeInteger(before) || before <= 0) return state;
    const updated = Object.assign({}, state?.[device]);
    for (const thread of threads ?? []) {
        if (Number.isSafeInteger(Number(thread)) && Number(thread) >= 0)
            updated[thread] = Math.max(Number(updated[thread]) || 0, before);
    }
    return Object.assign({}, state, {[device]: updated});
}

function keptMessages(items, state, device) {
    return (items ?? []).filter(item => !isDeleted(state, device, item));
}

function purgeSaved(saved, device, threads, before) {
    const deleted = deleteBefore(saved?._deletedConversations, device, threads, before);
    const remaining = keptMessages(saved?.[device], deleted, device);
    const outgoing = (saved?._outgoingAttachments ?? []).filter(item =>
        item.device !== device || !isDeleted(deleted, device, item));
    return Object.assign({}, saved, {
        _deletedConversations: deleted,
        [device]: remaining,
        _outgoingAttachments: outgoing
    });
}
