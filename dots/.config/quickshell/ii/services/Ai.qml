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
        return prompt;
    }
    // property var messages: []
    property var messageIDs: []
    property var messageByID: ({})
    readonly property var apiKeys: KeyringStorage.keyringData?.apiKeys ?? {}
    readonly property var apiKeysLoaded: KeyringStorage.loaded
    readonly property bool currentModelHasApiKey: {
        const model = models[currentModelId];
        if (!model || !model.requires_key) return true;
        if (!apiKeysLoaded) return false;
        const key = apiKeys[model.key_id];
        return (key?.length > 0);
    }
    property var postResponseHook
    property real temperature: Persistent.states?.ai?.temperature ?? 0.5
    property QtObject tokenCount: QtObject {
        property int input: -1
        property int output: -1
        property int total: -1
    }

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
    property list<var> savedChats: []

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
    readonly property string effectiveTool: (root.currentTool === "functions" && !(root.currentApiStrategy?.supportsFunctions ?? false)) ? "none" : root.currentTool
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
    property var models: Config.options.policies.ai === 2 ? {} : {
        "gemini-2.5-flash": aiModelComponent.createObject(this, {
            "name": "Gemini 2.5 Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nNewer model that's slower than its predecessor but should deliver higher quality answers"),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent",
            "model": "gemini-2.5-flash",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            "api_format": "gemini",
        }),
        "gemini-3-flash": aiModelComponent.createObject(this, {
            "name": "Gemini 3 Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nPro-level intelligence at the speed and pricing of Flash."),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:streamGenerateContent",
            "model": "gemini-3-flash-preview",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            "api_format": "gemini",
        }),
        "mistral-medium-3": aiModelComponent.createObject(this, {
            "name": "Mistral Medium 3",
            "icon": "mistral-symbolic",
            "description": Translation.tr("Online | %1's model | Delivers fast, responsive and well-formatted answers. Disadvantages: not very eager to do stuff; might make up unknown function calls").arg("Mistral"),
            "homepage": "https://mistral.ai/news/mistral-medium-3",
            "endpoint": "https://api.mistral.ai/v1/chat/completions",
            "model": "mistral-medium-2505",
            "requires_key": true,
            "key_id": "mistral",
            "key_get_link": "https://console.mistral.ai/api-keys",
            "key_get_description": Translation.tr("**Instructions**: Log into Mistral account, go to Keys on the sidebar, click Create new key"),
            "api_format": "mistral",
        }),
        "claude": aiModelComponent.createObject(this, {
            "name": "Claude",
            "icon": "spark-symbolic",
            "description": Translation.tr("Online | Anthropic's Claude Opus 4.8 over the Messages API"),
            "homepage": "https://www.anthropic.com/claude",
            "endpoint": "https://api.anthropic.com/v1/messages",
            "model": "claude-opus-4-8",
            "requires_key": true,
            "key_id": "anthropic",
            "key_get_link": "https://console.anthropic.com/settings/keys",
            "key_get_description": Translation.tr("**Instructions**: Log into your Anthropic account, go to API Keys, click Create Key"),
            "api_format": "anthropic",
        }),
        "codex": aiModelComponent.createObject(this, {
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
    }
    // Only ever a view of the map. Readonly so no fetch handler can hand it
    // a snapshot that stops following the models registered afterwards.
    readonly property var modelList: Object.keys(root.models)
    readonly property var currentModelId: Persistent.states?.ai?.model || modelList[0]
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
    readonly property var currentModel: models[currentModelId] ?? null

    property var apiStrategies: {
        "openai": openaiApiStrategy.createObject(this),
        "gemini": geminiApiStrategy.createObject(this),
        "mistral": mistralApiStrategy.createObject(this),
        "anthropic": anthropicApiStrategy.createObject(this),
        "claude-code": claudeCodeApiStrategy.createObject(this),
        "codex-cli": codexCliApiStrategy.createObject(this),
    }
    property ApiStrategy currentApiStrategy: apiStrategies[models[currentModelId]?.api_format || "openai"]

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
            "install": "curl -fsSL https://claude.ai/install.sh | bash",
            "login": "claude auth login --claudeai",
            "readyCheck": "claude auth status --json 2>/dev/null | grep -q '\"loggedIn\": *true'"
        },
        "codex-cli": {
            "name": "Codex",
            "cmd": "codex",
            "install": "curl -fsSL https://chatgpt.com/codex/install.sh | sh",
            "login": "codex login",
            "readyCheck": "codex login status >/dev/null 2>&1"
        }
    })
    readonly property var cliPlanModels: ({
        "claude-code": {
            "claude-fable": { alias: "fable", name: "Claude Fable" },
            "claude-opus": { alias: "opus", name: "Claude Opus" },
            "claude-opus-1m": { alias: "opus[1m]", name: "Claude Opus 1M" },
            "claude-sonnet": { alias: "sonnet", name: "Claude Sonnet" },
            "claude-haiku": { alias: "haiku", name: "Claude Haiku" },
        },
        // Sol is refused under ChatGPT-account auth (API key only), so the
        // plan shelf carries the three the subscription actually serves.
        "codex-cli": {
            "codex-terra": { alias: "gpt-5.6-terra", name: "Codex Terra" },
            "codex-luna": { alias: "gpt-5.6-luna", name: "Codex Luna" },
            "codex-gpt-5-5": { alias: "gpt-5.5", name: "Codex GPT-5.5" },
        }
    })
    readonly property var cliPlans: ({
        "claude-code": {
            setupId: "claude-code",
            setupName: "Claude (Pro/Max plan)",
            setupDescription: Translation.tr("Plan | Anthropic's Claude through your Pro/Max subscription. Sign in from the sidebar, no API key needed"),
            setupHomepage: "https://docs.anthropic.com/en/docs/claude-code",
            modelDescription: Translation.tr("Plan | %1 through your Claude subscription. No API key needed"),
            signedIn: Translation.tr("Signed in. The plan models are in the picker now: type /model to choose between Fable, Opus, Opus 1M, Sonnet, and Haiku."),
            icon: "spark-symbolic",
            endpoint: "https://api.anthropic.com",
            homepage: "https://www.anthropic.com/claude",
            firstPick: "claude-fable",
            idPrefix: "claude-",
        },
        "codex-cli": {
            setupId: "codex-plan",
            setupName: "Codex (ChatGPT plan)",
            setupDescription: Translation.tr("Plan | OpenAI's Codex through your ChatGPT subscription. Sign in from the sidebar, no API key needed"),
            setupHomepage: "https://learn.chatgpt.com/docs/codex/cli",
            modelDescription: Translation.tr("Plan | %1 through your ChatGPT subscription. No API key needed"),
            signedIn: Translation.tr("Signed in. The plan models are in the picker now: type /model to choose between Terra, Luna, and GPT-5.5."),
            icon: "openai-symbolic",
            endpoint: "https://chatgpt.com",
            homepage: "https://learn.chatgpt.com/docs/codex/cli",
            firstPick: "codex-terra",
            idPrefix: "codex-",
        }
    })
    property var cliPlanState: ({})
    function cliInstalled(fmt) { return root.cliPlanState[fmt]?.installed === true }
    function cliReady(fmt) { return root.cliPlanState[fmt]?.ready === true }
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

    function syncCliPlanModels(fmt) {
        if (Config.options?.policies?.ai === 2) return;
        const plan = root.cliPlans[fmt];
        const planModels = root.cliPlanModels[fmt];
        if (!plan || !planModels) return;
        let next = Object.assign({}, root.models);
        let changed = false;
        if (root.cliReady(fmt)) {
            if (next[plan.setupId]) { delete next[plan.setupId]; changed = true; }
            for (const id of Object.keys(planModels)) {
                if (next[id]) continue;
                const planEntry = planModels[id];
                next[id] = aiModelComponent.createObject(this, {
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
                });
                changed = true;
            }
        } else {
            for (const id of Object.keys(planModels)) {
                if (next[id]) { delete next[id]; changed = true; }
            }
            if (!next[plan.setupId]) {
                next[plan.setupId] = aiModelComponent.createObject(this, {
                    "name": plan.setupName,
                    "icon": plan.icon,
                    "description": plan.setupDescription,
                    "homepage": plan.setupHomepage,
                    "endpoint": plan.endpoint,
                    "model": plan.setupId,
                    "requires_key": false,
                    "api_format": fmt,
                });
                changed = true;
            }
        }
        if (changed) root.models = next;
    }

    // One detector serves every CLI; requests that arrive while it is busy
    // wait their turn in the queue.
    property var _detectQueue: []
    function detectCli(fmt) {
        const entry = root.cliSetup[fmt];
        if (!entry) return;
        if (cliDetectProc.running) {
            if (!root._detectQueue.includes(fmt)) root._detectQueue.push(fmt);
            return;
        }
        const script = root.cliPathPrefix + `if command -v ${entry.cmd} >/dev/null 2>&1; then echo installed; if ${entry.readyCheck}; then echo ready; fi; fi < /dev/null`;
        cliDetectProc.format = fmt;
        cliDetectProc.command = ["bash", "-lc", script];
        cliDetectProc.running = true;
    }

    function setupCurrentModel() {
        const entry = root.currentCliSetup;
        if (!entry || root.setupState === "installing" || root.setupState === "loggingIn") return;
        if (root.cliInstalled(root.currentModel.api_format)) {
            root._runLogin();
        } else {
            root.setupState = "installing";
            installProc.command = ["bash", "-lc", root.cliPathPrefix + entry.install];
            installProc.running = false;
            installProc.running = true;
        }
    }

    // The login flow is interactive: only under a terminal does the CLI print
    // its link, open the browser, and take back whatever the flow needs. So
    // the sign-in gets a real terminal window and the watcher below notices
    // when the login lands.
    function _runLogin() {
        const entry = root.currentCliSetup;
        if (!entry) return;
        root.setupState = "loggingIn";
        const script = root.cliPathPrefix + entry.login
            + "; echo; echo 'You can close this window.'; read -r -n 1 -s";
        Quickshell.execDetached(["bash", "-c",
            `${Config.options.apps.terminal} -e bash -c '${CF.StringUtils.shellSingleQuoteEscape(script)}'`]);
        loginWatch.triesLeft = 60;
    }

    Process {
        id: cliDetectProc
        property string format: ""
        property string buf: ""
        stdout: SplitParser { onRead: line => cliDetectProc.buf += line + "\n" }
        onRunningChanged: if (running) buf = ""
        onExited: (code) => {
            const fmt = cliDetectProc.format;
            const wasReady = root.cliReady(fmt);
            const nextState = Object.assign({}, root.cliPlanState);
            nextState[fmt] = {
                installed: cliDetectProc.buf.includes("installed"),
                ready: cliDetectProc.buf.includes("ready"),
            };
            root.cliPlanState = nextState;
            if (nextState[fmt].ready && root.currentModel?.api_format === fmt) root.setupState = "";
            root.syncCliPlanModels(fmt);
            const plan = root.cliPlans[fmt];
            if (!wasReady && nextState[fmt].ready && root.currentModelId === plan.setupId) {
                root.setModel(plan.firstPick, true);
                root.addMessage(plan.signedIn, root.interfaceRole);
            }
            // A selection this family no longer offers (a lapsed login, or a
            // model entry that was retired) falls to the best seat still open
            // rather than dangling on an id that no longer resolves.
            if (root.models[root.currentModelId] === undefined && root.currentModelId.startsWith(plan.idPrefix)) {
                Persistent.states.ai.model = nextState[fmt].ready ? plan.firstPick : plan.setupId;
            }
            const queued = root._detectQueue.shift();
            if (queued) root.detectCli(queued);
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
        interval: 2000
        repeat: true
        running: triesLeft > 0 && root.setupState === "loggingIn"
            && !root.cliReady(root.currentModel?.api_format ?? "")
        onTriggered: {
            triesLeft--;
            const fmt = root.currentModel?.api_format;
            if (fmt) root.detectCli(fmt);
            if (triesLeft <= 0) root.setupState = "error";
        }
    }
    onCurrentModelIdChanged: {
        root.setupState = "";
        if (root.cliSetup[root.currentModel?.api_format] !== undefined)
            root.detectCli(root.currentModel.api_format);
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return;
            root.addUserModels()
        }
    }

    property string requestScriptFilePath: "/tmp/quickshell/ai/request.sh"
    property string pendingFilePath: ""

    Component.onCompleted: {
        // The default model is local AI, whose setup entry does not exist
        // until the first status answer arrives. Running it through setModel
        // here would start the walkthrough unprompted at every shell start;
        // syncOllamaSetupEntry and the model fetch land the selection instead.
        if (currentModelId !== root.ollamaSetupModelId)
            setModel(currentModelId, false, false); // Do necessary setup for model
        root.addUserModels() // Config onReadyChanged above might not fire if config is loaded before this service
        for (const fmt of Object.keys(root.cliSetup)) {
            root.syncCliPlanModels(fmt) // The setup entries exist before the CLIs answer
            root.detectCli(fmt)
        }
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
        root.models = Object.assign({}, root.models, {
            [modelName]: aiModelComponent.createObject(this, data)
        });
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
                    dataJson.forEach(model => {
                        const safeModelName = root.safeModelName(model);
                        root.addModel(safeModelName, {
                            "name": guessModelName(model),
                            "icon": guessModelLogo(model),
                            "description": Translation.tr("Local Ollama model | %1").arg(model),
                            "homepage": `https://ollama.com/library/${model}`,
                            "endpoint": "http://localhost:11434/v1/chat/completions",
                            "model": model,
                            "requires_key": false,
                        })
                    });

                    // The saved model may only now have become selectable, so
                    // take it up rather than leaving the default in place.
                    if (root.modelList.includes(root.currentModelId)) {
                        root.setModel(root.currentModelId, false, false);
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
                    } else if (root.currentModelId === root.ollamaSetupModelId) {
                        // The saved model is the local AI default and a real
                        // local model just showed up: that is the machine this
                        // default was waiting for, so take the first one up.
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
            });
        } else if (root.models[root.ollamaSetupModelId]) {
            const remaining = Object.assign({}, root.models);
            delete remaining[root.ollamaSetupModelId];
            root.models = remaining;
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
        message.content = body;
        message.rawContent = body;
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
        running: true
        command: ["ls", "-1", Directories.aiChats]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.savedChats = text.split("\n")
                    .filter(fileName => fileName.endsWith(".json"))
                    .map(fileName => `${Directories.aiChats}/${fileName}`)
            }
        }
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

    function addMessage(message, role) {
        if (message.length === 0) return;
        const aiMessage = aiMessageComponent.createObject(root, {
            "role": role,
            "content": message,
            "rawContent": message,
            "thinking": false,
            "done": true,
        });
        const id = idForMessage(aiMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
        // Handed back so a caller reporting on something long-running can
        // rewrite the one message instead of appending a line per update.
        return id;
    }

    function removeMessage(index) {
        if (index < 0 || index >= messageIDs.length) return;
        const id = root.messageIDs[index];
        root.messageIDs.splice(index, 1);
        root.messageIDs = [...root.messageIDs];
        delete root.messageByID[id];
    }

    function addApiKeyAdvice(model) {
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

    function setModel(modelId, feedback = true, setPersistentState = true) {
        if (!modelId) modelId = ""
        modelId = modelId.toLowerCase()
        // The setup entry is a prompt wearing a model's clothes. Picking it
        // starts the walkthrough and leaves the working model in place, so a
        // user who was mid-conversation does not lose the model answering it.
        if (modelId === root.ollamaSetupModelId) {
            root.startOllamaWalkthrough();
            return;
        }
        if (modelList.indexOf(modelId) !== -1) {
            const model = models[modelId]
            // See if policy prevents online models
            if (Config.options.policies.ai === 2 && !model.endpoint.includes("localhost")) {
                root.addMessage(
                    Translation.tr("Online models disallowed\n\nControlled by `policies.ai` config option"),
                    root.interfaceRole
                );
                return;
            }
            if (setPersistentState) Persistent.states.ai.model = modelId;
            if (feedback) root.addMessage(Translation.tr("Model set to %1").arg(model.name), root.interfaceRole);
            // Advice belongs to somebody who just chose this model. Callers
            // passing feedback=false are re-applying a model the user already
            // had, and a silent re-apply that answers with a page about API
            // keys reads as though it is talking about whatever just happened.
            if (feedback && model.requires_key) {
                // If key not there show advice
                if (root.apiKeysLoaded && (!root.apiKeys[model.key_id] || root.apiKeys[model.key_id].length === 0)) {
                    root.addApiKeyAdvice(model)
                }
            }
        } else {
            if (feedback) root.addMessage(Translation.tr("Invalid model. Supported: \n```\n") + modelList.join("\n```\n```\n"), Ai.interfaceRole) + "\n```"
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
    
    function getTemperature() {
        return root.temperature;
    }

    function setTemperature(value) {
        if (value == NaN || value < 0 || value > 2) {
            root.addMessage(Translation.tr("Temperature must be between 0 and 2"), Ai.interfaceRole);
            return;
        }
        Persistent.states.ai.temperature = value;
        root.temperature = value;
        root.addMessage(Translation.tr("Temperature set to %1").arg(value), Ai.interfaceRole);
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
                root.addMessage(Translation.tr("API key:\n\n```txt\n%1\n```").arg(key), Ai.interfaceRole);
            } else {
                root.addMessage(Translation.tr("No API key set for %1").arg(model.name), Ai.interfaceRole);
            }
        } else {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
        }
    }

    function printTemperature() {
        root.addMessage(Translation.tr("Temperature: %1").arg(root.temperature), Ai.interfaceRole);
    }

    function clearMessages() {
        root.messageIDs = [];
        root.messageByID = ({});
        root.tokenCount.input = -1;
        root.tokenCount.output = -1;
        root.tokenCount.total = -1;
        // A CLI strategy resumes its session on every request; keeping the id
        // across a clear would quietly thread the old conversation back in.
        for (const strategy of Object.values(root.apiStrategies)) {
            if (strategy.isCliStrategy && strategy.sessionId !== undefined)
                strategy.sessionId = "";
        }
    }

    FileView {
        id: requesterScriptFile
    }

    Process {
        id: requester
        property list<string> baseCommand: ["bash"]
        property AiMessageData message
        property ApiStrategy currentStrategy

        function markDone() {
            requester.message.done = true;
            if (root.postResponseHook) {
                root.postResponseHook();
                root.postResponseHook = null; // Reset hook after use
            }
            root.responseFinished()
        }

        function makeRequest() {
            const model = models[currentModelId];

            // Fetch API keys if needed
            if (model?.requires_key && !KeyringStorage.loaded) KeyringStorage.fetchKeyringData();
            
            requester.currentStrategy = root.currentApiStrategy;
            requester.currentStrategy.reset(); // Reset strategy state

            /* Put API key in environment variable */
            if (model.requires_key) requester.environment[`${root.apiKeyEnvVarName}`] = root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : ""

            /* Build endpoint, request data */
            const endpoint = root.currentApiStrategy.buildEndpoint(model);
            const messageArray = root.messageIDs.map(id => root.messageByID[id]);
            const filteredMessageArray = messageArray.filter(message => message.role !== Ai.interfaceRole);
            const data = root.currentApiStrategy.buildRequestData(model, filteredMessageArray, root.systemPrompt, root.temperature, root.tools[model.api_format]?.[root.effectiveTool] ?? [], root.pendingFilePath);
            // console.log("[Ai] Request data: ", JSON.stringify(data, null, 2));

            let requestHeaders = {
                "Content-Type": "application/json",
            }
            
            /* Create local message object */
            requester.message = root.aiMessageComponent.createObject(root, {
                "role": "assistant",
                "model": currentModelId,
                "content": "",
                "rawContent": "",
                "thinking": true,
                "done": false,
            });
            const id = idForMessage(requester.message);
            root.messageIDs = [...root.messageIDs, id];
            root.messageByID[id] = requester.message;

            /* Build header string for curl */ 
            let headerString = Object.entries(requestHeaders)
                .filter(([k, v]) => v && v.length > 0)
                .map(([k, v]) => `-H '${k}: ${v}'`)
                .join(' ');

            // console.log("Request headers: ", JSON.stringify(requestHeaders));
            // console.log("Header string: ", headerString);

            /* Get authorization header from strategy */
            const authHeader = requester.currentStrategy.buildAuthorizationHeader(root.apiKeyEnvVarName);
            
            /* Script shebang */
            const scriptShebang = "#!/usr/bin/env bash\n";

            /* Create extra setup when there's an attached file */
            let scriptFileSetupContent = ""
            if (root.pendingFilePath && root.pendingFilePath.length > 0) {
                requester.message.localFilePath = root.pendingFilePath;
                scriptFileSetupContent = requester.currentStrategy.buildScriptFileSetup(root.pendingFilePath);
                root.pendingFilePath = ""
            }

            /* Create command string */
            // A strategy backed by a local command writes its own invocation.
            // There is no endpoint to post to in that case, so the curl form
            // below would be addressed at an empty URL.
            let scriptRequestContent = ""
            if (requester.currentStrategy.isCliStrategy) {
                scriptRequestContent = requester.currentStrategy.buildScriptRequestContent(model, filteredMessageArray, root.systemPrompt, root.temperature);
            } else {
                scriptRequestContent += `curl --no-buffer "${endpoint}"`
                    + ` ${headerString}`
                    + (authHeader ? ` ${authHeader}` : "")
                    + ` --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'`
                    + "\n"
            }
            
            /* Send the request */
            const scriptContent = requester.currentStrategy.finalizeScriptContent(scriptShebang + scriptFileSetupContent + scriptRequestContent)
            const shellScriptPath = CF.FileUtils.trimFileProtocol(root.requestScriptFilePath)
            requesterScriptFile.path = Qt.resolvedUrl(shellScriptPath)
            requesterScriptFile.setText(scriptContent)
            requester.command = baseCommand.concat([shellScriptPath]);
            requester.running = true
        }

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                if (requester.message.thinking) requester.message.thinking = false;
                // console.log("[Ai] Raw response line: ", data);

                // Handle response line
                try {
                    const result = requester.currentStrategy.parseResponseLine(data, requester.message);
                    // console.log("[Ai] Parsed response result: ", JSON.stringify(result, null, 2));

                    if (result.functionCall) {
                        requester.message.functionCall = result.functionCall;
                        root.handleFunctionCall(result.functionCall.name, result.functionCall.args, requester.message);
                    }
                    if (result.tokenUsage) {
                        root.tokenCount.input = result.tokenUsage.input;
                        root.tokenCount.output = result.tokenUsage.output;
                        root.tokenCount.total = result.tokenUsage.total;
                    }
                    if (result.finished) {
                        requester.markDone();
                    }
                    
                } catch (e) {
                    console.log("[AI] Could not parse response: ", e);
                    requester.message.rawContent += data;
                    requester.message.content += data;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            const result = requester.currentStrategy.onRequestFinished(requester.message);
            
            if (result.finished) {
                requester.markDone();
            } else if (!requester.message.done) {
                requester.markDone();
            }

            // Handle error responses
            if (requester.message.content.includes("API key not valid")) {
                root.addApiKeyAdvice(models[requester.message.model]);
            }
        }
    }

    function sendUserMessage(message) {
        if (message.length === 0) return;
        root.addMessage(message, "user");
        // The setup entry names no model, so a request built from it would post
        // an empty one and come back as a failure the user cannot act on. Say
        // what local AI is still waiting for instead.
        if (root.currentModelId === root.ollamaSetupModelId) {
            root.startOllamaWalkthrough();
            return;
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
            return;
        }
        requester.makeRequest();
    }

    function attachFile(filePath: string) {
        root.pendingFilePath = CF.FileUtils.trimFileProtocol(filePath);
    }

    function regenerate(messageIndex) {
        if (messageIndex < 0 || messageIndex >= messageIDs.length) return;
        const id = root.messageIDs[messageIndex];
        const message = root.messageByID[id];
        if (message.role !== "assistant") return;
        // Remove all messages after this one
        for (let i = root.messageIDs.length - 1; i >= messageIndex; i--) {
            root.removeMessage(i);
        }
        requester.makeRequest();
    }

    function createFunctionOutputMessage(name, output, includeOutputInChat = true) {
        return aiMessageComponent.createObject(root, {
            "role": "user",
            "content": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "rawContent": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "functionName": name,
            "functionResponse": output,
            "thinking": false,
            "done": true,
            // "visibleToUser": false,
        });
    }

    function addFunctionOutputMessage(name, output) {
        const aiMessage = createFunctionOutputMessage(name, output);
        const id = idForMessage(aiMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
    }

    function rejectCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"
        addFunctionOutputMessage(message.functionName, Translation.tr("Command rejected by user"))
    }

    function approveCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"

        const responseMessage = createFunctionOutputMessage(message.functionName, "", false);
        const id = idForMessage(responseMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = responseMessage;

        commandExecutionProc.message = responseMessage;
        commandExecutionProc.baseMessageContent = responseMessage.content;
        commandExecutionProc.shellCommand = message.functionCall.args.command;
        commandExecutionProc.running = true; // Start the command execution
    }

    Process {
        id: commandExecutionProc
        property string shellCommand: ""
        property AiMessageData message
        property string baseMessageContent: ""
        command: ["bash", "-c", shellCommand]
        stdout: SplitParser {
            onRead: (output) => {
                commandExecutionProc.message.functionResponse += output + "\n\n";
                const updatedContent = commandExecutionProc.baseMessageContent + `\n\n<think>\n<tt>${commandExecutionProc.message.functionResponse}</tt>\n</think>`;
                commandExecutionProc.message.rawContent = updatedContent;
                commandExecutionProc.message.content = updatedContent;
            }
        }
        onExited: (exitCode, exitStatus) => {
            commandExecutionProc.message.functionResponse += `[[ Command exited with code ${exitCode} (${exitStatus}) ]]\n`;
            requester.makeRequest(); // Continue
        }
    }

    function handleFunctionCall(name, args: var, message: AiMessageData) {
        if (name === "switch_to_search_mode") {
            const modelId = root.currentModelId;
            root.currentTool = "search"
            root.postResponseHook = () => { root.currentTool = "functions" }
            addFunctionOutputMessage(name, Translation.tr("Switched to search mode. Continue with the user's request."))
            requester.makeRequest();
        } else if (name === "get_shell_config") {
            const configJson = CF.ObjectUtils.toPlainObject(Config.options)
            addFunctionOutputMessage(name, JSON.stringify(configJson));
            requester.makeRequest();
        } else if (name === "set_shell_config") {
            if (!args.key || !args.value) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `key` and `value`."));
                return;
            }
            const key = args.key;
            const value = args.value;
            Config.setNestedValue(key, value);
        } else if (name === "run_shell_command") {
            if (!args.command || args.command.length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `command`."));
                return;
            }
            const contentToAppend = `\n\n**Command execution request**\n\n\`\`\`command\n${args.command}\n\`\`\``;
            message.rawContent += contentToAppend;
            message.content += contentToAppend;
            message.functionPending = true; // Use thinking to indicate the command is waiting for approval
        }
        else root.addMessage(Translation.tr("Unknown function call: %1").arg(name), "assistant");
    }

    function chatToJson() {
        return root.messageIDs.map(id => {
            const message = root.messageByID[id]
            return ({
                "role": message.role,
                "rawContent": message.rawContent,
                "fileMimeType": message.fileMimeType,
                "fileUri": message.fileUri,
                "localFilePath": message.localFilePath,
                "model": message.model,
                "thinking": false,
                "done": true,
                "annotations": message.annotations,
                "annotationSources": message.annotationSources,
                "functionName": message.functionName,
                "functionCall": message.functionCall,
                "functionResponse": message.functionResponse,
                "visibleToUser": message.visibleToUser,
            })
        })
    }

    FileView {
        id: chatSaveFile
        property string chatName: ""
        path: chatName.length > 0 ? `${Directories.aiChats}/${chatName}.json` : ""
        blockLoading: true // Prevent race conditions
    }

    FileView {
        id: chatWriter
    }

    /**
     * Saves chat to a JSON list of message objects.
     * @param chatName name of the chat
     */
    function saveChat(chatName) {
        const filePath = `${Directories.aiChats}/${chatName.trim()}.json`
        chatWriter.path = filePath
        const saveContent = JSON.stringify(root.chatToJson())
        chatWriter.setText(saveContent)
        getSavedChats.running = true;
    }

    /**
     * Loads chat from a JSON list of message objects.
     * @param chatName name of the chat
     */
    function loadChat(chatName) {
        try {
            chatSaveFile.chatName = chatName.trim()
            chatSaveFile.reload()
            const saveContent = chatSaveFile.text()
            // console.log(saveContent)
            const saveData = JSON.parse(saveContent)
            root.clearMessages()
            root.messageIDs = saveData.map((_, i) => {
                return i
            })
            // console.log(JSON.stringify(messageIDs))
            for (let i = 0; i < saveData.length; i++) {
                const message = saveData[i];
                root.messageByID[i] = root.aiMessageComponent.createObject(root, {
                    "role": message.role,
                    "rawContent": message.rawContent,
                    "content": message.rawContent,
                    "fileMimeType": message.fileMimeType,
                    "fileUri": message.fileUri,
                    "localFilePath": message.localFilePath,
                    "model": message.model,
                    "thinking": message.thinking,
                    "done": message.done,
                    "annotations": message.annotations,
                    "annotationSources": message.annotationSources,
                    "functionName": message.functionName,
                    "functionCall": message.functionCall,
                    "functionResponse": message.functionResponse,
                    "visibleToUser": message.visibleToUser,
                });
            }
        } catch (e) {
            console.log("[AI] Could not load chat: ", e);
        } finally {
            getSavedChats.running = true;
        }
    }
}
