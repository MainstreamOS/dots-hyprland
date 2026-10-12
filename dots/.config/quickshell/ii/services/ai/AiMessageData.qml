import QtQuick;

/**
 * Represents a message in an AI conversation. (Kind of) follows the OpenAI API message structure.
 * Only the Ai service writes these fields, except setThinkCollapsed() (think block UI)
 * and Ai.updateMessageContent() (editing).
 */
QtObject {
    property string id
    property string role
    // What the UI renders, think tags and activity marker lines included
    property string content
    property string rawContent
    // Bumped on every change of content that is not an append
    property int contentRevision: 0
    property string fileMimeType
    property string fileUri
    property string localFilePath
    property string model
    property bool thinking: true
    property bool done: false
    property var annotations: []
    property var annotationSources: []
    property list<string> searchQueries: []
    property string functionName
    property var functionCall
    property var functionArgs
    // Gemini 3 signs the reasoning behind a call and refuses the next turn if
    // the call is replayed without that signature.
    property string functionThoughtSignature
    property string functionCallId
    property string functionResponse
    property bool functionPending: false
    property bool visibleToUser: true
    // False for notices that are never written to session files
    property bool persist: true
    // ActivityRecord[], append-only; marker lines in content index into it
    property var activities: []
    // ThinkBlockState[] ({start, duration, collapsed}), by think block ordinal
    property var thinkBlocks: []

    // Copies the current array so a concurrent flush of start and duration
    // values is never lost. The caller saves with Ai.scheduleSave().
    function setThinkCollapsed(index: int, collapsed: bool): void {
        if (index < 0)
            return;
        const next = (thinkBlocks ?? []).slice();
        while (next.length <= index)
            next.push({ start: 0, duration: 0, collapsed: null });
        next[index] = Object.assign({}, next[index], { collapsed: collapsed });
        thinkBlocks = next;
    }
}
