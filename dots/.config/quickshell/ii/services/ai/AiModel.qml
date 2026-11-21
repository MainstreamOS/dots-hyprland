import QtQuick;

/**
 * An AI model representation.
 * - name: Friendly name of the model
 * - icon: Icon name of the model
 * - description: Description of the model
 * - endpoint: Endpoint of the model
 * - model: Model code (like gpt-4.1 or gemini-2.5-flash)
 * - requires_key: Whether the model requires an API key
 * - key_id: The identifier of the API key. Use the same identifier for models that can be accessed with the same key.
 * - key_get_link: Link to get an API key
 * - key_get_description: Description of pricing and how to get an API key
 * - api_format: The API format of the model. Can be "openai" or "gemini". Default is "openai".
 * - extraParams: Extra parameters to be passed to the model. This is a JSON object.
 * - sendTemperature: Whether to send temperature sampling parameter (deprecated on Gemini 3)
 * - thinkingLevel: Default thinking/reasoning level ("minimal", "low", "medium", "high", etc.)
 * - supportsSessions: Whether the model supports saving and loading chat sessions
 * - thinkingProfile: Named thinking profile from models.json (e.g. "gemini-xhigh")
 * - descProfile: Thinking-level description family ("gemini", "claude", "openai", "generic")
 * - thinkingLevels: Explicit ordered list of UI thinking level IDs (or null to use fallback heuristics)
 * - effortMap: Explicit map of UI thinking level ID -> provider wire effort string (or null)
 * - defaultEffort: Default wire effort string when thinkingLevel is Auto/empty (e.g. Antigravity CLI)
 * - capabilities: Provider-specific model capability flags (searchRequiresBilling, quotaSwitchTip, thinkingMode, maxTokens, ...)
 * - isSetupEntry: True for CLI plan sign-in/setup placeholder entries
 */

QtObject {
    property string name
    property string icon
    property string description
    property string homepage
    property string endpoint
    property string model
    property bool requires_key: true
    property string key_id
    property string key_get_link
    property string key_get_description
    property string api_format: "openai"
    property var tools
    property var extraParams: ({})
    property bool sendTemperature: true
    property string thinkingLevel: ""
    property bool supportsSessions: true
    property string thinkingProfile: ""
    property string descProfile: ""
    property var thinkingLevels: null
    property var effortMap: null
    property string defaultEffort: ""
    property var capabilities: ({})
    property bool isSetupEntry: false
}
