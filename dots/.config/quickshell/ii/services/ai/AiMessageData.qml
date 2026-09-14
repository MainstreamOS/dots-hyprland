import QtQuick;

/**
 * Represents a message in an AI conversation. (Kind of) follows the OpenAI API message structure.
 */
QtObject {
    property string role
    property string content
    property string rawContent
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
    property string functionResponse
    property bool functionPending: false
    property bool visibleToUser: true
}
