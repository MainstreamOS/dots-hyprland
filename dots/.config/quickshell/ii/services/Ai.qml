pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common.functions as CF
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.services.ai
import "ai/sink.js" as Sink
import "ai/sessions.js" as Sessions

/**
 * Basic service to handle LLM chats. Supports Google's and OpenAI's API formats.
 * Supports Gemini and OpenAI models.
 * Limitations:
 * - For now functions only work with Gemini API format
 */
Singleton {
    id: root

    property Component aiMessageComponent: AiMessageData {}
    property Component aiModelComponent: AiModel {}
    property Component geminiApiStrategy: GeminiApiStrategy {}
    property Component openaiApiStrategy: OpenAiApiStrategy {}
    property Component mistralApiStrategy: MistralApiStrategy {}
    property Component anthropicApiStrategy: AnthropicApiStrategy {}
    property Component claudeCodeApiStrategy: ClaudeCodeApiStrategy {}
    property Component codexCliApiStrategy: CodexCliApiStrategy {}
    property Component antigravityCliApiStrategy: AntigravityCliApiStrategy {}
    readonly property string interfaceRole: "interface"
    readonly property string apiKeyEnvVarName: "API_KEY"

    signal responseFinished()

    property string systemPrompt: {
        let prompt = Config.options?.ai?.systemPrompt ?? "";
        for (let key in root.promptSubstitutions) {
            // prompt = prompt.replaceAll(key, root.promptSubstitutions[key]);
            // QML/JS doesn't support replaceAll, so use split/join
            prompt = prompt.split(key).join(root.promptSubstitutions[key]);
        }
        if (AiModes.current === "plan") {
            prompt += "\n\n## Mode: Plan\nYou are currently in Plan Mode. Focus on designing, architecting, and outlining a structured step-by-step plan. Do not execute destructive edits or commands without user confirmation.";
        }
        return prompt;
    }
    // Reassigned on every change. A message object is in messageByID before
    // its id joins messageIDs, and leaves messageIDs before it is destroyed.
    property var messageIDs: []
    property var messageByID: ({})
    onMessageIDsChanged: {
        if (root._graveyard.length > 0) reaper.restart();
    }
    // True while a saved session is being read and rebuilt; sends, edits and
    // saves wait for it.
    property bool sessionLoading: false
    property bool _startupRestored: false
    property int _loadGeneration: 0
    property var _restore: null
    // What the chat looked like when it last matched a named session
    property string _savedSignature: ""
    property string _savedName: ""
    readonly property var apiKeys: KeyringStorage.keyringData?.apiKeys ?? {}
    readonly property var apiKeysLoaded: KeyringStorage.loaded
    readonly property bool currentModelHasApiKey: {
        const model = models[currentModelId];
        if (!model || !model.requires_key) return true;
        if (!apiKeysLoaded) return false;
        const key = apiKeys[model.key_id];
        return (key?.length > 0);
    }
    property real temperature: Persistent.states?.ai?.temperature ?? 0.5
    property string thinkingLevel: Persistent.states?.ai?.thinkingLevel ?? ""
    readonly property var thinkingLevels: [
        "minimal", "low", "medium", "high", "extra", "max", "ultracode", "none"
    ]
    property QtObject tokenCount: QtObject {
        property int input: -1
        property int output: -1
        property int total: -1
    }
    // "idle", "starting", "streaming", "awaitingConfirmation" or "stopping"
    property string requestState: "idle"
    readonly property bool isGenerating: root.requestState === "starting"
        || root.requestState === "streaming" || root.requestState === "stopping"
    // null or a frozen Confirmation; replaced, never mutated
    property var pendingConfirmation: null

    function idForMessage(message) {
        // Generate a unique ID using timestamp and random value
        return Date.now().toString(36) + Math.random().toString(36).substr(2, 8);
    }

    function safeModelName(modelName) {
        return modelName.replace(/:/g, "_").replace(/ /g, "-").replace(/\//g, "-")
    }

    property list<var> defaultPrompts: []
    property list<var> userPrompts: []
    property list<var> promptFiles: [...defaultPrompts, ...userPrompts]
    property list<string> savedChats: []

    property var promptSubstitutions: {
        "{DISTRO}": SystemInfo.distroName,
        "{DATETIME}": `${DateTime.time}, ${DateTime.collapsedCalendarFormat}`,
        "{WINDOWCLASS}": ToplevelManager.activeToplevel?.appId ?? "Unknown",
        "{DE}": `${SystemInfo.desktopEnvironment} (${SystemInfo.windowingSystem})` 
    }

    // Gemini: https://ai.google.dev/gemini-api/docs/function-calling
    // OpenAI: https://platform.openai.com/docs/guides/function-calling
    property string currentTool: Config?.options.ai.tool ?? "search"
    property var tools: {
        "gemini": {
            "functions": [{"functionDeclarations": [
                {
                    "name": "switch_to_search_mode",
                    "description": "Search the web",
                },
                {
                    "name": "get_shell_config",
                    "description": "Get the desktop shell config file contents",
                },
                {
                    "name": "set_shell_config",
                    "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "key": {
                                "type": "string",
                                "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                            },
                            "value": {
                                "type": "string",
                                "description": "The value to set, e.g. `true`"
                            }
                        },
                        "required": ["key", "value"]
                    }
                },
                {
                    "name": "run_shell_command",
                    "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "command": {
                                "type": "string",
                                "description": "The bash command to run",
                            },
                        },
                        "required": ["command"]
                    }
                },
            ]}],
            "search": [{
                "google_search": {}
            }],
            "none": []
        },
        "openai": {
            "functions": [
                {
                    "type": "function",
                    "function": {
                        "name": "get_shell_config",
                        "description": "Get the desktop shell config file contents",
                        "parameters": {}
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "set_shell_config",
                        "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "key": {
                                    "type": "string",
                                    "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                                },
                                "value": {
                                    "type": "string",
                                    "description": "The value to set, e.g. `true`"
                                }
                            },
                            "required": ["key", "value"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "run_shell_command",
                        "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "command": {
                                    "type": "string",
                                    "description": "The bash command to run",
                                },
                            },
                            "required": ["command"]
                        }
                    },
                },
            ],
            "search": [],
            "none": [],
        },
        "mistral": {
            "functions": [
                {
                    "type": "function",
                    "function": {
                        "name": "get_shell_config",
                        "description": "Get the desktop shell config file contents",
                        "parameters": {}
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "set_shell_config",
                        "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "key": {
                                    "type": "string",
                                    "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                                },
                                "value": {
                                    "type": "string",
                                    "description": "The value to set, e.g. `true`"
                                }
                            },
                            "required": ["key", "value"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "run_shell_command",
                        "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "command": {
                                    "type": "string",
                                    "description": "The bash command to run",
                                },
                            },
                            "required": ["command"]
                        }
                    },
                },
            ],
            "search": [],
            "none": [],
        },
        "anthropic": {
            "functions": [],
            "search": [],
            "none": []
        }
    }
    // A saved local model does not exist until the Ollama query answers, so at
    // startup this looks up a format that is not there yet and Object.keys
    // refuses undefined. The tools reappear when the model registers.
    // Function calling is also hidden from strategies that cannot read a call
    // back out of the reply, so it cannot be picked for a model it would mute.
    property list<var> availableTools: Object.keys(root.tools[models[currentModelId]?.api_format] ?? {})
        .filter(tool => tool !== "functions" || (root.currentApiStrategy?.supportsFunctions ?? false))

    // The tool preference is global, but a model that cannot report a function
    // call must not be handed the definitions: it answers with a call instead
    // of prose and the reply arrives empty. Fall back rather than go silent.
    readonly property string effectiveTool: (root.currentTool === "functions" && !(root.currentApiStrategy?.supportsFunctions ?? false)) ? "none" : (root.currentTool ?? "search")
    property var toolDescriptions: {
        "functions": Translation.tr("Commands, edit configs, search.\nTakes an extra turn to switch to search mode if that's needed"),
        "search": Translation.tr("Gives the model search capabilities (immediately)"),
        "none": Translation.tr("Disable tools")
    }

    // Model properties:
    // - name: Name of the model
    // - icon: Icon name of the model
    // - description: Description of the model
    // - endpoint: Endpoint of the model
    // - model: Model name of the model
    // - requires_key: Whether the model requires an API key
    // - key_id: The identifier of the API key. Use the same identifier for models that can be accessed with the same key.
    // - key_get_link: Link to get an API key
    // - key_get_description: Description of pricing and how to get an API key
    // - api_format: The API format of the model. Can be "openai" or "gemini". Default is "openai".
    // - extraParams: Extra parameters to be passed to the model. This is a JSON object.
    readonly property var geminiApiCatalog: ({
        "gemini-flash-latest": {
            "name": "Gemini Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nGoogle's current Flash model: fast and capable, with a free tier."),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:streamGenerateContent",
            "model": "gemini-flash-latest",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free tier, with data used for training. Web search needs billing turned on.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            "api_format": "gemini",
            "sendTemperature": false,
            "thinkingLevel": "",
        },
        "gemini-pro-latest": {
            "name": "Gemini Pro",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nGoogle's flagship Pro reasoning model: complex coding, mathematics, and research."),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro-latest:streamGenerateContent",
            "model": "gemini-pro-latest",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free tier and pay-as-you-go.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project, go to Get API key"),
            "api_format": "gemini",
            "sendTemperature": false,
            "thinkingLevel": "",
        }
    })
    function isGeminiApiModel(id) {
        return root.geminiApiCatalog[id] !== undefined;
    }

    // Every model the service knows of, online or not. Only the functions
    // that register or retire models write it; everything else reads models.
    property var _registry: ({
        "gemini": aiModelComponent.createObject(root, {
            "name": "Gemini",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nGoogle's Gemini models with a free tier: Gemini Flash and Gemini Pro."),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:streamGenerateContent",
            "model": "gemini-flash-latest",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free tier, with data used for training. Web search needs billing turned on.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            "api_format": "gemini",
            "sendTemperature": false,
            "thinkingLevel": "",
        }),
        "mistral-4": aiModelComponent.createObject(root, {
            "name": "Mistral 4",
            "icon": "mistral-symbolic",
            "description": Translation.tr("Online | %1's 1T parameter flagship. Strong at coding, agentic workflows, and structured tool use. Disadvantages: higher initial latency and tends to be verbose").arg("Mistral"),
            "homepage": "https://mistral.ai/news/mistral-large-4",
            "endpoint": "https://api.mistral.ai/v1/chat/completions",
            "model": "mistral-large-latest",
            "requires_key": true,
            "key_id": "mistral",
            "key_get_link": "https://console.mistral.ai/api-keys",
            "key_get_description": Translation.tr("**Instructions**: Log into Mistral account, go to Keys on the sidebar, click Create new key"),
            "api_format": "mistral",
        }),
        "claude": aiModelComponent.createObject(root, {
            "name": "Claude",
            "icon": "claude-symbolic",
            "description": Translation.tr("Online | Anthropic's Claude Opus 5.5 over the Messages API"),
            "homepage": "https://www.anthropic.com/claude",
            "endpoint": "https://api.anthropic.com/v1/messages",
            "model": "claude-opus-5-5",
            "requires_key": true,
            "key_id": "anthropic",
            "key_get_link": "https://console.anthropic.com/settings/keys",
            "key_get_description": Translation.tr("**Instructions**: Log into your Anthropic account, go to API Keys, click Create Key"),
            "api_format": "anthropic",
            "sendTemperature": false,
            "thinkingLevel": "",
        }),
        "codex": aiModelComponent.createObject(root, {
            "name": "Codex",
            "icon": "openai-symbolic",
            "description": Translation.tr("Online | OpenAI's GPT-5.6 over the Chat Completions API"),
            "homepage": "https://platform.openai.com",
            "endpoint": "https://api.openai.com/v1/chat/completions",
            "model": "gpt-5.6",
            "sendTemperature": false,
            "requires_key": true,
            "key_id": "openai",
            "key_get_link": "https://platform.openai.com/api-keys",
            "key_get_description": Translation.tr("**Instructions**: Log into your OpenAI account, open the API keys page, click Create new secret key"),
            "api_format": "openai",
        }),
    })
    // What the picker offers and requests may use: the local-only policy
    // hides online entries rather than dropping them, so they are back as
    // soon as the policy allows them again.
    readonly property var models: Config.options?.policies?.ai === 2 ? root._localModels(root._registry) : root._registry
    function _isLocalModel(model) {
        return String(model?.endpoint ?? "").includes("localhost");
    }
    function _localModels(map) {
        const local = {};
        for (const id of Object.keys(map)) {
            if (root._isLocalModel(map[id])) local[id] = map[id];
        }
        return local;
    }
    // Judged by id so it also covers a plan model or a Gemini catalog entry
    // that is not registered right now. An id nothing knows yet is a saved
    // local model whose fetch has not answered.
    function _isOnlineModelId(id) {
        if (!id || id === root.ollamaSetupModelId) return false;
        const model = root._registry[id] ?? (root.isGeminiApiModel(id) ? root.geminiApiCatalog[id] : null);
        if (model) return !root._isLocalModel(model);
        return root.planFormatFor(id) !== "";
    }
    // Only ever a view of the map. Readonly so no fetch handler can hand it
    // a snapshot that stops following the models registered afterwards.
    readonly property var modelList: Object.keys(root.models)
    readonly property var retiredModels: ({
        "claude-opus-4-8": "claude",
        "mistral-medium-3": "mistral-4",
        "mistral-3": "mistral-4",
        "mistral-medium": "mistral-4",
        "mistral": "mistral-4",
        "gemini-3-flash": "gemini-flash-latest",
        "gemini-2.5-flash": "gemini-flash-latest",
        "gemini-3.5-flash-lite": "gemini-flash-latest",
        "gemini-3.8-flash": "gemini-flash-latest",
        "gemini": "gemini-flash-latest",
        "gemini-flash": "gemini-flash-latest",
        "gemini-pro": "gemini-pro-latest",
        "gemini-3.1-pro": "gemini-pro-latest",
        "gemini-3.1-pro-preview": "gemini-pro-latest",
        "gemini-plan-default": "gemini-plan-3-8-flash",
        "gemini-plan-3-8-flash-high": "gemini-plan-3-8-flash",
        "gemini-plan-3-8-flash-medium": "gemini-plan-3-8-flash",
        "gemini-plan-3-8-flash-low": "gemini-plan-3-8-flash",
        "gemini-plan-3-1-pro-high": "gemini-plan-3-1-pro",
        "gemini-plan-3-1-pro-low": "gemini-plan-3-1-pro",
    })
    // The user's choice as saved in Persistent. Everything that talks to a
    // model reads currentModelId instead.
    readonly property var _savedModelId: {
        const id = Persistent.states?.ai?.model || modelList[0];
        return retiredModels[id] ?? id;
    }
    // Under the local-only policy an online choice stays saved for when the
    // policy allows it again, and the first local model answers in its place.
    // The two inputs are typed bindings of their own: the selection handler
    // rewrites the map's online entries, and a binding reading the map
    // directly would be re-entered by that write and abandoned as a loop.
    readonly property bool _savedIsOnline: root._isOnlineModelId(root._savedModelId)
    readonly property string _localFallbackId: Object.keys(root._registry).find(id => id !== root.ollamaSetupModelId
        && root.retiredModels[id] === undefined && root._isLocalModel(root._registry[id])) ?? root.ollamaSetupModelId
    readonly property var currentModelId: Config.options?.policies?.ai === 2 && root._savedIsOnline
        ? root._localFallbackId
        : root._savedModelId
    // Read by the input-box indicator. A plain getModel() call there never
    // re-evaluated, so the name sat on whatever was current when the chat was
    // built. Ollama's list arrives after that, so a saved local model showed as
    // something else entirely until the next interaction.
    // No fallback to the first map entry: before the local model fetch
    // answers, the saved model has no object yet, and the first key is an
    // online model, so the picker chip claimed Gemini was selected on every
    // start whose real model is local. Null here renders as local AI still
    // being looked up, which is the truth of that moment. Readonly: every
    // selection writes Persistent, and both id and object derive from it, so
    // no imperative write can strand the id and the object apart again.
    readonly property var currentModel: models[currentModelId] ?? (root.isGeminiApiModel(currentModelId) ? models["gemini"] : null)
    readonly property bool currentModelSupportsSessions: Boolean(currentModel && currentModel.supportsSessions !== false && currentModelId !== ollamaSetupModelId)

    property var apiStrategies: {
        "openai": openaiApiStrategy.createObject(root),
        "gemini": geminiApiStrategy.createObject(root),
        "mistral": mistralApiStrategy.createObject(root),
        "anthropic": anthropicApiStrategy.createObject(root),
        "claude-code": claudeCodeApiStrategy.createObject(root),
        "codex-cli": codexCliApiStrategy.createObject(root),
        "antigravity-cli": antigravityCliApiStrategy.createObject(root),
    }
    property ApiStrategy currentApiStrategy: apiStrategies[models[currentModelId]?.api_format || "openai"]
    readonly property bool currentModelSupportsAttachments: Boolean(root.currentApiStrategy?.supportsAttachments)

    function addUserModels() {
        (Config?.options.ai?.extraModels ?? []).forEach(model => {
            const safeModelName = root.safeModelName(model["model"]);
            root.addModel(safeModelName, model)
        });
    }

    // ── Subscription plans behind local CLIs ──────────────────────
    // Sits beside the key-backed entries rather than replacing them: a
    // subscriber signs in once and spends nothing per token, while anyone
    // with a key keeps the HTTP path that needs no CLI installed. A plan's
    // models only join the picker while its CLI reports a live login;
    // before that a single setup entry holds the seat and the sidebar banner
    // walks through install and sign-in. Everything here is keyed by
    // api_format, so another provider's CLI is a set of table rows rather
    // than another copy of the machinery.
    readonly property var cliSetup: ({
        "claude-code": {
            "name": "Claude Code",
            "cmd": "claude",
            "install": "curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors https://claude.ai/install.sh | bash",
            "login": "claude auth login --claudeai",
            "readyCheck": "claude auth status --json 2>/dev/null | grep -q '\"loggedIn\": *true'",
            // Print mode leaves thinking text out unless asked for it. Older CLIs
            // refuse the flag before making any request, so empty input tells.
            "features": "claude -p --thinking-display summarized 2>&1 | grep -q 'unknown option' || echo 'feature thinking-display'"
        },
        "codex-cli": {
            "name": "Codex",
            "cmd": "codex",
            "install": "curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors https://chatgpt.com/codex/install.sh | sh",
            // What ai-cli-install is asked for when the download will not
            // come. Arch carries the CLI too, signed and on the update path,
            // and reaching it costs one prompt inside the sidebar rather than
            // a trip to a terminal.
            "installFallback": "codex",
            "login": "codex login",
            "readyCheck": "codex login status >/dev/null 2>&1",
            // The CLI's own model list, read once signed in. The raw catalog
            // runs to hundreds of KB, so only the fields used here reach QML.
            "catalog": "timeout 30 codex debug models 2>/dev/null | python3 -I -c \"$1\"",
            "catalogFilter": "import json, sys\n"
                + "try:\n"
                + "    out = []\n"
                + "    for m in (json.load(sys.stdin).get('models') or [])[:200]:\n"
                + "        if not isinstance(m, dict): continue\n"
                + "        up = m.get('upgrade')\n"
                + "        levels = m.get('supported_reasoning_levels') or []\n"
                + "        out.append({'slug': m.get('slug'), 'name': m.get('display_name'), 'visibility': m.get('visibility'),\n"
                + "            'priority': m.get('priority'), 'default': m.get('default_reasoning_level'),\n"
                + "            'efforts': [l.get('effort') for l in levels if isinstance(l, dict)][:20],\n"
                + "            'upgrade': up.get('model') if isinstance(up, dict) else None})\n"
                + "    print('catalog ' + json.dumps(out, separators=(',', ':')))\n"
                + "except Exception:\n"
                + "    pass\n"
        },
        "antigravity-cli": {
            "name": "Antigravity",
            "cmd": "agy",
            // Google's own installer, run with a throwaway home and config
            // folders: after placing the binary it hands over to `agy
            // install`, which rewrites the shell profiles wherever those point,
            // and those are files Mainstream updates keep in step. The binary
            // still lands in the real ~/.local/bin, and it keeps itself up to
            // date from there.
            "install": "t=$(mktemp -d) && trap 'rm -rf \"$t\"' EXIT && curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors https://antigravity.google/cli/install.sh | HOME=\"$t\" XDG_CONFIG_HOME=\"$t/.config\" ZDOTDIR=\"$t\" bash -s -- --dir \"$HOME/.local/bin\"",
            // A one-line question starts Google's sign-in by itself: the CLI
            // opens the browser, waits a minute for the code Google's page
            // shows, then answers and exits. It only offers that when it has a
            // terminal, so script gives it a hidden one, fed from a pipe the
            // sidebar writes the code into; held open both ways here, the pipe
            // never reads as closed while the CLI waits. It runs in the chat's
            // own folder so the question joins no other history, in a session
            // of its own so a retry can end it whole, and the pid is checked
            // first since it may be reused after a restart. Its exit code is
            // kept so a sign-in that ran out of time says so at once.
            "login": "dir=\"" + root.antigravityDir + "\"; mkdir -p \"$dir\" && cd \"$dir\" || exit 1; p=$(cat login.pid 2>/dev/null); if [ -n \"$p\" ] && [ \"$(ps -o comm= -p \"$p\")\" = bash ] && [ \"$(ps -o sid= -p \"$p\" | tr -d ' ')\" = \"$p\" ]; then kill -- -\"$p\"; fi; rm -f login.exit code.fifo; mkfifo -m 600 code.fifo || exit 1; setsid bash -c 'exec 3<>code.fifo; SHELL=/bin/bash script -qec \"agy --disable-slash-commands --print=\\\"Reply with only these words: You are signed in.\\\"\" /dev/null <&3 > login.log 2>&1; echo $? > login.exit; rm -f code.fifo' > /dev/null 2>&1 < /dev/null & echo $! > login.pid",
            // Where the code Google's page shows goes; see login above.
            "loginCodePipe": root.antigravityDir + "/code.fifo",
            "loginInBackground": true,
            "loginFailedCheck": "f=\"" + root.antigravityDir + "/login.exit\"; [ -s \"$f\" ] && [ \"$(cat \"$f\")\" != 0 ]",
            "loginDoneCheck": "[ -e \"" + root.antigravityDir + "/login.exit\" ]",
            // The full app, for a sign-in the hidden one could not finish: it
            // shows any first-run screens and takes a pasted code.
            "terminalLogin": "dir=\"" + root.antigravityDir + "\"; mkdir -p \"$dir\" && cd \"$dir\" && rm -f login.exit && agy",
            // The login lives in the system keyring, so the CLI is the only
            // reliable judge; listing models fails at once when signed out.
            "readyCheck": "timeout 20 agy models >/dev/null 2>&1"
        }
    })
    // The sign-in's code pipe and exit file and the chat's own runs all live
    // here, so every use has to name this one folder.
    readonly property string antigravityDir: root._stateHome + "/quickshell/ai/antigravity-cli"

    // ── Codex plan models, from the CLI's own catalog ─────────────
    // What the plan offers when the catalog cannot be read.
    readonly property var _codexFallbackCatalog: [
        { slug: "gpt-6.1-sol", name: "GPT-6.1-Sol", efforts: ["low", "medium", "high", "xhigh", "max", "ultra"], defaultEffort: "low" },
        { slug: "gpt-6-astra", name: "GPT-6-Astra", efforts: ["low", "medium", "high", "xhigh", "max", "ultra"], defaultEffort: "low" },
        { slug: "gpt-6-sol", name: "GPT-6-Sol", efforts: ["low", "medium", "high", "xhigh", "max", "ultra"], defaultEffort: "medium" },
        { slug: "gpt-6-luna", name: "GPT-6-Luna", efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "medium" },
    ]
    // The last catalog the CLI answered with: { listed, upgrades }. A read
    // that fails later keeps it.
    property var _codexCatalog: null
    readonly property var _codexListed: root._codexCatalog?.listed ?? root._codexFallbackCatalog
    // Codex effort -> the tab's level id. Efforts the tab has no level for are not offered.
    readonly property var codexEffortLevels: ({
        "none": "none", "minimal": "minimal", "low": "low", "medium": "medium",
        "high": "high", "xhigh": "extra", "max": "max", "ultra": "ultracode",
    })
    // Ids saved before the catalog named the models keep answering.
    readonly property var _codexLegacyIds: ({ "gpt-5.6-terra": "codex-terra", "gpt-5.6-luna": "codex-luna" })
    function codexModelId(slug: string): string {
        return root._codexLegacyIds[slug] ?? ("codex-" + String(slug).toLowerCase().replace(/[^a-z0-9]+/g, "-"));
    }
    readonly property var _codexPlanModels: {
        const out = {};
        for (const entry of root._codexListed) {
            const id = root.codexModelId(entry.slug);
            if (out[id] !== undefined || id === "codex-plan") continue;
            const level = root.codexEffortLevels[entry.defaultEffort] ?? "";
            out[id] = {
                alias: entry.slug,
                name: entry.name,
                thinkingLevel: entry.efforts.includes(entry.defaultEffort) ? level : "",
            };
        }
        return out;
    }
    // The efforts a listed model accepts, or [] when it is not listed.
    function codexEfforts(slug: string): var {
        return root._codexListed.find(entry => entry.slug === slug)?.efforts ?? [];
    }

    // The filtered catalog line from the detector, or null when it holds no
    // listed model.
    function _parseCodexCatalog(text: string): var {
        let raw = null;
        try {
            raw = JSON.parse(text);
        } catch (e) {
            return null;
        }
        if (!Array.isArray(raw)) return null;
        const upgrades = {};
        const listed = [];
        raw.forEach((m, index) => {
            const slug = typeof m?.slug === "string" ? m.slug : "";
            if (!/^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$/.test(slug)) return;
            if (typeof m.upgrade === "string" && m.upgrade.length > 0) upgrades[slug] = m.upgrade;
            if (m.visibility !== "list") return;
            const name = typeof m.name === "string" && m.name.trim().length > 0 ? m.name.trim().slice(0, 80) : slug;
            const efforts = (Array.isArray(m.efforts) ? m.efforts : [])
                .filter(effort => typeof effort === "string" && root.codexEffortLevels.hasOwnProperty(effort));
            listed.push({
                slug: slug,
                name: name,
                efforts: efforts,
                defaultEffort: typeof m.default === "string" ? m.default : "",
                priority: Number.isFinite(m.priority) ? m.priority : Infinity,
                index: index,
            });
        });
        if (listed.length === 0) return null;
        listed.sort((a, b) => (a.priority - b.priority) || (a.index - b.index));
        return { listed: listed, upgrades: upgrades };
    }

    // Where a saved pick the plan no longer lists goes: its catalog upgrade
    // when that is listed, else the plan's first model.
    function _planSuccessor(fmt: string, id: string): string {
        const planModels = root.cliPlanModels[fmt] ?? {};
        if (fmt === "codex-cli") {
            const upgrades = root._codexCatalog?.upgrades ?? {};
            let slug = Object.keys(upgrades).find(s => root.codexModelId(s) === id);
            for (let hop = 0; slug !== undefined && hop < 5; hop++) {
                slug = upgrades[slug];
                if (slug === undefined) break;
                if (planModels[root.codexModelId(slug)] !== undefined) return root.codexModelId(slug);
            }
        }
        return root.cliPlans[fmt].firstPick;
    }

    readonly property var cliPlanModels: ({
        "claude-code": {
            "claude-fable": { alias: "fable", name: "Claude Fable" },
            "claude-opus": { alias: "opus", name: "Claude Opus" },
            "claude-opus-1m": { alias: "opus[1m]", name: "Claude Opus 1M" },
            "claude-sonnet": { alias: "sonnet", name: "Claude Sonnet" },
            "claude-haiku": { alias: "haiku", name: "Claude Haiku" },
        },
        "codex-cli": root._codexPlanModels,
        // Google serves personal accounts through Antigravity; supports Gemini 3
        // with dynamic reasoning effort.
        "antigravity-cli": {
            "gemini-plan-3-8-flash": { alias: "gemini-3.8-flash", name: "Gemini Flash", thinkingLevel: "" },
            "gemini-plan-3-1-pro": { alias: "gemini-3.1-pro", name: "Gemini Pro", thinkingLevel: "" },
        }
    })
    readonly property var cliPlans: ({
        "claude-code": {
            setupId: "claude-code",
            setupName: "Claude (Pro/Max plan)",
            setupDescription: Translation.tr("Plan | Anthropic's Claude through your Pro/Max subscription. Sign in from the sidebar, no API key needed"),
            readyDescription: Translation.tr("Plan | Your Claude subscription. Pick it to use its models"),
            setupHomepage: "https://docs.anthropic.com/en/docs/claude-code",
            modelDescription: Translation.tr("Plan | %1 through your Claude subscription. No API key needed"),
            signedIn: Translation.tr("Signed in. The plan models are in the picker now: type /model to choose between Fable, Opus, Opus 1M, Sonnet, and Haiku."),
            icon: "claude-symbolic",
            endpoint: "https://api.anthropic.com",
            homepage: "https://www.anthropic.com/claude",
            firstPick: "claude-fable",
            idPrefix: "claude-",
        },
        "codex-cli": {
            setupId: "codex-plan",
            setupName: "Codex (ChatGPT plan)",
            setupDescription: Translation.tr("Plan | OpenAI's Codex through your ChatGPT subscription. Sign in from the sidebar, no API key needed"),
            readyDescription: Translation.tr("Plan | Your ChatGPT subscription. Pick it to use its models"),
            setupHomepage: "https://learn.chatgpt.com/docs/codex/cli",
            modelDescription: Translation.tr("Plan | %1 through your ChatGPT subscription. No API key needed"),
            signedIn: Translation.tr("Signed in. The plan models are in the picker now: type /model to choose one."),
            icon: "openai-symbolic",
            endpoint: "https://chatgpt.com",
            homepage: "https://learn.chatgpt.com/docs/codex/cli",
            firstPick: Object.keys(root._codexPlanModels)[0] ?? "",
            idPrefix: "codex-",
        },
        // Google serves personal accounts through Antigravity now; the
        // Gemini CLI turns them away.
        "antigravity-cli": {
            // "gemini" alone would also match the key-backed Gemini ids.
            setupId: "gemini-plan",
            setupName: "Gemini (Google account)",
            setupDescription: Translation.tr("Plan | Google's Gemini through Antigravity and your Google account, free or with Google AI Pro or Ultra. Sign in from the sidebar, no API key needed"),
            readyDescription: Translation.tr("Plan | Your Google account. Pick it to use its models"),
            setupHomepage: "https://antigravity.google/product/antigravity-cli",
            modelDescription: Translation.tr("Plan | %1 through your Google account. No API key needed"),
            signedIn: Translation.tr("Signed in. Gemini Flash and Gemini Pro are in the picker now. Adjust thinking level with /think."),
            icon: "antigravity-symbolic",
            endpoint: "https://antigravity.google",
            homepage: "https://antigravity.google",
            firstPick: "gemini-plan-3-8-flash",
            idPrefix: "gemini-plan",
        }
    })
    property var cliPlanState: ({})
    function cliInstalled(fmt) { return root.cliPlanState[fmt]?.installed === true }
    function cliReady(fmt) { return root.cliPlanState[fmt]?.ready === true }
    // Which plan a model id belongs to, answered from the id alone so it also
    // holds for a model that is not in the picker yet. The setup entry is
    // deliberately not one of these: it is the way into a plan, not a model
    // of it, so it stays listed while the plan's own models are put away.
    function planFormatFor(id) {
        for (const fmt of Object.keys(root.cliPlanModels))
            if (root.cliPlanModels[fmt][id] !== undefined) return fmt;
        // Codex names its models from a catalog that may not have answered
        // yet or may have dropped a saved one, so its whole id space counts.
        const codex = root.cliPlans["codex-cli"];
        if (String(id).startsWith(codex.idPrefix) && id !== codex.setupId) return "codex-cli";
        return "";
    }
    property string setupState: ""
    // The native CLI installs to ~/.local/bin, which the compositor session
    // does not put on PATH for the shell, so every claude invocation carries
    // its own. Without it the detector reports a logged-in machine as having
    // no CLI at all.
    readonly property string cliPathPrefix: "export PATH=\"$HOME/.local/bin:$PATH\"; "
    readonly property var currentCliSetup: currentModel && !currentModel.requires_key
        ? (cliSetup[currentModel.api_format] ?? null) : null
    readonly property bool currentModelNeedsSetup: currentCliSetup !== null
        && (!cliReady(currentModel.api_format) || setupState !== "")

    function syncGeminiApiModels(targetId) {
        const current = targetId || root.currentModelId;
        const isGeminiActive = root.isGeminiApiModel(current);
        let next = Object.assign({}, root._registry);
        let changed = false;

        if (isGeminiActive) {
            if (next["gemini"]) {
                root._bury(next["gemini"]);
                delete next["gemini"];
                changed = true;
            }
            for (const id of Object.keys(root.geminiApiCatalog)) {
                if (next[id]) continue;
                next[id] = aiModelComponent.createObject(root, root.geminiApiCatalog[id]);
                changed = true;
            }
        } else {
            for (const id of Object.keys(root.geminiApiCatalog)) {
                if (next[id]) {
                    root._bury(next[id]);
                    delete next[id];
                    changed = true;
                }
            }
            if (!next["gemini"]) {
                next["gemini"] = aiModelComponent.createObject(root, {
                    "name": "Gemini",
                    "icon": "google-gemini-symbolic",
                    "description": Translation.tr("Online | Google's model\nGoogle's Gemini models with a free tier: Gemini Flash and Gemini Pro."),
                    "homepage": "https://aistudio.google.com",
                    "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:streamGenerateContent",
                    "model": "gemini-flash-latest",
                    "requires_key": true,
                    "key_id": "gemini",
                    "key_get_link": "https://aistudio.google.com/app/apikey",
                    "key_get_description": Translation.tr("**Pricing**: free tier, with data used for training. Web search needs billing turned on.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
                    "api_format": "gemini",
                    "sendTemperature": false,
                    "thinkingLevel": "",
                });
                changed = true;
            }
        }
        if (changed) root._registry = next;
    }

    function syncCliPlanModels(fmt) {
        const plan = root.cliPlans[fmt];
        const planModels = root.cliPlanModels[fmt];
        if (!plan || !planModels) return;
        let next = Object.assign({}, root._registry);
        let changed = false;
        // What this plan registered before, in picker order. A catalog that
        // changed since leaves entries that are gone, renamed or out of order.
        const registered = Object.keys(next).filter(id => id !== plan.setupId
            && next[id]?.api_format === fmt && !next[id].requires_key);
        // A plan shows its models only while it is the one being used. Two
        // signed-in plans would otherwise put nine entries in the picker at
        // once, most of them for the provider nobody is talking to.
        if (root.cliReady(fmt) && root.planFormatFor(root.currentModelId) === fmt) {
            if (next[plan.setupId]) { root._bury(next[plan.setupId]); delete next[plan.setupId]; changed = true; }
            const wantedIds = Object.keys(planModels);
            const current = registered.length === wantedIds.length && wantedIds.every((id, i) => registered[i] === id
                && next[id].name === planModels[id].name && next[id].model === planModels[id].alias
                && next[id].thinkingLevel === (planModels[id].thinkingLevel ?? ""));
            if (!current) {
                for (const id of registered) { root._bury(next[id]); delete next[id]; changed = true; }
            }
            for (const id of wantedIds) {
                if (next[id]) continue;
                const planEntry = planModels[id];
                next[id] = aiModelComponent.createObject(root, {
                    "name": planEntry.name,
                    "icon": plan.icon,
                    "description": plan.modelDescription.arg(planEntry.name),
                    "homepage": plan.homepage,
                    // Never requested: the CLI strategy writes its own
                    // command. A real address keeps the local-only policy
                    // honest about this being an online model.
                    "endpoint": plan.endpoint,
                    "model": planEntry.alias,
                    "requires_key": false,
                    "api_format": fmt,
                    "sendTemperature": fmt !== "antigravity-cli",
                    "thinkingLevel": planEntry.thinkingLevel ?? "",
                });
                changed = true;
            }
        } else {
            for (const id of registered) { root._bury(next[id]); delete next[id]; changed = true; }
            const wanted = root.cliReady(fmt) ? plan.readyDescription : plan.setupDescription;
            if (!next[plan.setupId] || next[plan.setupId].description !== wanted) {
                if (next[plan.setupId]) root._bury(next[plan.setupId]);
                next[plan.setupId] = aiModelComponent.createObject(root, {
                    "name": plan.setupName,
                    "icon": plan.icon,
                    "description": wanted,
                    "homepage": plan.setupHomepage,
                    "endpoint": plan.endpoint,
                    "model": plan.setupId,
                    "requires_key": false,
                    "api_format": fmt,
                    "supportsSessions": false,
                });
                changed = true;
            }
        }
        if (changed) root._registry = next;
    }

    // One detector serves every CLI. Requests that arrive while it is busy queue up,
    // except a sign-in poll waiting on its exit file: the next tick asks again.
    // Busy is tracked here: until the shell has finished loading, the Process
    // holds a start back and still reads as not running.
    property var _detectQueue: []
    property bool _detecting: false
    // A plan's catalog is read once per need (startup, a sign-in, an explicit
    // reread), not on every check: need and served are counters per plan.
    property var _catalogNeed: ({})
    property var _catalogServed: ({})
    function detectCli(fmt, waitForLogin = false, rereadCatalog = false) {
        const entry = root.cliSetup[fmt];
        if (!entry) return;
        if (rereadCatalog && entry.catalog) root._catalogNeed[fmt] = (root._catalogNeed[fmt] ?? 1) + 1;
        if (root._detecting) {
            if (waitForLogin || cliDetectProc.format === fmt) return;
            // Asked again while waiting means it is wanted now, so it goes next.
            const waiting = root._detectQueue.filter(f => f !== fmt);
            root._detectQueue = waiting.length < root._detectQueue.length ? [fmt].concat(waiting) : waiting.concat([fmt]);
            return;
        }
        const readyCheck = waitForLogin && entry.loginDoneCheck
            ? `${entry.loginDoneCheck} && ${entry.readyCheck}` : entry.readyCheck;
        // The catalog is read with the sign-in it depends on, so a plan's
        // models and its readiness always land together. Only while online AI
        // is allowed, since the CLI may refresh it over the network.
        const need = root._catalogNeed[fmt] ?? 1;
        const catalog = entry.catalog && need !== (root._catalogServed[fmt] ?? 0)
            && Config.options?.policies?.ai === 1 ? `; ${entry.catalog}` : "";
        const features = entry.features ? `; ${entry.features}` : "";
        let script = root.cliPathPrefix + `if command -v ${entry.cmd} >/dev/null 2>&1; then echo installed; if ${readyCheck}; then echo ready${catalog}${features}; fi; fi < /dev/null`;
        if (entry.loginFailedCheck) script += `; if ${entry.loginFailedCheck}; then echo loginfailed; fi`;
        root._detecting = true;
        cliDetectProc.format = fmt;
        cliDetectProc.catalogNeed = catalog ? need : 0;
        cliDetectProc.buf = "";
        cliDetectProc.command = catalog ? ["bash", "-lc", script, "_", entry.catalogFilter] : ["bash", "-lc", script];
        cliDetectProc.running = true;
    }
    function _detectNext() {
        const queued = root._detectQueue.shift();
        if (queued) root.detectCli(queued);
    }

    function setupCurrentModel() {
        const entry = root.currentCliSetup;
        if (!entry || root.setupState === "installing" || root.setupState === "loggingIn") return;
        const fmt = root.currentModel.api_format;
        if (root.cliInstalled(fmt)) {
            root._runLogin();
        } else if (entry.install) {
            root.setupState = "installing";
            // The installer's own exit status proves nothing: a piped download
            // that fetches nothing still leaves the pipeline reporting the
            // reading shell's success, and the flow then opens a sign-in
            // window for a command that is not there. Asking for the command
            // last is what makes a zero mean the tool is really there, and it
            // answers for every way an install can fall short, not just that
            // one.
            installProc.command = ["bash", "-lc", root.cliPathPrefix + entry.install
                + "; command -v " + entry.cmd + " >/dev/null 2>&1"];
            installProc.running = false;
            installProc.running = true;
        }
    }

    // The login flow is interactive: only under a terminal does the CLI print
    // its link, open the browser, and take back whatever the flow needs. So
    // the sign-in gets a real terminal window and the watcher below notices
    // when the login lands. A CLI whose only question can be answered for the
    // user signs in with no window at all, and gets longer to finish, since
    // the whole sign-in then happens in the browser.
    function _runLogin() {
        const entry = root.currentCliSetup;
        if (!entry) return;
        root.loginCodeSent = false;
        root.setupState = "loggingIn";
        loginWatch.hiddenLogin = entry.loginInBackground === true;
        if (entry.loginInBackground) {
            Quickshell.execDetached(["bash", "-c", root.cliPathPrefix + entry.login]);
            loginWatch.triesLeft = 150;
            return;
        }
        const script = root.cliPathPrefix + entry.login
            + "; echo; echo 'You can close this window.'; read -r -n 1 -s";
        Quickshell.execDetached(["bash", "-c",
            `${Config.options.apps.terminal} -e bash -c '${CF.StringUtils.shellSingleQuoteEscape(script)}'`]);
        loginWatch.triesLeft = 60;
    }

    // For a browser tab closed before the sign-in finished: starting over
    // opens a fresh one and replaces the attempt that was waiting on it.
    function restartLogin() {
        if (root.setupState !== "loggingIn" || !root.currentCliSetup?.loginInBackground) return;
        root._runLogin();
    }

    // ── The code a browser sign-in hands back ─────────────────────
    // Some CLIs finish signing in only once the code Google's page shows is
    // typed back in. The sidebar takes it from the clipboard: by itself when
    // the page's Copy button changes it, or from Paste Code. What the
    // clipboard held when the sign-in began is left alone, since sending a
    // code from an earlier attempt would use this attempt up.
    property bool loginCodeSent: false
    property string _clipboardAtStart: ""
    readonly property bool watchingForLoginCode: root.setupState === "loggingIn"
        && (root.currentCliSetup?.loginCodePipe ?? "") !== "" && !root.loginCodeSent

    function looksLikeLoginCode(text) {
        return /^[A-Za-z0-9\/_.~-]{10,512}$/.test(text);
    }

    // What the watcher sends without being asked has to look like Google's
    // code, which always carries a slash. A password copied during the same
    // sign-in usually does not, and sending one would hand it to the CLI.
    function looksLikeCopiedCode(text) {
        return text.length >= 20 && text.indexOf("/") !== -1 && root.looksLikeLoginCode(text);
    }

    function sendLoginCode(code) {
        const entry = root.currentCliSetup;
        const clean = (code ?? "").trim();
        if (!entry?.loginCodePipe || !root.looksLikeLoginCode(clean) || codeSendProc.running) return;
        root.loginCodeSent = true;
        codeSendProc.pendingCode = clean;
        codeSendProc.command = ["bash", "-c",
            `f="${entry.loginCodePipe}"; [ -p "$f" ] || exit 3; timeout 5 bash -c 'cat > "$1"' _ "$f"`];
        codeSendProc.stdinEnabled = true;
        codeSendProc.running = true;
    }

    function pasteLoginCode() {
        clipboardReadProc.running = false;
        clipboardReadProc.running = true;
    }

    // The code goes down stdin: as an argument it would be readable in ps by
    // anyone on the machine while the command runs.
    Process {
        id: codeSendProc
        property string pendingCode: ""
        onRunningChanged: {
            if (running && pendingCode.length > 0) {
                write(pendingCode + "\n");
                pendingCode = "";
                stdinEnabled = false;
            }
        }
        // No pipe means the sign-in it belonged to is already over.
        onExited: (code) => {
            if (code !== 0 && root.setupState === "loggingIn") root.setupState = "error";
        }
    }

    Process {
        id: clipboardReadProc
        command: ["wl-paste", "--no-newline", "--type", "text"]
        stdout: StdioCollector { onStreamFinished: root.sendLoginCode(this.text) }
    }

    // wl-paste reads the clipboard without the focus a Qt clipboard read
    // needs, so the code is seen even while the browser has it. The snapshot
    // is taken first, and each new clipboard arrives as one line.
    Process {
        id: clipboardSnapshotProc
        command: ["bash", "-c", "wl-paste --no-newline --type text 2>/dev/null | head -c 600 | tr -d '\\n'"]
        stdout: StdioCollector {
            onStreamFinished: {
                root._clipboardAtStart = this.text.trim();
                if (root.watchingForLoginCode) clipboardWatchProc.running = true;
            }
        }
    }
    Process {
        id: clipboardWatchProc
        command: ["wl-paste", "--type", "text", "--watch", "bash", "-c", "head -c 600 | tr -d '\n'; echo"]
        stdout: SplitParser {
            onRead: line => {
                const text = line.trim();
                if (text !== root._clipboardAtStart && root.looksLikeCopiedCode(text)) root.sendLoginCode(text);
            }
        }
    }
    onWatchingForLoginCodeChanged: {
        clipboardWatchProc.running = false;
        if (root.watchingForLoginCode) {
            clipboardSnapshotProc.running = false;
            clipboardSnapshotProc.running = true;
        }
    }

    // The way out when the sign-in in the background could not finish: the
    // CLI's own app in a terminal, watched the same way as the others.
    function loginInTerminal() {
        const entry = root.currentCliSetup;
        if (!entry?.terminalLogin) return;
        // The terminal takes the code itself, and there is no pipe to send one
        // down, so the clipboard is left alone.
        root.loginCodeSent = true;
        root.setupState = "loggingIn";
        loginWatch.hiddenLogin = false;
        const script = root.cliPathPrefix + entry.terminalLogin;
        Quickshell.execDetached(["bash", "-c",
            `${Config.options.apps.terminal} -e bash -c '${CF.StringUtils.shellSingleQuoteEscape(script)}'`]);
        loginWatch.triesLeft = 150;
    }

    Process {
        id: cliDetectProc
        property string format: ""
        property string buf: ""
        property int catalogNeed: 0
        stdout: SplitParser { onRead: line => cliDetectProc.buf += line + "\n" }
        // A start that failed ends with no exit.
        onRunningChanged: if (!running && root._detecting) {
            root._detecting = false;
            root._detectNext();
        }
        onExited: (code) => {
            root._detecting = false;
            const fmt = cliDetectProc.format;
            const wasReady = root.cliReady(fmt);
            const lines = cliDetectProc.buf.split("\n");
            const catalogLine = lines.find(line => line.startsWith("catalog "));
            const buf = lines.filter(line => !line.startsWith("catalog ") && !line.startsWith("feature ")).join("\n");
            const catalog = fmt === "codex-cli" && catalogLine !== undefined ? root._parseCodexCatalog(catalogLine.slice(8)) : null;
            if (catalog !== null) root._codexCatalog = catalog;
            const nextState = Object.assign({}, root.cliPlanState);
            nextState[fmt] = {
                installed: buf.includes("installed"),
                ready: buf.includes("ready"),
                features: lines.filter(line => line.startsWith("feature ")).map(line => line.slice(8)),
            };
            // A read that ran is spent even when it failed: the last good list
            // stands until the next need. Signed out, the next sign-in reads again.
            if (!nextState[fmt].ready) delete root._catalogServed[fmt];
            else if (cliDetectProc.catalogNeed > 0) root._catalogServed[fmt] = cliDetectProc.catalogNeed;
            root.cliPlanState = nextState;
            if (nextState[fmt].ready && root.currentModel?.api_format === fmt) root.setupState = "";
            // A sign-in in the background that ended without a login is over,
            // so the banner offers the next step now rather than at the end
            // of the watch.
            else if (buf.includes("loginfailed") && root.setupState === "loggingIn"
                    && root.currentModel?.api_format === fmt) root.setupState = "error";
            root.syncCliPlanModels(fmt);
            const plan = root.cliPlans[fmt];
            if (!wasReady && nextState[fmt].ready && root.currentModelId === plan.setupId) {
                root.setModel(plan.firstPick, true);
                root.addMessage(plan.signedIn, root.interfaceRole);
            }
            // A selection this family no longer offers (a lapsed login, or a
            // model entry that was retired) falls to the best seat still open
            // rather than dangling on an id that no longer resolves.
            // Until a catalog read has run, a pick the built-in list lacks may
            // still be offered, so it waits for one.
            const listUnknown = fmt === "codex-cli" && root._codexCatalog === null && root._catalogServed[fmt] === undefined;
            if (root.models[root.currentModelId] === undefined && root.currentModelId.startsWith(plan.idPrefix)
                    && !(nextState[fmt].ready && listUnknown)) {
                Persistent.states.ai.model = nextState[fmt].ready ? root._planSuccessor(fmt, root.currentModelId) : plan.setupId;
            }
            // A model's levels and default may have changed with the catalog.
            if (catalog !== null && root.models[root.currentModelId]?.api_format === fmt)
                root.restoreThinkingLevelForModel(root.currentModelId);
            root._detectNext();
        }
    }
    // When the vendor download will not come, the same CLI is in the system
    // repositories. One prompt, and the sidebar never sends anybody to a
    // terminal to finish what it offered to do.
    function installFromSystemRepo() {
        const entry = root.currentCliSetup;
        if (!entry || !entry.installFallback || root.setupState === "installing") return;
        root.setupState = "installing";
        fallbackInstallProc.running = false;
        fallbackInstallProc.command = ["pkexec", "/usr/local/bin/ai-cli-install", entry.installFallback];
        fallbackInstallProc.running = true;
    }

    Process {
        id: fallbackInstallProc
        onExited: (code) => {
            // The password prompt takes the focus the sidebar closes on, so
            // answering it puts the conversation away mid-setup.
            GlobalStates.sidebarLeftOpen = true;
            if (code !== 0) { root.setupState = "error"; return; }
            const fmt = root.currentModel?.api_format;
            if (fmt) {
                const nextState = Object.assign({}, root.cliPlanState);
                nextState[fmt] = Object.assign({}, nextState[fmt], { installed: true });
                root.cliPlanState = nextState;
            }
            root._runLogin();
        }
    }

    Process {
        id: installProc
        onExited: (code) => {
            if (code === 0) {
                const fmt = root.currentModel?.api_format;
                if (fmt) {
                    const nextState = Object.assign({}, root.cliPlanState);
                    nextState[fmt] = Object.assign({}, nextState[fmt], { installed: true });
                    root.cliPlanState = nextState;
                }
                root._runLogin();
            } else { root.setupState = "error"; }
        }
    }
    Timer {
        id: loginWatch
        property int triesLeft: 0
        property bool hiddenLogin: false
        interval: 2000
        repeat: true
        running: triesLeft > 0 && root.setupState === "loggingIn"
            && !root.cliReady(root.currentModel?.api_format ?? "")
        onTriggered: {
            triesLeft--;
            const fmt = root.currentModel?.api_format;
            // The CLI's own check is a large binary and a network request. Until
            // the hidden sign-in writes its exit file, it runs only every 10 s.
            if (fmt) root.detectCli(fmt, hiddenLogin && triesLeft % 5 !== 0);
            if (triesLeft <= 0) root.setupState = "error";
        }
    }
    // Nothing here while the service is still being built. The id resolves the
    // first time any binding above asks for it, and the work below registers a
    // plan's models, which rewrites the map those same bindings are reading:
    // Qt takes a binding whose own evaluation changed what it depends on for a
    // loop and abandons it, so whichever property asked first went unanswered
    // for the rest of the session. The startup pass below does all of this
    // once, for every plan rather than only the selected one, so a start loses
    // nothing by leaving it alone.
    property bool _startupDone: false

    onCurrentModelIdChanged: {
        if (!root._startupDone) return;
        root.setupState = "";
        root.syncGeminiApiModels();
        // Both plans re-read the selection: the one just entered brings its
        // models in, and the one just left puts its own away.
        for (const fmt of Object.keys(root.cliSetup)) root.syncCliPlanModels(fmt);
        // By id: currentModel has not caught up with the new id yet here.
        const format = root.models[root.currentModelId]?.api_format ?? "";
        const fmt = root.planFormatFor(root.currentModelId) || (root.cliSetup[format] !== undefined ? format : "");
        if (fmt !== "") root.detectCli(fmt);
        root.restoreThinkingLevelForModel(root.currentModelId);
        root._resetTokenCount();
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return;
            root.addUserModels()
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (!Persistent.ready) return;
            root.restoreThinkingLevelForModel(root.currentModelId);
            if (root._detectAllWhenReady) {
                root._detectAllWhenReady = false;
                root._detectAllPlans();
            }
        }
    }

    property bool _detectAllWhenReady: false
    // Every plan is checked, one after another, the selected one first.
    function _detectAllPlans() {
        const selectedPlan = root.planFormatFor(root.currentModelId) || (root.models[root.currentModelId]?.api_format ?? "");
        const plans = Object.keys(root.cliSetup).sort((a, b) => (b === selectedPlan) - (a === selectedPlan));
        for (const fmt of plans) root.detectCli(fmt);
    }

    // The policy can change while a reply is running or a card is waiting,
    // with the chat page gone (Off) or the model no longer allowed (Local).
    Connections {
        target: Config.options?.policies ?? null
        function onAiChanged() { root._applyAiPolicy() }
    }

    function _applyAiPolicy() {
        const policy = Config.options?.policies?.ai ?? 0;
        if (policy === 1) {
            // A catalog passed over while online AI was off is read now.
            const fmt = root.planFormatFor(root.currentModelId);
            if (root.cliSetup[fmt]?.catalog) root.detectCli(fmt);
            return;
        }
        if (policy !== 0 && policy !== 2) return;
        const disallowed = id => policy === 0 || root._isOnlineModelId(id);
        // Stopped as Stop does: the process group is killed and a stopped
        // request never continues into a function call.
        if (root._req && disallowed(root._req.modelId)) root.cancelRequest();
        if (root.pendingConfirmation && disallowed(root.pendingConfirmation.modelId)) {
            root._dropConfirmation();
            root._saveNow();
        }
    }

    property string pendingFilePath: ""

    Component.onCompleted: {
        root.syncGeminiApiModels();
        // The default model is local AI, whose setup entry does not exist
        // until the first status answer arrives. Running it through setModel
        // here would start the walkthrough unprompted at every shell start;
        // syncOllamaSetupEntry and the model fetch land the selection instead.
        if (currentModelId !== root.ollamaSetupModelId)
            setModel(currentModelId, false, false); // Do necessary setup for model
        root.addUserModels() // Config onReadyChanged above might not fire if config is loaded before this service
        for (const fmt of Object.keys(root.cliSetup))
            root.syncCliPlanModels(fmt) // The setup entries exist before the CLIs answer
        // The selection is only known once the saved state is read.
        if (Persistent.ready) root._detectAllPlans();
        else root._detectAllWhenReady = true;
        // Last: everything above is the work the selection handler skips while
        // the service is being built, and a selection made from here on is its
        // own to answer.
        root._startupDone = true;
        root.restoreThinkingLevelForModel(root.currentModelId);
        // The last session is read in the background once the shell is up;
        // a New chat or a load before it lands wins.
        root._loadGeneration++;
        root.sessionLoading = true;
        const generation = root._loadGeneration;
        Qt.callLater(() => {
            if (generation === root._loadGeneration)
                root._startLoad(root.autoSaveFilePath, "startup", "");
        });
    }

    Component.onDestruction: {
        // Quickshell kills only the leader on teardown; the group goes too.
        const pgid = root._req?.pgid;
        if (Number.isInteger(pgid) && pgid > 1)
            Quickshell.execDetached(["kill", "-TERM", "--", "-" + pgid]);
    }

    function guessModelLogo(model) {
        if (model.includes("llama")) return "ollama-symbolic";
        if (model.includes("gemma")) return "google-gemini-symbolic";
        if (model.includes("deepseek")) return "deepseek-symbolic";
        if (/^phi\d*:/i.test(model)) return "microsoft-symbolic";
        return "ollama-symbolic";
    }

    function guessModelName(model) {
        const replaced = model.replace(/-/g, ' ').replace(/:/g, ' ');
        let words = replaced.split(' ');
        words[words.length - 1] = words[words.length - 1].replace(/(\d+)b$/, (_, num) => `${num}B`)
        words = words.map((word) => {
            return (word.charAt(0).toUpperCase() + word.slice(1))
        });
        if (words[words.length - 1] === "Latest") words.pop();
        else words[words.length - 1] = `(${words[words.length - 1]})`; // Surround the last word with square brackets
        const result = words.join(' ');
        return result;
    }

    function addModel(modelName, data) {
        const replaced = root._registry[modelName];
        root._registry = Object.assign({}, root._registry, {
            [modelName]: aiModelComponent.createObject(root, data)
        });
        if (replaced) root._bury(replaced);
    }

    // What the local Ollama install is currently able to do. The sidebar reads
    // this to say something useful instead of showing an empty list: not
    // installed, installed but not running, running with nothing pulled yet, or
    // ready. Starts as "checking" so nothing is claimed before the first answer.
    property string ollamaState: "checking"
    readonly property bool ollamaReady: root.ollamaState === "ok"

    // The model picker is the only place local AI is ever mentioned, so while
    // it is not ready the setup step is listed there as if it were a model.
    // Without it a fresh install shows no trace of Ollama and offers nothing
    // to click, which is exactly the state most machines boot into: the
    // package is installed but its unit ships disabled.
    readonly property string ollamaSetupModelId: "local-ai-setup"
    readonly property string ollamaSetupEntryName: Translation.tr("Local AI (Ollama)")
    readonly property string ollamaSuggestedModel: "llama3.2:3b"
    property bool ollamaBusy: false
    property string ollamaPullMessageId: ""
    property string ollamaPendingSelect: ""

    onOllamaStateChanged: {
        root.syncOllamaSetupEntry();
        // A walkthrough request that arrived before the first status answer
        // is honored the moment the answer lands, so nobody is told to wait
        // and then left to come back on their own.
        if (root.ollamaWalkthroughPending && root.ollamaState !== "checking") {
            root.ollamaWalkthroughPending = false;
            // The delivered step's own action re-kicks polling if it needs
            // it, so the rest of this burst would only re-ask a settled
            // question.
            ollamaBurst.triesLeft = 0;
            // "ok" needs no walkthrough: the fetch that raised it lands the
            // model selection itself a moment later.
            if (root.ollamaState !== "ok")
                root.startOllamaWalkthrough();
        }
    }

    // Asking once at startup meant a user who installed Ollama, started the
    // service, or pulled a model had to restart the shell before any of it
    // counted. Ask again, but only while somebody is looking: a machine that is
    // never going to have Ollama would otherwise spend the rest of its life
    // waking up to ask. Opening the sidebar is also the moment the answer starts
    // mattering, so that is when it re-checks.
    Timer {
        id: ollamaRecheck
        interval: 20000
        repeat: true
        running: root.ollamaState !== "ok" && GlobalStates.sidebarLeftOpen
        onTriggered: root.refreshOllama()
    }

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (GlobalStates.sidebarLeftOpen && root.ollamaState !== "ok") root.refreshOllama();
        }
    }

    function refreshOllama() {
        if (!getOllamaModels.running) getOllamaModels.running = true;
    }

    // The 20s recheck above is paced for a sidebar somebody left open, not
    // for the seconds right after an install, a service start, or a pull,
    // when the state is about to change and the user is watching it. A kick
    // asks again every second and a half for a short burst, and stops early
    // the moment local AI answers ready.
    // Set when the walkthrough was asked for while the state was still
    // unknown, so the answer continues the walkthrough by itself instead of
    // leaving a message telling the user to come back.
    property bool ollamaWalkthroughPending: false
    Timer {
        id: ollamaBurst
        property int triesLeft: 0
        interval: 1500
        repeat: true
        running: triesLeft > 0 && root.ollamaState !== "ok"
        onTriggered: {
            triesLeft--;
            root.refreshOllama();
        }
    }
    function kickOllamaRefresh() {
        ollamaBurst.triesLeft = 8;
        root.refreshOllama();
    }

    function fetchOllamaModels(): void {
        root.kickOllamaRefresh();
    }

    Process {
        id: getOllamaModels
        running: true
        command: ["bash", "-c", `${Directories.scriptPath}/ai/show-installed-ollama-models.sh`.replace(/file:\/\//, "")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    if (data.length === 0) return;
                    const parsed = JSON.parse(data);
                    // The script used to hand back a bare array. It now reports
                    // which of the failure states it is in alongside the list,
                    // so accept either shape rather than breaking on an older
                    // copy left behind by a partial update.
                    const dataJson = Array.isArray(parsed) ? parsed : (parsed.models ?? []);
                    root.ollamaState = Array.isArray(parsed)
                        ? (dataJson.length > 0 ? "ok" : "empty")
                        : (parsed.state ?? "empty");

                    if (dataJson.length === 0) {
                        // The server answered but has nothing to think with yet.
                        // Somebody who just gave their password to start it asked
                        // for local AI, so land on the setup entry, whose own
                        // description names the step still outstanding, rather
                        // than leaving the online model they were moved off
                        // sitting there as though nothing had happened.
                        if (root.ollamaSelectWhenReady && root.modelList.includes(root.ollamaSetupModelId))
                            root.selectOllamaSetupEntry();
                        return;
                    }
                    const next = Object.assign({}, root._registry);
                    const replaced = [];
                    let changed = false;
                    let currentArrived = false;
                    for (const model of dataJson) {
                        const id = root.safeModelName(model);
                        if (next[id] && next[id].model === model) continue;
                        if (next[id]) replaced.push(next[id]);
                        changed = true;
                        next[id] = root.aiModelComponent.createObject(root, {
                            "name": root.guessModelName(model),
                            "icon": root.guessModelLogo(model),
                            "description": Translation.tr("Local Ollama model | %1").arg(model),
                            "homepage": `https://ollama.com/library/${model}`,
                            "endpoint": "http://localhost:11434/v1/chat/completions",
                            "model": model,
                            "requires_key": false,
                        });
                        if (id === root.currentModelId) currentArrived = true;
                    }
                    if (changed) root._registry = next;
                    root._buryAll(replaced);

                    // The saved model may only now have become selectable, so
                    // take it up rather than leaving the default in place.
                    if (currentArrived) {
                        root.setModel(root.currentModelId, false, false);
                        root.restoreThinkingLevelForModel(root.currentModelId);
                    }

                    // A model the user just downloaded on purpose outranks the
                    // saved one, so it is switched to once it actually exists.
                    if (root.ollamaPendingSelect.length > 0) {
                        const justPulled = root.safeModelName(root.ollamaPendingSelect);
                        root.ollamaPendingSelect = "";
                        // A pull is a choice of its own and settles the question
                        // the service start left open, or the next refresh would
                        // pull the selection back to whatever is listed first.
                        root.ollamaSelectWhenReady = false;
                        if (root.modelList.includes(justPulled)) root.setModel(justPulled);
                    } else if (root.ollamaSelectWhenReady) {
                        // Answering the password prompt was a request for local
                        // AI, so land on it now that the server has something to
                        // answer with. Only the first arrival counts: after that
                        // the user's own choice stands.
                        const firstLocal = root.safeModelName(dataJson[0]);
                        root.ollamaSelectWhenReady = false;
                        if (root.modelList.includes(firstLocal)) root.setModel(firstLocal);
                    } else if (Persistent.ready && root._savedModelId === root.ollamaSetupModelId) {
                        // The saved model is the local AI default and a real
                        // local model just showed up: that is the machine this
                        // default was waiting for, so take the first one up.
                        // Only once the saved state has actually loaded: until
                        // then the saved id reads as that same default, and
                        // this would overwrite whichever model the user picked
                        // before the file arrived.
                        const firstLocal = root.safeModelName(dataJson[0]);
                        if (root.modelList.includes(firstLocal)) root.setModel(firstLocal, false);
                    }

                } catch (e) {
                    console.log("Could not fetch Ollama models:", e);
                }
            }
        }
    }

    function ollamaStateSummary() {
        switch (root.ollamaState) {
        case "missing":
            return Translation.tr("Not installed. Select to set up.");
        case "stopped":
            return Translation.tr("Installed but not running. Select to start it.");
        case "empty":
            return Translation.tr("No model downloaded yet. Select to get one.");
        default:
            return Translation.tr("Checking for local AI...");
        }
    }

    function syncOllamaSetupEntry() {
        // "checking" is deliberately not offered: the first answer usually
        // arrives within a second, and advertising setup for a machine that
        // turns out to be ready would flash an entry and take it away again.
        const wanted = (root.ollamaState !== "ok" && root.ollamaState !== "checking");
        if (wanted) {
            root.addModel(root.ollamaSetupModelId, {
                "name": root.ollamaSetupEntryName,
                "icon": "ollama-symbolic",
                "description": root.ollamaStateSummary(),
                "homepage": "https://ollama.com",
                "endpoint": "http://localhost:11434/v1/chat/completions",
                "model": "",
                "requires_key": false,
                "supportsSessions": false,
            });
        } else if (root._registry[root.ollamaSetupModelId]) {
            const removed = root._registry[root.ollamaSetupModelId];
            const remaining = Object.assign({}, root._registry);
            delete remaining[root.ollamaSetupModelId];
            root._registry = remaining;
            root._bury(removed);
        }
    }

    // Picking the setup entry is a request for help rather than a model
    // switch, so each state answers with the single action that moves it on.
    function startOllamaWalkthrough() {
        if (root.ollamaBusy) {
            root.addMessage(Translation.tr("Local AI setup is already working on it."), root.interfaceRole);
            return;
        }
        switch (root.ollamaState) {
        case "missing":
            root.addMessage(Translation.tr("### Local AI is not installed\n\nLocal AI answers on this computer. Nothing leaves the machine, and no API key is needed.\n\nInstall it from a terminal:\n\n```\nsudo pacman -S ollama\n```\n\nThen pick **Local AI (Ollama)** here again."), root.interfaceRole);
            break;
        case "stopped":
            root.addMessage(Translation.tr("### Starting local AI\n\nOllama is installed, but its service ships switched off. Turning it on asks for your password once, and from then on it starts by itself at every boot."), root.interfaceRole);
            root.startOllamaService();
            break;
        case "empty":
            root.addMessage(Translation.tr("### One download to go\n\nLocal AI is running but has no model to think with yet. **%1** is a good first one at roughly 2 GB. It downloads once, then works offline.\n\nStart by entering:\n\n```\n%2\n```\n\nAny model from [ollama.com/library](https://ollama.com/library) works too, for example `%2 qwen2.5:0.5b`.").arg(root.ollamaSuggestedModel).arg("/ollama pull"), root.interfaceRole);
            break;
        default:
            root.addMessage(Translation.tr("Checking for local AI now. The next step appears here in a moment."), root.interfaceRole);
            root.ollamaWalkthroughPending = true;
            root.kickOllamaRefresh();
        }
    }

    // Set while the walkthrough is starting the service, so the model it was
    // asked for is taken up once the server actually has one to offer. Picking
    // the setup entry deliberately leaves the working model alone, which is
    // right while nothing local can answer yet and wrong the moment one can.
    property bool ollamaSelectWhenReady: false

    function startOllamaService() {
        if (root.ollamaBusy) return;
        root.ollamaBusy = true;
        root.ollamaSelectWhenReady = true;
        ollamaServiceProc.running = true;
    }

    Process {
        id: ollamaServiceProc
        command: ["pkexec", "/usr/local/bin/ollama-setup", "enable"]
        stderr: StdioCollector {
            id: ollamaServiceError
        }
        onExited: exitCode => {
            root.ollamaBusy = false;
            if (exitCode === 0) {
                // The password prompt takes the focus the sidebar closes on, so
                // answering it puts the conversation away mid-walkthrough. Bring
                // it back rather than making the user find it again to read how
                // the step they just completed turned out.
                GlobalStates.sidebarLeftOpen = true;
                root.addMessage(Translation.tr("Local AI is running."), root.interfaceRole);
                // The server takes a few seconds to start listening, and a
                // single ask right now usually lands in that gap.
                root.kickOllamaRefresh();
                return;
            }
            root.ollamaSelectWhenReady = false;
            // pkexec reports 126 for a prompt that was refused or dismissed
            // and 127 for a helper it could not run at all. Neither means the
            // service failed, so neither should be reported as if it had.
            if (exitCode === 126) {
                root.addMessage(Translation.tr("Local AI was not started: the password prompt was dismissed."), root.interfaceRole);
                return;
            }
            if (exitCode === 127) {
                root.addMessage(Translation.tr("The local AI helper is missing. Reinstalling the Mainstream OS components restores it."), root.interfaceRole);
                return;
            }
            const detail = ollamaServiceError.text.trim();
            root.addMessage(detail.length > 0 ? Translation.tr("Could not start local AI.\n\n```\n%1\n```").arg(detail) : Translation.tr("Could not start local AI."), root.interfaceRole);
        }
    }

    function pullOllamaModel(modelName) {
        if (root.ollamaBusy) {
            root.addMessage(Translation.tr("A download is already running."), root.interfaceRole);
            return;
        }
        if (root.ollamaState === "missing" || root.ollamaState === "stopped") {
            root.startOllamaWalkthrough();
            return;
        }
        const target = (modelName ?? "").trim().length > 0 ? modelName.trim() : root.ollamaSuggestedModel;
        root.ollamaBusy = true;
        ollamaPullProc.modelName = target;
        ollamaPullProc.failure = "";
        ollamaPullProc.sawProgress = false;
        root.ollamaPullMessageId = root.addMessage(Translation.tr("Starting the download of **%1**...").arg(target), root.interfaceRole);
        // The name is passed as its own argument rather than inside a command
        // string, so a hostile model name cannot become shell syntax.
        ollamaPullProc.command = ["bash", `${Directories.scriptPath}/ai/ollama-pull.sh`.replace(/file:\/\//, ""), target];
        ollamaPullProc.running = true;
    }

    function setOllamaPullMessage(body) {
        const message = root.messageByID[root.ollamaPullMessageId];
        if (!message) return false;
        root._setMessageText(message, body);
        return true;
    }

    Process {
        id: ollamaPullProc
        property string modelName: ""
        property string failure: ""
        property bool sawProgress: false
        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                let update;
                try {
                    update = JSON.parse(data);
                } catch (e) {
                    return;
                }
                if (update.state === "error") {
                    // Held rather than shown, so the exit handler decides on
                    // one final message instead of racing this one.
                    ollamaPullProc.failure = update.message ?? "";
                    return;
                }
                if (update.state !== "pulling") return;
                const pct = update.pct ?? -1;
                if (pct >= 0) {
                    ollamaPullProc.sawProgress = true;
                    root.setOllamaPullMessage(Translation.tr("Downloading **%1**: %2%").arg(ollamaPullProc.modelName).arg(pct));
                } else if (ollamaPullProc.sawProgress) {
                    // The server reports no byte counts while it checksums and
                    // writes the manifest, which on a large model is a long
                    // wait immediately after the bar reaches 100%.
                    root.setOllamaPullMessage(Translation.tr("Finishing **%1**...").arg(ollamaPullProc.modelName));
                }
            }
        }
        onExited: exitCode => {
            const name = ollamaPullProc.modelName;
            const failure = ollamaPullProc.failure;
            root.ollamaBusy = false;
            if (exitCode === 0 && failure.length === 0) {
                root.setOllamaPullMessage(Translation.tr("**%1** is ready and selected. It answers on this computer, needs no API key, and keeps working with the network off.").arg(name));
                root.ollamaPullMessageId = "";
                // Selecting it is the point of having downloaded it, so the
                // refresh is told to finish the job it was started for.
                root.ollamaPendingSelect = name;
                root.kickOllamaRefresh();
                return;
            }
            const body = failure.length > 0 ? Translation.tr("Could not download **%1**.\n\n```\n%2\n```").arg(name).arg(failure) : Translation.tr("Could not download **%1**.").arg(name);
            if (!root.setOllamaPullMessage(body)) root.addMessage(body, root.interfaceRole);
            root.ollamaPullMessageId = "";
        }
    }

    Process {
        id: getDefaultPrompts
        running: true
        command: ["ls", "-1", Directories.defaultAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.defaultPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.defaultAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getUserPrompts
        running: true
        command: ["ls", "-1", Directories.userAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.userPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.userAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getSavedChats
        // A refresh asked for while one runs repeats once it ends, so a file
        // written in between is not missed.
        property bool again: false
        running: true
        command: ["find", Directories.aiChats, "-maxdepth", "1", "-type", "f", "-name", "*.json", "-printf", "%f\\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = this.text.split("\n")
                    .filter(fileName => fileName.endsWith(".json") && fileName !== "lastSession.json");
                names.sort((a, b) => {
                    const x = a.toLowerCase();
                    const y = b.toLowerCase();
                    return x < y ? -1 : (x > y ? 1 : 0);
                });
                root.savedChats = names.map(fileName => `${Directories.aiChats}/${fileName}`);
            }
        }
        onExited: {
            if (getSavedChats.again) {
                getSavedChats.again = false;
                getSavedChats.running = true;
            }
        }
    }

    function reloadSavedChats(): void {
        if (getSavedChats.running) getSavedChats.again = true;
        else getSavedChats.running = true;
    }

    FileView {
        id: promptLoader
        watchChanges: false;
        onLoadedChanged: {
            if (!promptLoader.loaded) return;
            Config.options.ai.systemPrompt = promptLoader.text();
            root.addMessage(Translation.tr("Loaded the following system prompt\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
        }
    }

    function printPrompt() {
        root.addMessage(Translation.tr("The current system prompt is\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
    }

    function loadPrompt(filePath) {
        promptLoader.path = "" // Unload
        promptLoader.path = filePath; // Load
        promptLoader.reload();
    }

    // options: {persist: bool, localFilePath: string}. Returns the new id, ""
    // for empty text.
    function addMessage(text: string, role: string, options): string {
        if (!text || text.length === 0) return "";
        const persist = options?.persist ?? true;
        const aiMessage = root._createMessage(role, text, {
            "persist": persist,
            "localFilePath": options?.localFilePath ?? "",
            "answer": options?.answer ?? "",
        });
        root._insertMessage(aiMessage);
        if (persist) root.scheduleSave();
        // Handed back so a caller reporting on something long-running can
        // rewrite the one message instead of appending a line per update.
        return aiMessage.id;
    }

    function _createMessage(role, content, extra) {
        return aiMessageComponent.createObject(root, Object.assign({
            "id": root.idForMessage(),
            "role": role,
            "content": content,
            "rawContent": content,
            "thinking": false,
            "done": true,
        }, extra ?? {}));
    }

    function _insertMessage(message) {
        root.messageByID[message.id] = message;
        root.messageIDs = root.messageIDs.concat([message.id]);
    }

    // A string is a message id; a number is an index into messageIDs.
    function removeMessage(idOrIndex): void {
        if (root.sessionLoading) return;
        const id = typeof idOrIndex === "number" ? root.messageIDs[idOrIndex] : String(idOrIndex ?? "");
        const message = id ? root.messageByID[id] : undefined;
        if (!message) return;
        if (root._req && root._req.messageId === id) root.cancelRequest();
        if (root.pendingConfirmation?.messageId === id) root._dropConfirmation(false);
        root._setMessageIds(root.messageIDs.filter(other => other !== id));
        root._saveNow();
    }

    // Sets the text of an edited message.
    function updateMessageContent(id: string, text: string): void {
        if (root.sessionLoading) return;
        const message = root.messageByID[id];
        if (!message) return;
        root._setMessageText(message, text);
        root._saveNow();
    }

    function _setMessageText(message, text) {
        message.content = text;
        message.rawContent = text;
        message.contentRevision++;
    }

    // What a strategy sends back as an earlier reply: no thoughts, no markers.
    function historyText(message): string {
        return Sink.historyText(message?.content ?? "");
    }

    function addApiKeyAdvice(model) {
        if (!model) return;
        root.addMessage(
            Translation.tr('To set an API key, pass it with the %4 command\n\nTo view the key, pass "get" with the command<br/>\n\n### For %1:\n\n**Link**: %2\n\n%3')
                .arg(model.name).arg(model.key_get_link).arg(model.key_get_description ?? Translation.tr("<i>No further instruction provided</i>")).arg("/key"),
            Ai.interfaceRole
        );
    }

    function getModel() {
        return models[currentModelId];
    }

    // Choosing the setup entry by hand starts the walkthrough and leaves the
    // working model alone, which is why setModel refuses it. This is the other
    // way in: the walkthrough has been followed as far as it goes and local AI
    // is the answer, it simply has no model yet. Selecting it keeps the picker
    // on local AI and lets its description carry the remaining step.
    function selectOllamaSetupEntry() {
        if (!root.models[root.ollamaSetupModelId]) return;
        Persistent.states.ai.model = root.ollamaSetupModelId;
    }

    function setModel(modelId, feedback = true, setPersistentState = true, keyAdvice = feedback) {
        if (!modelId) modelId = ""
        modelId = modelId.toLowerCase()
        if (modelId === "gemini") {
            modelId = "gemini-flash-latest";
        }
        modelId = root.retiredModels[modelId] ?? modelId
        // Plan models and the Gemini catalog are switched to before they are
        // listed, so the check below on the listed entry would miss them.
        if (Config.options?.policies?.ai === 2 && root._isOnlineModelId(modelId)) {
            root.addMessage(
                Translation.tr("Only local models are allowed right now. To use online models, set AI to Yes in Settings > Interface > Left Sidebar."),
                root.interfaceRole,
                { "persist": feedback }
            );
            return;
        }
        // An approval asked for under another model no longer applies.
        if (root.pendingConfirmation && modelId !== root.currentModelId) root._dropConfirmation();
        // The setup entry is a prompt wearing a model's clothes. Picking it
        // starts the walkthrough and leaves the working model in place, so a
        // user who was mid-conversation does not lose the model answering it.
        if (modelId === root.ollamaSetupModelId) {
            root.startOllamaWalkthrough();
            return;
        }
        // The entry for a signed-in plan is a door rather than a model: it
        // stands in for the plan while its models are put away, so opening it
        // lands on the plan's first model.
        for (const fmt of Object.keys(root.cliPlans)) {
            if (modelId === root.cliPlans[fmt].setupId && root.cliReady(fmt)) {
                root.setModel(root.cliPlans[fmt].firstPick, feedback, setPersistentState, keyAdvice);
                return;
            }
        }
        // A plan's own models are absent from the picker until that plan is in
        // use, so a switch into one writes the selection and lets the models
        // follow it in rather than failing the membership check below.
        const wantedPlan = root.planFormatFor(modelId);
        if (wantedPlan !== "" && root.cliReady(wantedPlan) && root.cliPlanModels[wantedPlan][modelId] === undefined)
            modelId = root._planSuccessor(wantedPlan, modelId);
        if (wantedPlan !== "" && root.cliReady(wantedPlan) && !root.models[modelId]) {
            if (setPersistentState) {
                Persistent.states.ai.model = modelId;
                root.restoreThinkingLevelForModel(modelId);
            }
            if (feedback) root.addMessage(Translation.tr("Model set to %1").arg(root.cliPlanModels[wantedPlan][modelId].name), root.interfaceRole);
            return;
        }
        if (root.isGeminiApiModel(modelId)) {
            root.syncGeminiApiModels(modelId);
        }
        if (models[modelId] !== undefined) {
            const model = models[modelId]
            // See if policy prevents online models
            if (Config.options.policies.ai === 2 && !model.endpoint.includes("localhost")) {
                root.addMessage(
                    Translation.tr("Only local models are allowed right now. To use online models, set AI to Yes in Settings > Interface > Left Sidebar."),
                    root.interfaceRole,
                    { "persist": feedback }
                );
                return;
            }
            // Only a real selection carries its reasoning level along; a
            // re-apply must not hand this model's level to the active one.
            if (setPersistentState) {
                Persistent.states.ai.model = modelId;
                root.restoreThinkingLevelForModel(modelId, model);
            }
            if (feedback) root.addMessage(Translation.tr("Model set to %1").arg(model.name), root.interfaceRole);
            // Advice belongs to somebody who just chose this model. Callers
            // passing keyAdvice=false are re-applying a model the user already
            // had, and a silent re-apply that answers with a page about API
            // keys reads as though it is talking about whatever just happened.
            if (keyAdvice && model.requires_key) {
                // If key not there show advice
                if (root.apiKeysLoaded && (!root.apiKeys[model.key_id] || root.apiKeys[model.key_id].length === 0)) {
                    root.addApiKeyAdvice(model)
                }
            }
        } else {
            if (feedback) root.addMessage(Translation.tr("Invalid model. Supported: \n```\n") + modelList.join("\n```\n```\n") + "\n```", Ai.interfaceRole)
        }
    }

    function setTool(tool) {
        if (root.availableTools.indexOf(tool) === -1) {
            root.addMessage(Translation.tr("Invalid tool. Supported tools:\n- %1").arg(root.availableTools.join("\n- ")), root.interfaceRole);
            return false;
        }
        Config.options.ai.tool = tool;
        return true;
    }
    
    function responseStyleId(temp): string {
        const t = (temp !== undefined) ? temp : root.temperature;
        if (t <= 0.35) return "precise";
        if (t <= 0.65) return "balanced";
        return "creative";
    }

    function getResponseStyleName(temp) {
        switch (root.responseStyleId(temp)) {
        case "precise":
            return Translation.tr("Precise");
        case "balanced":
            return Translation.tr("Balanced");
        default:
            return Translation.tr("Creative");
        }
    }

    function cycleResponseStyle(): void {
        const next = { "precise": 0.5, "balanced": 0.8, "creative": 0.2 };
        root.setTemperature(next[root.responseStyleId()], false);
    }

    function getTemperature() {
        return root.temperature;
    }

    function setResponseStyle(style) {
        const norm = (style || "").toString().trim().toLowerCase();
        if (norm === "precise" || norm === "code" || norm === "exact") {
            root.setTemperature(0.2);
        } else if (norm === "balanced" || norm === "default" || norm === "normal") {
            root.setTemperature(0.5);
        } else if (norm === "creative" || norm === "ideas" || norm === "imaginative") {
            root.setTemperature(0.8);
        } else {
            const num = parseFloat(style);
            if (!isNaN(num)) {
                root.setTemperature(num);
            } else {
                root.addMessage(Translation.tr("Invalid style '%1'. Valid styles: precise, balanced, creative").arg(style), Ai.interfaceRole);
            }
        }
    }

    function setTemperature(value, feedback = true) {
        if (isNaN(value) || value < 0 || value > 2) {
            if (feedback) root.addMessage(Translation.tr("Temperature must be between 0 and 2"), Ai.interfaceRole);
            return;
        }
        Persistent.states.ai.temperature = value;
        root.temperature = value;
        if (!feedback) return;
        const styleName = root.getResponseStyleName(value);
        if (root.currentModel?.sendTemperature === false) {
            root.addMessage(Translation.tr("Response style set to %1 (%2). (Note: %3 uses default sampling; adjust thinking level with /think instead)").arg(styleName).arg(value).arg(root.currentModel.name), Ai.interfaceRole);
        } else {
            root.addMessage(Translation.tr("Response style set to %1 (%2)").arg(styleName).arg(value), Ai.interfaceRole);
        }
    }

    function setApiKey(key) {
        const model = models[currentModelId];
        if (!model.requires_key) {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
            return;
        }
        if (!key || key.length === 0) {
            const model = models[currentModelId];
            root.addApiKeyAdvice(model)
            return;
        }
        KeyringStorage.setNestedField(["apiKeys", model.key_id], key.trim());
        root.addMessage(Translation.tr("API key set for %1").arg(model.name), Ai.interfaceRole);
    }

    function printApiKey() {
        const model = models[currentModelId];
        if (model.requires_key) {
            const key = root.apiKeys[model.key_id];
            if (key) {
                root.addMessage(Translation.tr("API key:\n\n```txt\n%1\n```").arg(key), Ai.interfaceRole, { "persist": false });
            } else {
                root.addMessage(Translation.tr("No API key set for %1").arg(model.name), Ai.interfaceRole);
            }
        } else {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
        }
    }

    function printTemperature() {
        const styleName = root.getResponseStyleName(root.temperature);
        if (root.currentModel?.sendTemperature === false) {
            root.addMessage(Translation.tr("Response style: %1 (%2) (Not used by %3; adjust thinking level with /think instead)").arg(styleName).arg(root.temperature).arg(root.currentModel.name), Ai.interfaceRole);
        } else {
            root.addMessage(Translation.tr("Response style: %1 (%2)").arg(styleName).arg(root.temperature), Ai.interfaceRole);
        }
    }

    function printResponseStyle() {
        root.printTemperature();
    }

    function getModelThinkingLevels(model) {
        const m = model || root.currentModel;
        const fmt = m?.api_format || "";
        const mid = (m?.model || m?.name || "").toLowerCase();
        // Generic fallback for any other models, and for local Ollama
        // models, which speak the OpenAI format but take only these.
        const generic = () => [
            { id: "auto", name: Translation.tr("Auto"), desc: Translation.tr("Model default reasoning") },
            { id: "low", name: Translation.tr("Low"), desc: Translation.tr("Light reasoning effort") },
            { id: "medium", name: Translation.tr("Medium"), desc: Translation.tr("Standard balanced reasoning") },
            { id: "high", name: Translation.tr("High"), desc: Translation.tr("Deep reasoning effort") },
        ];
        if ((m?.endpoint ?? "").includes("localhost:11434")) return generic();

        // Claude (Claude Code CLI, Anthropic API, or Claude-named models)
        if (fmt === "claude-code" || fmt === "anthropic" || mid.includes("claude")) {
            return [
                { id: "auto", name: Translation.tr("Auto"), desc: Translation.tr("Model default reasoning budget") },
                { id: "low", name: Translation.tr("Low"), desc: Translation.tr("Quick reasoning for routine edits and questions") },
                { id: "medium", name: Translation.tr("Medium"), desc: Translation.tr("Balanced reasoning for standard coding and debugging") },
                { id: "high", name: Translation.tr("High"), desc: Translation.tr("Deep reasoning for complex logic and tricky bugs") },
                { id: "extra", name: Translation.tr("Extra"), desc: Translation.tr("Extended thinking across large contexts and refactors") },
                { id: "max", name: Translation.tr("Max"), desc: Translation.tr("Maximum reasoning budget for exhaustive verification") },
                { id: "ultracode", name: Translation.tr("UltraCode"), desc: Translation.tr("Full extended thinking & autonomous multi-pass reasoning") },
            ];
        }

        // Codex plan models: the levels the catalog lists for that model.
        const codexEfforts = fmt === "codex-cli" ? root.codexEfforts(m?.model ?? "") : [];
        if (codexEfforts.length > 0) {
            const rows = [
                { id: "none", name: Translation.tr("None"), desc: Translation.tr("Disable reasoning for instantaneous output") },
                { id: "minimal", name: Translation.tr("Minimal"), desc: Translation.tr("Minimal thinking for lowest latency") },
                { id: "low", name: Translation.tr("Low"), desc: Translation.tr("Light reasoning with high throughput") },
                { id: "medium", name: Translation.tr("Medium"), desc: Translation.tr("Standard balanced reasoning effort") },
                { id: "high", name: Translation.tr("High"), desc: Translation.tr("Deep reasoning for complex math and architecture") },
                { id: "extra", name: Translation.tr("Extra"), desc: Translation.tr("Extended thinking across large contexts and refactors") },
                { id: "max", name: Translation.tr("Max"), desc: Translation.tr("Maximum reasoning budget for exhaustive verification") },
                { id: "ultracode", name: Translation.tr("UltraCode"), desc: Translation.tr("Full extended thinking & autonomous multi-pass reasoning") },
            ];
            const offered = codexEfforts.map(effort => root.codexEffortLevels[effort]);
            return [{ id: "auto", name: Translation.tr("Auto"), desc: Translation.tr("Model default reasoning effort") }]
                .concat(rows.filter(row => offered.includes(row.id)));
        }

        // Codex (Codex CLI or OpenAI reasoning models)
        if (fmt === "codex-cli" || fmt === "openai" || mid.includes("codex") || mid.startsWith("o1") || mid.startsWith("o3") || mid.startsWith("gpt-5")) {
            return [
                { id: "auto", name: Translation.tr("Auto"), desc: Translation.tr("Model default reasoning effort") },
                { id: "none", name: Translation.tr("None"), desc: Translation.tr("Disable reasoning for instantaneous output") },
                { id: "low", name: Translation.tr("Low"), desc: Translation.tr("Light reasoning with high throughput") },
                { id: "medium", name: Translation.tr("Medium"), desc: Translation.tr("Standard balanced reasoning effort") },
                { id: "high", name: Translation.tr("High"), desc: Translation.tr("Deep reasoning for complex math and architecture") },
                { id: "extra", name: Translation.tr("Extra"), desc: Translation.tr("Maximum reasoning effort for hard problems") },
            ];
        }

        // Gemini (Gemini API or Antigravity CLI)
        if (fmt === "gemini" || fmt === "antigravity-cli" || mid.includes("gemini")) {
            return [
                { id: "auto", name: Translation.tr("Auto"), desc: Translation.tr("Model default dynamic reasoning") },
                { id: "minimal", name: Translation.tr("Minimal"), desc: Translation.tr("Minimal thinking for lowest latency") },
                { id: "low", name: Translation.tr("Low"), desc: Translation.tr("Standard reasoning effort") },
                { id: "medium", name: Translation.tr("Medium"), desc: Translation.tr("Balanced reasoning for coding and analysis") },
                { id: "high", name: Translation.tr("High"), desc: Translation.tr("Deep thinking and complex mathematics") },
            ];
        }

        return generic();
    }

    function canonicalModelId(modelId) {
        const id = (modelId || root.currentModelId || "").toLowerCase();
        return root.retiredModels[id] ?? id;
    }

    function getModelObject(modelId) {
        if (!modelId) return root.currentModel;
        const id = modelId.toLowerCase();
        const norm = root.canonicalModelId(id);
        if (root.models[norm]) return root.models[norm];
        if (root.models[id]) return root.models[id];
        if (root.isGeminiApiModel(norm)) return root.geminiApiCatalog[norm] ?? root.models["gemini"];
        if (root.isGeminiApiModel(id)) return root.geminiApiCatalog[id] ?? root.models["gemini"];
        for (const fmt of Object.keys(root.cliPlanModels)) {
            if (root.cliPlanModels[fmt][norm]) {
                const entry = root.cliPlanModels[fmt][norm];
                return { api_format: fmt, model: entry.alias || norm, name: entry.name, thinkingLevel: entry.thinkingLevel || "" };
            }
            if (root.cliPlanModels[fmt][id]) {
                const entry = root.cliPlanModels[fmt][id];
                return { api_format: fmt, model: entry.alias || id, name: entry.name, thinkingLevel: entry.thinkingLevel || "" };
            }
        }
        return root.currentModel;
    }

    function getStoredThinkingLevel(modelId) {
        const id = (modelId || root.currentModelId || "").toLowerCase();
        const norm = root.canonicalModelId(id);
        const map = Persistent.states?.ai?.modelThinkingLevels ?? ({});
        if (map[norm] !== undefined) return map[norm];
        if (map[id] !== undefined) return map[id];
        if (norm === "gemini-flash-latest" && map["gemini"] !== undefined) return map["gemini"];
        if (norm === "gemini" && map["gemini-flash-latest"] !== undefined) return map["gemini-flash-latest"];
        const legacyLevel = (Persistent.states?.ai?.thinkingLevel || "").toLowerCase();
        if (legacyLevel === "ultracode" && (norm === "claude" || norm.startsWith("claude-"))) {
            return "ultracode";
        }
        return undefined;
    }

    function restoreThinkingLevelForModel(modelId, targetModelObj) {
        const id = (modelId || root.currentModelId || "").toLowerCase();
        const norm = root.canonicalModelId(id);
        const modelObj = targetModelObj || root.getModelObject(norm);

        const stored = root.getStoredThinkingLevel(norm);
        const defaultLevel = (modelObj?.thinkingLevel || "").toLowerCase();

        let targetLevel = "";
        if (stored !== undefined && stored !== null) {
            const storedNorm = stored.toString().trim().toLowerCase();
            if (storedNorm === "" || storedNorm === "auto" || storedNorm === "default" || storedNorm === "off") {
                targetLevel = "";
            } else {
                const validLevels = root.getModelThinkingLevels(modelObj).map(item => item.id.toLowerCase());
                if (validLevels.includes(storedNorm)) {
                    targetLevel = storedNorm;
                } else {
                    targetLevel = defaultLevel === "auto" ? "" : defaultLevel;
                }
            }
        } else {
            targetLevel = defaultLevel === "auto" ? "" : defaultLevel;
        }

        root.thinkingLevel = targetLevel;
        try {
            if (Persistent.states?.ai) {
                Persistent.states.ai.thinkingLevel = targetLevel;
            }
        } catch (e) {
            console.warn("[Ai] Failed to update active thinkingLevel in persistent state:", e);
        }
    }

    function setThinkingLevel(value, feedback = true): void {
        const norm = (value || "").toString().trim().toLowerCase();
        const modelKey = root.canonicalModelId(root.currentModelId);
        const validItems = root.getModelThinkingLevels(root.currentModel);
        const validIds = validItems.map(item => item.id.toLowerCase());

        if (norm === "off" || norm === "default" || norm === "auto" || norm === "") {
            try {
                if (Persistent.states?.ai) {
                    const next = Object.assign({}, Persistent.states.ai.modelThinkingLevels ?? {});
                    next[modelKey] = "";
                    if (modelKey === "gemini-flash-latest") next["gemini"] = "";
                    else if (modelKey === "gemini") next["gemini-flash-latest"] = "";
                    Persistent.states.ai.modelThinkingLevels = next;
                    Persistent.states.ai.thinkingLevel = "";
                }
            } catch (e) {
                console.warn("[Ai] Failed to clear thinkingLevel in persistent state:", e);
            }
            root.thinkingLevel = "";
            if (feedback) root.addMessage(Translation.tr("Thinking level set to default (%1)").arg(root.defaultThinkingLevelLabel()), Ai.interfaceRole);
        } else if (validIds.includes(norm)) {
            try {
                if (Persistent.states?.ai) {
                    const next = Object.assign({}, Persistent.states.ai.modelThinkingLevels ?? {});
                    next[modelKey] = norm;
                    if (modelKey === "gemini-flash-latest") next["gemini"] = norm;
                    else if (modelKey === "gemini") next["gemini-flash-latest"] = norm;
                    Persistent.states.ai.modelThinkingLevels = next;
                    Persistent.states.ai.thinkingLevel = norm;
                }
            } catch (e) {
                console.warn("[Ai] Failed to save thinkingLevel to persistent state:", e);
            }
            root.thinkingLevel = norm;
            if (feedback) root.addMessage(Translation.tr("Thinking level set to %1").arg(root.thinkingLevelName(norm)), Ai.interfaceRole);
        } else {
            if (feedback) root.addMessage(Translation.tr("Invalid thinking level '%1'. Valid levels: %2").arg(value).arg(validIds.join(", ")), Ai.interfaceRole);
        }
    }

    // Display name of a level id, translated.
    function thinkingLevelName(id: string): string {
        const norm = String(id ?? "").trim().toLowerCase();
        if (norm === "" || norm === "auto" || norm === "default" || norm === "off") return Translation.tr("Auto");
        const names = {
            "minimal": Translation.tr("Minimal"),
            "low": Translation.tr("Low"),
            "medium": Translation.tr("Medium"),
            "high": Translation.tr("High"),
            "extra": Translation.tr("Extra"),
            "max": Translation.tr("Max"),
            "ultracode": Translation.tr("UltraCode"),
            "none": Translation.tr("None"),
        };
        return names.hasOwnProperty(norm) ? names[norm] : norm.charAt(0).toUpperCase() + norm.slice(1);
    }

    function defaultThinkingLevelLabel() {
        const level = root.currentModel?.thinkingLevel;
        return level ? Translation.tr("%1 (model default)").arg(root.thinkingLevelName(level)) : Translation.tr("Auto (model default)");
    }

    function printThinkingLevel() {
        const current = root.thinkingLevel || root.defaultThinkingLevelLabel();
        root.addMessage(Translation.tr("Thinking level: %1").arg(current), Ai.interfaceRole);
    }

    function _resetTokenCount() {
        root.tokenCount.input = -1;
        root.tokenCount.output = -1;
        root.tokenCount.total = -1;
    }

    // A CLI strategy resumes its session on every request; keeping the id
    // across a clear would quietly thread the old conversation back in.
    function _resetCliSessions() {
        for (const strategy of Object.values(root.apiStrategies)) {
            if (strategy?.isCliStrategy) strategy.sessionId = "";
        }
    }

    function clearMessages(): void {
        root._bumpLoad();
        root._abandonRequest();
        root._dropConfirmation(false);
        root._setMessageIds([]);
        root._resetTokenCount();
        root._resetCliSessions();
        root._saveNow();
    }

    function _setMessageIds(next) {
        const previous = root.messageIDs;
        root.messageIDs = next;
        const kept = new Set(next);
        const dead = [];
        for (const id of previous) {
            if (kept.has(id)) continue;
            dead.push(root.messageByID[id]);
            delete root.messageByID[id];
        }
        root._buryAll(dead);
    }

    // ── Graveyard ──────────────────────────────────────────────────
    // Views release their delegates with deleteLater, so objects that left a
    // list are destroyed a while later rather than at once.
    property var _graveyard: []

    function _bury(object) {
        root._buryAll([object]);
    }

    function _buryAll(objects) {
        const dead = objects.filter(object => object);
        if (dead.length === 0) return;
        root._graveyard = root._graveyard.concat(dead);
        reaper.restart();
    }

    Timer {
        id: reaper
        interval: 500
        repeat: false
        onTriggered: {
            const dead = new Set(root._graveyard);
            root._graveyard = [];
            for (const object of dead) {
                try {
                    object.destroy();
                } catch (e) {}
            }
        }
    }

    // ── Requests ───────────────────────────────────────────────────
    // One request at a time. Every callback carries the request it belongs to
    // and does nothing once that request is no longer root._req.
    property var _req: null
    property int _requestCounter: 0
    property int _confirmationCounter: 0
    property var _pendingKills: []
    property var _postResponseHook: null
    readonly property string _home: Quickshell.env("HOME") || ""
    readonly property string _stateHome: Quickshell.env("XDG_STATE_HOME") || (root._home + "/.local/state")
    readonly property var _dirs: ({
        "antigravity": root.antigravityDir,
        "codex": root._stateHome + "/quickshell/ai/codex-cli",
        "home": root._home,
        "runtime": Quickshell.env("XDG_RUNTIME_DIR") || "/tmp",
    })
    readonly property string _aiScriptsDir: CF.FileUtils.trimFileProtocol(String(Directories.scriptPath)) + "/ai"
    readonly property var _scripts: ({
        "filter": root._aiScriptsDir + "/stream-diff-filter.py",
        "runRequest": root._aiScriptsDir + "/run-request.sh",
    })
    readonly property var _sinkHost: ({
        "isActive": req => req === root._req && !req.finalized,
        "now": () => Date.now(),
        "scheduleFlush": req => root._scheduleFlush(req),
        "setSessionId": (req, id) => {
            if (req.strategy) req.strategy.sessionId = id;
        },
        "recordFunctionCall": (req, call) => root._recordFunctionCall(req, call),
        "uploadedFile": (req, uri, mime) => root._recordUploadedFile(req, uri, mime),
        "actionFallback": Translation.tr("Action"),
    })

    Component {
        id: requestProcessComponent
        Process {
            id: requestProc
            property var req: null
            // Lines are only queued here: a backlog arrives in one burst, and
            // anything slower per line would stall the shell for its length.
            stdout: SplitParser {
                onRead: line => root._onRequestLine(requestProc.req, line)
            }
            onStarted: root._onProcessStarted(requestProc, requestProc.req)
            onExited: (exitCode, exitStatus) => root._onRequestExited(requestProc, requestProc.req, exitCode)
            onRunningChanged: {
                if (!running) root._onProcessNotRunning(requestProc, requestProc.req);
            }
        }
    }

    Component {
        id: commandProcessComponent
        Process {
            id: commandProc
            property var req: null
            stdout: StdioCollector {
                waitForEnd: true
                onStreamFinished: root._onCommandOutput(commandProc.req, this.text)
            }
            onStarted: root._onProcessStarted(commandProc, commandProc.req)
            onExited: (exitCode, exitStatus) => root._onRequestExited(commandProc, commandProc.req, exitCode)
            onRunningChanged: {
                if (!running) root._onProcessNotRunning(commandProc, commandProc.req);
            }
        }
    }

    Timer {
        id: drainTimer
        interval: 0
        repeat: false
        onTriggered: root._drain()
    }

    Timer {
        id: flushTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (root._req) root._flushReq(root._req);
        }
    }

    Timer {
        id: stopWatchdog
        interval: 5000
        repeat: false
        onTriggered: {
            const req = root._req;
            if (req && req.stopped && !req.finalized) root._finalize(req);
        }
    }

    // Sends the KILL that follows every Stop's TERM, whether or not the leader
    // is still there: the group can outlive it.
    Timer {
        id: groupKillTimer
        interval: 500
        repeat: true
        running: root._pendingKills.length > 0
        onTriggered: {
            const now = Date.now();
            const keep = [];
            for (const entry of root._pendingKills) {
                if (entry.due <= now) Quickshell.execDetached(["kill", "-KILL", "--", "-" + entry.pgid]);
                else keep.push(entry);
            }
            root._pendingKills = keep;
        }
    }

    function _newRequest(kind, message, strategy) {
        root._requestCounter++;
        const model = root.currentModel;
        return {
            "id": root._requestCounter,
            "kind": kind,
            "messageId": message.id,
            "message": message,
            "strategy": strategy,
            "modelId": root.currentModelId,
            "apiFormat": model?.api_format ?? "",
            "grant": null,
            "regenerate": false,
            "mode": AiModes.current,
            "proc": null,
            "pgid": null,
            "killSent": false,
            "cancelPending": false,
            "stopped": false,
            "started": false,
            "failedToStart": false,
            "lineQueue": [],
            "qHead": 0,
            "exited": false,
            "exitCode": null,
            "stderrTail": "",
            "finalized": false,
            "sink": null,
            "buf": null,
            "stdin": "",
            "startTime": Date.now(),
            "attachmentMessageId": "",
            "functionCall": null,
            "confirmationDraft": null,
            "loginLapsed": false,
            "searchRefused": false,
            "output": "",
        };
    }

    function _msgAlive(req) {
        return Boolean(req && req.message && root.messageByID[req.messageId] === req.message);
    }

    function _guessMime(path) {
        const ext = (String(path).split("/").pop().split(".").pop() || "").toLowerCase();
        const types = {
            "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp",
            "gif": "image/gif", "pdf": "application/pdf",
        };
        return types[ext] ?? "";
    }

    function _resolvedThinkingLevel(model) {
        const level = String(root.thinkingLevel || model?.thinkingLevel || "").toLowerCase();
        return level === "auto" ? "" : level;
    }

    // Message ids whose function call has no later output message of the same
    // function. Gemini and Mistral refuse a call turn that has no answer.
    function _unansweredCalls(messages) {
        const unanswered = Object.create(null);
        const answers = Object.create(null);
        for (let i = messages.length - 1; i >= 0; i--) {
            const message = messages[i];
            if (!message.functionName) continue;
            if (message.functionCall !== undefined && message.functionCall !== null) {
                if ((answers[message.functionName] ?? 0) > 0) answers[message.functionName]--;
                else unanswered[message.id] = true;
            } else {
                answers[message.functionName] = (answers[message.functionName] ?? 0) + 1;
            }
        }
        return unanswered;
    }

    // options: {attachment: null | {path, mime, messageId}, grant, regenerate}
    function _startModelRequest(options) {
        const opts = options ?? {};
        const policy = Config.options?.policies?.ai ?? 0;
        if (policy === 0) return false;
        if (policy === 2 && root._isOnlineModelId(root.currentModelId)) {
            root.addMessage(
                Translation.tr("Only local models are allowed right now. To use online models, set AI to Yes in Settings > Interface > Left Sidebar."),
                root.interfaceRole
            );
            return false;
        }
        const model = root.currentModel;
        const strategy = root.currentApiStrategy;
        if (!model || !strategy) {
            root.startOllamaWalkthrough();
            return false;
        }
        if (model.requires_key && !KeyringStorage.loaded) KeyringStorage.fetchKeyringData();
        const history = root.messageIDs.map(id => root.messageByID[id])
            .filter(message => message && message.role !== root.interfaceRole);
        const unanswered = root._unansweredCalls(history);

        const message = root._createMessage("assistant", "", {
            "model": root.currentModelId,
            "thinking": true,
            "done": false,
        });
        root._insertMessage(message);

        const req = root._newRequest("model", message, strategy);
        req.grant = opts.grant ?? null;
        req.regenerate = opts.regenerate === true;
        req.attachmentMessageId = opts.attachment?.messageId ?? "";
        root._req = req;
        root.requestState = "starting";
        req.sink = Sink.createSink(req, root._sinkHost);

        const apiKey = model.requires_key ? (root.apiKeys?.[model.key_id] ?? "") : "";
        let built = null;
        let failure = "";
        try {
            built = strategy.buildRequest({
                "requestId": req.id,
                "model": model,
                "messages": history,
                "unansweredCalls": unanswered,
                "systemPrompt": root.systemPrompt,
                "temperature": root.temperature,
                "tools": root.tools[model.api_format]?.[root.effectiveTool] ?? [],
                "thinkingLevel": root._resolvedThinkingLevel(model),
                "mode": req.mode,
                "grant": req.grant,
                "attachment": opts.attachment ? { "path": opts.attachment.path, "mime": opts.attachment.mime } : null,
                "regenerate": req.regenerate,
                "apiKey": apiKey,
                "scripts": root._scripts,
                "dirs": root._dirs,
            });
            // After the build: strategies carry values from it into the state.
            req.sink.state = strategy.newState();
        } catch (e) {
            failure = e?.message ?? String(e);
        }
        if (!built || !Array.isArray(built.argv) || built.argv.length === 0) {
            req.sink.error(Translation.tr("Error starting request: %1").arg(failure || model.name));
            root._finalize(req);
            return true;
        }

        const env = Object.assign({}, built.env ?? {});
        if (model.requires_key) env[root.apiKeyEnvVarName] = apiKey;
        req.stdin = typeof built.stdin === "string" ? built.stdin : "";
        const command = ["setsid", "bash", root._scripts.runRequest]
            .concat((built.options ?? []).map(String), ["--"], built.argv.map(String));
        req.proc = requestProcessComponent.createObject(root, {
            "command": command,
            "environment": env,
            "stdinEnabled": req.stdin.length > 0,
        });
        root._launch(req);
        return true;
    }

    // Runs a command the model asked for, as a request of its own: Stop ends
    // it, and its output reaches QML once, already cut to its last 64 KB.
    function _startCommandRequest(command) {
        root._saveNow();
        const output = root._createCommandOutputMessage(command);
        root._insertMessage(output);
        const req = root._newRequest("command", output, null);
        root._req = req;
        root.requestState = "starting";
        req.proc = commandProcessComponent.createObject(root, {
            "command": ["setsid", "bash", root._scripts.runRequest, "--workdir", root._home,
                "--tail-bytes", "65536", "--timeout", "120", "--", "bash", "-c", command],
        });
        root._launch(req);
    }

    // The request object is handed over by assignment: initial properties
    // pass through a QVariantMap, which would copy it.
    function _launch(req) {
        if (!req.proc) {
            req.failedToStart = true;
            if (req.kind === "model") req.sink.error(Translation.tr("Error starting request: %1").arg("setsid"));
            root._finalize(req);
            return;
        }
        req.proc.req = req;
        req.proc.running = true;
    }

    function _onProcessStarted(proc, req) {
        if (!req) return;
        req.started = true;
        const pid = Number(proc.processId);
        req.pgid = Number.isInteger(pid) && pid > 1 ? pid : null;
        if (req !== root._req || req.cancelPending) {
            req.stdin = "";
            proc.stdinEnabled = false;
            root._killGroup(req);
            return;
        }
        if (req.stdin.length > 0) proc.write(req.stdin);
        req.stdin = "";
        // Closing stdin sends EOF once the written data is flushed.
        proc.stdinEnabled = false;
        if (root.requestState === "starting") root.requestState = "streaming";
    }

    function _onRequestLine(req, line) {
        if (req !== root._req || req.stopped || line.length === 0) return;
        req.lineQueue.push(line);
        if (!drainTimer.running) drainTimer.start();
    }

    function _onCommandOutput(req, text) {
        if (req === root._req && !req.stopped) req.output = text;
    }

    function _onRequestExited(proc, req, exitCode) {
        root._bury(proc);
        if (!req) return;
        req.exited = true;
        if (req.exitCode === null) req.exitCode = exitCode;
        if (req !== root._req || req.finalized) return;
        if (req.kind === "command" || req.stopped || req.qHead >= req.lineQueue.length) root._finalize(req);
        else if (!drainTimer.running) drainTimer.start();
    }

    // Quickshell reports a process that never started only through running.
    function _onProcessNotRunning(proc, req) {
        if (!req || req.started) return;
        req.failedToStart = true;
        root._bury(proc);
        if (req !== root._req || req.finalized) return;
        if (req.kind === "model" && !req.stopped)
            req.sink.error(Translation.tr("Error starting request: %1").arg(proc.command[0] ?? ""));
        root._finalize(req);
    }

    // Parses queued lines for at most 8 ms, then yields to the event loop.
    function _drain() {
        const req = root._req;
        if (!req || req.stopped || req.finalized) return;
        const deadline = Date.now() + 8;
        while (req.qHead < req.lineQueue.length) {
            const line = req.lineQueue[req.qHead];
            req.lineQueue[req.qHead] = undefined;
            req.qHead++;
            root._handleLine(req, line);
            if (req !== root._req || req.stopped) return;
            if (Date.now() >= deadline) break;
        }
        if (req.qHead >= req.lineQueue.length) {
            req.lineQueue = [];
            req.qHead = 0;
            if (req.exited) root._finalize(req);
            return;
        }
        if (req.qHead > 4096) {
            req.lineQueue = req.lineQueue.slice(req.qHead);
            req.qHead = 0;
        }
        drainTimer.restart();
    }

    function _handleLine(req, line) {
        if (line.startsWith('{"event":"cli_exit"')) {
            try {
                const exit = JSON.parse(line);
                if (exit.event === "cli_exit") {
                    if (Number.isInteger(exit.code)) req.exitCode = exit.code;
                    req.stderrTail = String(exit.stderr ?? "");
                    return;
                }
            } catch (e) {}
        }
        try {
            req.strategy.parseLine(line, req.sink);
        } catch (e) {
            console.warn("[Ai] Could not parse a response line:", e);
            req.sink.raw(line);
        }
    }

    function _scheduleFlush(req) {
        if (req !== root._req || flushTimer.running) return;
        const length = root._msgAlive(req) ? req.message.content.length : 0;
        flushTimer.interval = Math.max(50, Math.min(250, Math.round(length / 400)));
        flushTimer.start();
    }

    function _flushReq(req) {
        if (!req.buf) return;
        if (!root._msgAlive(req)) {
            Sink.discard(req.buf);
            return;
        }
        const usage = Sink.flush(req.buf, req.message);
        if (usage) {
            root.tokenCount.input = usage.input;
            root.tokenCount.output = usage.output;
            root.tokenCount.total = usage.total;
        }
    }

    function _recordFunctionCall(req, call) {
        if (req.functionCall || !root._msgAlive(req)) return false;
        const message = req.message;
        message.functionName = call.name;
        message.functionArgs = call.args;
        message.functionCallId = call.id;
        message.functionThoughtSignature = call.thoughtSignature;
        message.functionCall = { "name": call.name, "args": call.args, "id": call.id };
        req.functionCall = { "name": call.name, "args": call.args };
        return true;
    }

    // The uploaded file belongs to the user turn that attached it, so later
    // requests send it with that turn.
    function _recordUploadedFile(req, uri, mime) {
        const target = root.messageByID[req.attachmentMessageId] ?? (root._msgAlive(req) ? req.message : null);
        if (!target) return;
        target.fileUri = uri;
        target.fileMimeType = mime;
    }

    function _killGroup(req) {
        const pgid = req?.pgid;
        if (!Number.isInteger(pgid) || pgid <= 1 || req.killSent) return;
        req.killSent = true;
        Quickshell.execDetached(["kill", "-TERM", "--", "-" + pgid]);
        root._pendingKills = root._pendingKills.concat([{ "pgid": pgid, "due": Date.now() + 3000 }]);
    }

    function cancelRequest(): void {
        const req = root._req;
        if (!req || req.stopped || req.finalized) return;
        req.stopped = true;
        root.requestState = "stopping";
        drainTimer.stop();
        req.lineQueue = [];
        req.qHead = 0;
        stopWatchdog.restart();
        root._stopProcess(req);
    }

    // A process that has not started yet is killed by its own start.
    function _stopProcess(req) {
        if (req.started) root._killGroup(req);
        else req.cancelPending = true;
    }

    // The timers serve only the active request.
    function _detach(req) {
        if (req !== root._req) return;
        drainTimer.stop();
        flushTimer.stop();
        stopWatchdog.stop();
        root._req = null;
        root.requestState = "idle";
    }

    // Drops the active request without waiting for it; its late output is
    // ignored because it is no longer root._req.
    function _abandonRequest() {
        const req = root._req;
        if (!req) return;
        req.stopped = true;
        root._detach(req);
        if (req.buf) Sink.discard(req.buf);
        root._stopProcess(req);
        if (root._msgAlive(req)) {
            req.message.done = true;
            req.message.thinking = false;
        }
        root._runPostResponseHook();
    }

    function _runPostResponseHook() {
        const hook = root._postResponseHook;
        root._postResponseHook = null;
        if (hook) hook();
    }

    // The end of a reply, function continuations included.
    function _finishChain() {
        root._runPostResponseHook();
        root.responseFinished();
        root._saveNow();
    }

    function _finalize(req) {
        if (!req || req.finalized) return;
        if (req.kind === "command") {
            root._finalizeCommand(req);
            return;
        }
        if (req !== root._req) {
            req.finalized = true;
            return;
        }
        if (!req.stopped) {
            try {
                req.strategy.finish(req.sink, req.exitCode ?? 0, req.stderrTail ?? "");
            } catch (e) {
                console.warn("[Ai] Could not finish the response:", e);
            }
        }
        req.sink.close();
        root._flushReq(req);
        req.finalized = true;
        root._detach(req);

        const message = root._msgAlive(req) ? req.message : null;
        if (message) {
            message.rawContent = message.content;
            message.done = true;
            message.thinking = false;
        }

        // History must never hold a call without an answer.
        let call = req.functionCall;
        if (req.stopped && call) {
            if (message) root._addFunctionOutputMessage(call.name, Translation.tr("[[ Command stopped by user ]]"));
            call = null;
        }

        // A plan whose sign-in stopped working is checked again, which
        // swaps its models back for the setup entry and its Log in button
        // rather than failing every later message the same way.
        if (req.loginLapsed || req.strategy?.loginLapsed) {
            if (req.strategy) req.strategy.loginLapsed = false;
            const fmt = req.apiFormat || root.currentModel?.api_format;
            if (fmt) root.detectCli(fmt);
        }

        // Handle error responses
        if (message) {
            if (message.content.includes("API key not valid")) {
                root.addApiKeyAdvice(root.models[message.model] ?? null);
            }
            if (/^\*\*Error \d+\*\*/.test(message.content) && message.content.includes("no longer available to new users")) {
                root.addMessage(Translation.tr("This Google account can no longer use this model. Pick another one with %1.").arg("/model"), Ai.interfaceRole);
            }
        }
        if (req.searchRefused) {
            root.addMessage(Translation.tr("Web search with Gemini 3 needs a Google AI Studio project with billing turned on. Ask again without searching, or switch to Gemini 2.5 Flash with %1 if your account can still use it.").arg("/model"), Ai.interfaceRole);
        }

        if (!req.stopped && message && req.confirmationDraft && req.mode === "ask") {
            root._raiseConfirmation(Object.assign({}, req.confirmationDraft, {
                "type": "cli",
                "requestId": req.id,
                "provider": req.apiFormat,
                "modelId": req.modelId,
                "messageId": req.messageId,
                "sessionId": req.strategy?.sessionId ?? "",
            }));
        } else if (!req.stopped && message && call) {
            if (root._handleFunctionCall(req, call.name, call.args ?? {}, message)) return;
        }
        root._finishChain();
    }

    function _commandResponse(text, exitCode) {
        let body = text;
        let code = exitCode ?? 0;
        let timedOut = false;
        const trimmed = body.endsWith("\n") ? body.slice(0, -1) : body;
        const lineStart = trimmed.lastIndexOf("\n") + 1;
        const trailer = /^ms-exit (\d+) ([01])$/.exec(trimmed.slice(lineStart));
        if (trailer) {
            body = trimmed.slice(0, lineStart);
            code = Number(trailer[1]);
            timedOut = trailer[2] === "1";
        }
        if (timedOut) return body + Translation.tr("[[ Command timed out after %1 s ]]").arg(120);
        return body + `[[ Command exited with code ${code} ]]`;
    }

    function _finalizeCommand(req) {
        if (req.finalized) return;
        req.finalized = true;
        const output = root._msgAlive(req) ? req.message : null;
        const ran = !req.stopped && !req.failedToStart;
        if (output) {
            if (req.failedToStart) output.functionResponse = Translation.tr("Error starting request: %1").arg("setsid");
            else if (req.stopped) output.functionResponse = Translation.tr("[[ Command stopped by user ]]");
            else output.functionResponse = root._commandResponse(req.output, req.exitCode);
            const blocks = (output.thinkBlocks ?? []).slice();
            if (blocks.length > 0) {
                blocks[0] = Object.assign({}, blocks[0], {
                    "duration": Math.max(1, Math.round((Date.now() - req.startTime) / 1000)),
                });
                output.thinkBlocks = blocks;
            }
        }
        req.output = "";
        root._detach(req);
        if (ran && output && root._continueRequest()) return;
        root._finishChain();
    }

    // ── Function calls ─────────────────────────────────────────────
    function _createFunctionOutputMessage(name, output) {
        const content = `[[ Output of ${name} ]]` + Sink.THINK_OPEN + Sink.cleanModelText(output) + Sink.THINK_CLOSE;
        return root._createMessage("user", content, {
            "functionName": name,
            "functionResponse": output,
            "thinkBlocks": [{ "start": Date.now(), "duration": 1, "collapsed": null }],
        });
    }

    function _createCommandOutputMessage(command) {
        const record = Sink.normalizeActivity({
            "kind": "command",
            "verb": "Ran",
            "target": command,
            "copyText": command,
        }, root._sinkHost.actionFallback);
        const content = "[[ Output of run_shell_command ]]" + Sink.THINK_OPEN + "\n" + Sink.marker(0) + "\n" + Sink.THINK_CLOSE;
        return root._createMessage("user", content, {
            "functionName": "run_shell_command",
            "functionResponse": "",
            "activities": [record],
            "thinkBlocks": [{ "start": Date.now(), "duration": 0, "collapsed": null }],
        });
    }

    function _addFunctionOutputMessage(name, output) {
        root._insertMessage(root._createFunctionOutputMessage(name, String(output ?? "")));
    }

    function _continueRequest() {
        root._saveNow();
        return root._startModelRequest({});
    }

    function _configValueText(value) {
        return typeof value === "string" ? value : JSON.stringify(value);
    }

    function _applyShellConfig(name, key, value) {
        // Every call needs its answer, an unknown key included, or the next request
        // is refused or comes back empty.
        try {
            Config.setNestedValue(key, value);
            root._addFunctionOutputMessage(name, Translation.tr("Set %1 to %2.").arg(key).arg(JSON.stringify(value)));
        } catch (e) {
            root._addFunctionOutputMessage(name, `${e}`);
        }
    }

    // Returns true when it started another request; false ends the reply.
    function _handleFunctionCall(req, name, args, message) {
        const mode = AiModes.current;
        const confirm = (command) => {
            message.functionPending = true;
            root._raiseConfirmation({
                "type": "function",
                "requestId": req.id,
                "provider": req.apiFormat,
                "modelId": req.modelId,
                "messageId": message.id,
                "action": name,
                "command": command,
                "scope": "once",
            });
        };
        if (name === "switch_to_search_mode") {
            root.currentTool = "search";
            root._postResponseHook = () => { root.currentTool = "functions"; };
            root._addFunctionOutputMessage(name, Translation.tr("Switched to search mode. Continue with the user's request."));
            return root._continueRequest();
        }
        if (name === "get_shell_config") {
            root._addFunctionOutputMessage(name, JSON.stringify(CF.ObjectUtils.toPlainObject(Config.options)));
            return root._continueRequest();
        }
        if (name === "set_shell_config") {
            if (!args.key || args.value === undefined || args.value === null) {
                root._addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `key` and `value`."));
                return root._continueRequest();
            }
            const key = String(args.key);
            if (mode === "plan") {
                root._addFunctionOutputMessage(name, Translation.tr("Config change skipped: Plan mode is active."));
                return root._continueRequest();
            }
            // Commands the shell runs, model endpoints and modes, and policy
            // switches always ask, in Auto mode too.
            const sensitive = /^(apps|ai|policies)(\.|$)/.test(key);
            if (mode === "auto" && !sensitive) {
                root._applyShellConfig(name, key, args.value);
                return root._continueRequest();
            }
            confirm(key + " = " + root._configValueText(args.value));
            return false;
        }
        if (name === "run_shell_command") {
            const command = typeof args.command === "string" ? args.command : "";
            if (command.length === 0) {
                root._addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `command`."));
                return root._continueRequest();
            }
            if (mode === "auto") {
                root._startCommandRequest(command);
                return true;
            }
            if (mode === "plan") {
                root._addFunctionOutputMessage(name, Translation.tr("Command execution skipped: Plan mode is active."));
                return root._continueRequest();
            }
            message.content = message.content + `\n\n**Command execution request**\n\n\`\`\`command\n${command}\n\`\`\``;
            message.rawContent = message.content;
            confirm(command);
            return false;
        }
        root.addMessage(Translation.tr("Unknown function call: %1").arg(name), "assistant");
        return false;
    }

    // ── Confirmations ──────────────────────────────────────────────
    function _raiseConfirmation(fields) {
        root._confirmationCounter++;
        const scopes = ["once", "all"];
        root.pendingConfirmation = Object.freeze({
            "id": `confirm-${Date.now().toString(36)}-${root._confirmationCounter}`,
            "requestId": Number(fields.requestId ?? 0),
            "type": fields.type === "cli" ? "cli" : "function",
            "provider": String(fields.provider ?? ""),
            "modelId": String(fields.modelId ?? ""),
            "messageId": String(fields.messageId ?? ""),
            "action": String(fields.action ?? ""),
            "command": String(fields.command ?? ""),
            "target": String(fields.target ?? ""),
            "scope": scopes.includes(fields.scope) ? fields.scope : "once",
            "grantNote": String(fields.grantNote ?? ""),
            "sessionId": String(fields.sessionId ?? ""),
        });
        root.requestState = "awaitingConfirmation";
    }

    // Clears the pending confirmation. A function call it leaves unanswered
    // gets the rejected output unless the caller is discarding that message.
    function _dropConfirmation(addRejected = true) {
        const conf = root.pendingConfirmation;
        if (root.requestState === "awaitingConfirmation") root.requestState = "idle";
        if (!conf) return;
        root.pendingConfirmation = null;
        if (conf.type !== "function") return;
        const message = root.messageByID[conf.messageId];
        if (!message || !message.functionPending) return;
        message.functionPending = false;
        if (addRejected) root._addFunctionOutputMessage(message.functionName, Translation.tr("Command rejected by user"));
    }

    function approvePendingAction(confirmationId = root.pendingConfirmation?.id): bool {
        const conf = root.pendingConfirmation;
        const valid = conf !== null && conf.id === confirmationId
            && root.requestState === "awaitingConfirmation"
            && root.currentModelId === conf.modelId
            && (conf.type !== "cli" || (root.currentApiStrategy?.sessionId ?? "") === conf.sessionId);
        if (!valid) {
            root._dropConfirmation();
            root.addMessage(Translation.tr("This approval is out of date, so nothing was run."), root.interfaceRole);
            return false;
        }
        root.pendingConfirmation = null;
        root.requestState = "idle";
        if (conf.type === "cli") {
            // The grant lives only on the request this starts.
            return root._sendInternal(Translation.tr("Approved. Proceed."), "approved", {
                "grant": { "scope": conf.scope },
            });
        }
        const message = root.messageByID[conf.messageId];
        if (!message) {
            root._saveNow();
            return false;
        }
        message.functionPending = false;
        const args = message.functionArgs ?? {};
        if (conf.action === "run_shell_command") {
            root._startCommandRequest(typeof args.command === "string" ? args.command : conf.command);
        } else if (conf.action === "set_shell_config") {
            root._applyShellConfig(conf.action, String(args.key ?? ""), args.value);
            root._continueRequest();
        }
        return true;
    }

    function rejectPendingAction(confirmationId = root.pendingConfirmation?.id): bool {
        const conf = root.pendingConfirmation;
        root._dropConfirmation();
        const matches = Boolean(conf) && conf.id === confirmationId;
        // The decline is a message of its own, which saves.
        if (matches && conf.type === "cli") {
            root._sendInternal(Translation.tr("Declined. Do not run the command."), "declined", {});
            return true;
        }
        root._saveNow();
        return matches;
    }

    // For the buttons inside a command request block.
    function approveCommand(message) {
        const conf = root.pendingConfirmation;
        if (!conf || !message || conf.messageId !== message.id) return false;
        return root.approvePendingAction(conf.id);
    }

    function rejectCommand(message) {
        const conf = root.pendingConfirmation;
        if (!conf || !message || conf.messageId !== message.id) return false;
        return root.rejectPendingAction(conf.id);
    }

    // ── Sending ────────────────────────────────────────────────────
    // An approval or decline answer: not sendUserMessage, which would reject
    // the confirmation it answers.
    function _sendInternal(text, answer, options) {
        if (root.isGenerating || root.sessionLoading) return false;
        root.addMessage(text, "user", { "answer": answer });
        root._saveNow();
        return root._startModelRequest(options);
    }

    function sendUserMessage(text: string): bool {
        const content = String(text ?? "");
        if (content.length === 0 || root.isGenerating || root.sessionLoading) return false;
        const attachmentPath = root.pendingFilePath;
        if (attachmentPath.length > 0 && !(root.currentApiStrategy?.acceptsAttachment(attachmentPath) ?? false)) {
            root.addMessage(Translation.tr("This model can't read that file type. Remove the attachment to send your message."), root.interfaceRole, { "persist": false });
            return false;
        }
        if (root.requestState === "awaitingConfirmation") root._dropConfirmation();
        const messageId = root.addMessage(content, "user", { "localFilePath": attachmentPath });
        root.pendingFilePath = "";
        root._saveNow();
        // The setup entry names no model, so a request built from it would post
        // an empty one and come back as a failure the user cannot act on. Say
        // what local AI is still waiting for instead.
        if (root.currentModelId === root.ollamaSetupModelId) {
            root.startOllamaWalkthrough();
            return true;
        }
        // A saved local model has no object until the fetch answers, and a
        // request without one dies somewhere less explainable than here.
        // A ready list adopts the first local model and the send goes on;
        // everything else belongs to the walkthrough, whose default case
        // already remembers an unresolved ask and continues by itself.
        if (!root.currentModel && root.ollamaState === "ok") {
            const firstLocal = root.modelList.find(id => id !== root.ollamaSetupModelId && (root.models[id]?.endpoint ?? "").includes("localhost"));
            if (firstLocal) root.setModel(firstLocal);
        }
        if (!root.currentModel) {
            root.startOllamaWalkthrough();
            return true;
        }
        root._startModelRequest({
            "attachment": attachmentPath.length > 0
                ? { "path": attachmentPath, "mime": root._guessMime(attachmentPath), "messageId": messageId }
                : null,
        });
        return true;
    }

    // "" clears. file:// URLs are decoded; anything else is taken literally.
    function attachFile(pathOrUrl): bool {
        if (!pathOrUrl) {
            root.pendingFilePath = "";
            return true;
        }
        let path = String(pathOrUrl);
        if (path.startsWith("file://")) {
            path = path.slice(7);
            if (path.startsWith("localhost/")) path = path.slice(9);
            try {
                path = decodeURIComponent(path);
            } catch (e) {
                path = "";
            }
        } else if (/^[A-Za-z][A-Za-z0-9+.-]*:/.test(path)) {
            path = "";
        }
        if (!path.startsWith("/")) {
            root.addMessage(Translation.tr("Only local files can be attached."), root.interfaceRole, { "persist": false });
            return false;
        }
        root.pendingFilePath = path;
        return true;
    }

    function regenerate(idOrIndex): bool {
        if (root.isGenerating || root.sessionLoading || !root.currentModel) return false;
        const index = typeof idOrIndex === "number" ? idOrIndex : root.messageIDs.indexOf(String(idOrIndex ?? ""));
        if (index < 0 || index >= root.messageIDs.length) return false;
        const message = root.messageByID[root.messageIDs[index]];
        if (!message || message.role !== "assistant") return false;
        root._dropConfirmation(false);
        root._setMessageIds(root.messageIDs.slice(0, index));
        root._saveNow();
        root._startModelRequest({ "regenerate": true });
        return true;
    }

    // ── Sessions ───────────────────────────────────────────────────
    readonly property string autoSaveFilePath: `${Directories.aiChats}/lastSession.json`
    property bool _saveInFlight: false
    property bool _savePending: false
    readonly property var _sessionOptions: ({
        "retiredModels": root.retiredModels,
        "isAntigravityModel": id => root.planFormatFor(id) === "antigravity-cli" || String(id).startsWith("gemini-plan"),
        "newId": () => root.idForMessage(),
    })

    // Written only, never read: the restore reads through a loader of its own.
    FileView {
        id: autoSaveFileView
        path: root.autoSaveFilePath
        preload: false
        blockLoading: false
        blockWrites: false
        atomicWrites: true
        printErrors: false
        watchChanges: false
        onSaved: root._onAutoSaveDone()
        onSaveFailed: error => root._onAutoSaveDone()
    }

    Timer {
        id: saveDebounce
        interval: 1500
        repeat: false
        onTriggered: {
            if (!root.isGenerating) root._saveNow();
        }
    }

    Timer {
        id: restoreTimer
        interval: 0
        repeat: false
        onTriggered: root._restoreChunk()
    }

    Component {
        id: sessionLoaderComponent
        FileView {
            id: loaderView
            property int generation: 0
            property string kind: ""
            property string chatName: ""
            preload: true
            blockLoading: false
            printErrors: false
            watchChanges: false
            onLoaded: root._onSessionLoaded(loaderView)
            onLoadFailed: error => root._onSessionLoadFailed(loaderView)
        }
    }

    Component {
        id: namedSaveComponent
        FileView {
            id: saveView
            property string chatName: ""
            preload: false
            blockLoading: false
            blockWrites: false
            atomicWrites: true
            printErrors: false
            watchChanges: false
            onSaved: {
                root.reloadSavedChats();
                root._bury(saveView);
            }
            onSaveFailed: error => {
                if (root._savedName === saveView.chatName)
                    root._savedSignature = "";
                root._bury(saveView);
            }
        }
    }

    Component {
        id: removeProcessComponent
        Process {
            id: removeProc
            onExited: (exitCode, exitStatus) => {
                root.reloadSavedChats();
                root._bury(removeProc);
            }
        }
    }

    function scheduleSave(): void {
        if (!root._startupRestored || root.sessionLoading || root.isGenerating) return;
        saveDebounce.restart();
    }

    function _serializeSession() {
        const cliSessions = {};
        for (const [key, strategy] of Object.entries(root.apiStrategies)) {
            if (strategy?.isCliStrategy && strategy.sessionId) cliSessions[key] = strategy.sessionId;
        }
        return Sessions.serialize(root.messageIDs.map(id => root.messageByID[id]), root.currentModelId, cliSessions, Date.now());
    }

    // Writes lastSession.json. One write at a time: a new text is never handed
    // over while a write runs, since that would block on it.
    function _saveNow() {
        if (!root._startupRestored || root.sessionLoading) return;
        saveDebounce.stop();
        if (root._saveInFlight) {
            root._savePending = true;
            return;
        }
        const text = root._serializeSession();
        root._saveInFlight = true;
        autoSaveFileView.setText(text);
    }

    function _onAutoSaveDone() {
        root._saveInFlight = false;
        if (root._savePending) {
            root._savePending = false;
            // The FileView still counts the finished write as live until this
            // signal returns, and a write started now would be dropped.
            Qt.callLater(root._saveNow);
        }
    }

    function _cleanChatName(chatName) {
        let cleanName = String(chatName ?? "").trim();
        if (cleanName.endsWith(".json")) cleanName = cleanName.slice(0, -5).trim();
        if (cleanName.includes("/")) cleanName = cleanName.split("/").pop().replace(".json", "");
        return cleanName;
    }

    function _savedChatName(chatName) {
        const cleanName = root._cleanChatName(chatName);
        return cleanName.toLowerCase() === "lastsession" ? "saved-session" : cleanName;
    }

    function sessionNameExists(name): bool {
        const cleanName = root._savedChatName(name);
        return cleanName.length > 0 && root.savedChats.includes(`${Directories.aiChats}/${cleanName}.json`);
    }

    /**
     * Saves the chat under a name, in the background.
     * @param chatName name of the chat
     * @returns the name saved under, or "" when nothing was saved
     */
    function saveChat(chatName): string {
        const cleanName = root._savedChatName(chatName);
        if (cleanName.length === 0) return "";
        if (!root.messageIDs.some(id => root.messageByID[id]?.role === "user")) return "";
        const writer = namedSaveComponent.createObject(root, { "chatName": cleanName });
        if (!writer) return "";
        writer.path = `${Directories.aiChats}/${cleanName}.json`;
        writer.setText(root._serializeSession());
        root._savedSignature = root._chatSignature();
        root._savedName = cleanName;
        return cleanName;
    }

    // Changes whenever a message is added, removed, edited or still streaming.
    function _chatSignature() {
        const ids = root.messageIDs;
        const parts = [];
        for (let i = 0; i < ids.length; i++) {
            const msg = root.messageByID[ids[i]];
            parts.push(ids[i] + ":" + (msg?.contentRevision ?? 0) + ":" + (msg?.content?.length ?? 0) + ":" + (msg?.done ?? true));
        }
        return parts.join("|");
    }

    /**
     * True when the chat has a user message and is not the named session
     * it last matched, so loading over it would lose it.
     */
    function chatIsUnsaved(): bool {
        if (!root.messageIDs.some(id => root.messageByID[id]?.role === "user")) return false;
        return root._chatSignature() !== root._savedSignature || !root.sessionNameExists(root._savedName);
    }

    /**
     * Deletes saved chat file.
     * @param chatName name of the chat
     */
    function deleteChat(chatName): void {
        const cleanName = root._cleanChatName(chatName);
        if (cleanName.length === 0 || cleanName === "lastSession") return;
        const filePath = `${Directories.aiChats}/${cleanName}.json`;
        root.savedChats = root.savedChats.filter(path => path !== filePath);
        removeProcessComponent.createObject(root, {
            "command": ["rm", "-f", "--", filePath],
            "running": true,
        });
    }

    /**
     * Starts loading a saved chat. True means the load has started; a
     * failure arrives later as a message.
     * @param chatName name of the chat
     */
    function loadChat(chatName): bool {
        const cleanName = root._cleanChatName(chatName);
        if (cleanName.length === 0) return false;
        root._bumpLoad();
        root._abandonRequest();
        root._dropConfirmation(false);
        root._startLoad(`${Directories.aiChats}/${cleanName}.json`, "named", cleanName);
        return true;
    }

    // Abandons any load in progress; its late callbacks see another generation.
    function _bumpLoad() {
        root._loadGeneration++;
        restoreTimer.stop();
        if (root._restore) {
            root._buryAll(root._restore.created);
            root._restore = null;
        }
        root._endLoad();
    }

    // Every load ends here, and the first one to end settles the startup restore.
    function _endLoad() {
        root.sessionLoading = false;
        root._startupRestored = true;
    }

    function _startLoad(path, kind, chatName) {
        root.sessionLoading = true;
        const loader = sessionLoaderComponent.createObject(root, {
            "generation": root._loadGeneration,
            "kind": kind,
            "chatName": chatName,
        });
        if (!loader) {
            root._loadFailed(kind, chatName);
            return;
        }
        // Assigning the path starts the read in the background.
        loader.path = path;
    }

    function _onSessionLoaded(loader) {
        const generation = loader.generation;
        const kind = loader.kind;
        const chatName = loader.chatName;
        const current = generation === root._loadGeneration;
        const text = current ? loader.text() : "";
        root._bury(loader);
        if (!current) return;
        let parsed = null;
        try {
            parsed = Sessions.parse(JSON.parse(text));
        } catch (e) {
            parsed = null;
        }
        if (!parsed || !parsed.ok || (kind === "named" && parsed.items.length === 0)) {
            root._loadFailed(kind, chatName);
            return;
        }
        root._restore = {
            "generation": generation,
            "kind": kind,
            "chatName": chatName,
            "parsed": parsed,
            "index": 0,
            "ids": [],
            "byId": ({}),
            "created": [],
        };
        restoreTimer.start();
    }

    function _onSessionLoadFailed(loader) {
        const current = loader.generation === root._loadGeneration;
        const kind = loader.kind;
        const chatName = loader.chatName;
        root._bury(loader);
        if (current) root._loadFailed(kind, chatName);
    }

    function _loadFailed(kind, chatName) {
        root._endLoad();
        if (kind === "startup") return;
        root.addMessage(Translation.tr("Could not load the saved session %1.").arg(chatName), root.interfaceRole, { "persist": false });
    }

    // Builds 25 message objects per event loop pass.
    function _restoreChunk() {
        const r = root._restore;
        if (!r || r.generation !== root._loadGeneration) return;
        const items = r.parsed.items;
        const end = Math.min(r.index + 25, items.length);
        for (; r.index < end; r.index++) {
            const props = Sessions.messageProps(items[r.index], r.parsed.version, root._sessionOptions);
            if (!props) continue;
            if (r.byId[props.id] || root.messageByID[props.id]) props.id = root.idForMessage();
            const message = aiMessageComponent.createObject(root, props);
            if (!message) continue;
            r.created.push(message);
            r.ids.push(props.id);
            r.byId[props.id] = message;
        }
        if (r.index < items.length) {
            restoreTimer.restart();
            return;
        }
        root._restore = null;
        root._completeLoad(r);
    }

    function _completeLoad(r) {
        if (r.kind === "startup") {
            // Notices posted while the restore ran stay after it.
            const byId = Object.assign({}, r.byId);
            for (const id of root.messageIDs) byId[id] = root.messageByID[id];
            root.messageByID = byId;
            root.messageIDs = r.ids.concat(root.messageIDs);
        } else {
            root.messageByID = Object.assign({}, root.messageByID, r.byId);
            root._setMessageIds(r.ids);
            root._resetTokenCount();
        }
        root._resetCliSessions();
        const cliSessions = r.parsed.cliSessions;
        for (const key of Object.keys(cliSessions)) {
            const strategy = root.apiStrategies[key];
            if (strategy?.isCliStrategy && typeof cliSessions[key] === "string") strategy.sessionId = cliSessions[key];
        }
        root._endLoad();
        // At startup the selection the user has now stands over the one saved.
        // Picking the setup entry starts the Ollama walkthrough, so a chat saved
        // on it keeps the current model instead.
        const savedModel = root.retiredModels[r.parsed.model] ?? r.parsed.model;
        if (r.kind !== "startup" && savedModel.length > 0 && savedModel !== root.ollamaSetupModelId)
            root.setModel(savedModel, false, true, false);
        // Taken after the model switch, which can post a notice of its own.
        if (r.kind !== "startup") {
            root._savedSignature = root._chatSignature();
            root._savedName = r.chatName;
        }
        root._saveNow();
    }
}
