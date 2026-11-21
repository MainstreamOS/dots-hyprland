.pragma library

// Reads the AI model catalog, models.json. Top-level names are var because the
// tests load this file in a Node vm, where a top-level const stays out of reach.

var SUPPORTED_SCHEMA_VERSION = 1;
var VALID_THINKING_LEVELS = [
    "auto", "none", "minimal", "low", "medium", "high", "extra", "max", "ultracode"
];
var VALID_EFFORT_KEYS = [
    "none", "minimal", "low", "medium", "high", "extra", "max", "ultracode"
];
var VALID_DESC_PROFILES = ["gemini", "claude", "openai", "generic"];
// The formats this shell has a strategy for. An entry in any other format
// comes from a newer catalog and is left out.
var KNOWN_FORMATS = [
    "openai", "gemini", "mistral", "anthropic", "claude-code", "codex-cli", "antigravity-cli"
];
var CLI_FORMATS = ["claude-code", "codex-cli", "antigravity-cli"];
var MAX_RETIREMENT_HOPS = 5;

var _ID_RE = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
var _SLUG_RE = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$/;
var _EFFORT_VAL_RE = /^[A-Za-z0-9_-]{1,32}$/;

function isPlainObject(value) {
    return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

// A list that has passed through a QML property is a QVariantList, which
// Array.isArray does not recognize.
function toArray(value) {
    if (Array.isArray(value)) return value;
    if (value && typeof value === "object" && typeof value.length === "number") {
        const len = Math.floor(value.length);
        if (len >= 0 && len === value.length) {
            const out = [];
            for (let i = 0; i < len; i++) out.push(value[i]);
            return out;
        }
    }
    return null;
}

// A map read back from a QML property comes with its keys in another order,
// so two values are compared in this form.
function stableJson(value) {
    const list = toArray(value);
    if (list) return "[" + list.map(stableJson).join(",") + "]";
    if (!isPlainObject(value)) return JSON.stringify(value ?? null);
    return "{" + Object.keys(value).sort().map(key => JSON.stringify(key) + ":" + stableJson(value[key])).join(",") + "}";
}

function isValidModelId(id) {
    return typeof id === "string" && _ID_RE.test(id);
}

function isSafeEndpoint(url) {
    if (typeof url !== "string") return false;
    const trimmed = url.trim();
    if (trimmed.length === 0 || trimmed.length > 2048) return false;
    if (/[\s\x00-\x1f\x7f"'`\\<>]/.test(trimmed)) return false;
    if (/^https:\/\/[A-Za-z0-9.-]+(?::\d{1,5})?(?:\/[^\s]*)?$/.test(trimmed)) {
        const host = trimmed.slice(8).split(/[/:]/)[0];
        return host.length > 0 && !host.startsWith(".") && !host.endsWith(".") && !host.includes("..");
    }
    if (/^http:\/\/(?:localhost|127\.0\.0\.1|\[::1\])(?::\d{1,5})?(?:\/[^\s]*)?$/i.test(trimmed)) {
        return true;
    }
    return false;
}

function isSafeLink(url) {
    if (typeof url !== "string") return false;
    const trimmed = url.trim();
    if (trimmed.length === 0 || trimmed.length > 2048) return false;
    if (/[\s\x00-\x1f\x7f"'`\\<>]/.test(trimmed)) return false;
    return /^https:\/\/[^\s]+$/.test(trimmed);
}

function _nonEmptyString(value, fallback) {
    if (typeof value === "string") {
        const trimmed = value.trim();
        if (trimmed.length > 0) return trimmed;
    }
    return fallback !== undefined ? fallback : "";
}

function sanitizeEffortMap(raw) {
    if (!isPlainObject(raw)) return null;
    const out = {};
    let count = 0;
    for (const key of Object.keys(raw)) {
        const normKey = String(key).trim().toLowerCase();
        if (!VALID_EFFORT_KEYS.includes(normKey)) continue;
        const val = raw[key];
        if (val === "") {
            out[normKey] = "";
            count++;
        } else if (typeof val === "string" && _EFFORT_VAL_RE.test(val.trim())) {
            out[normKey] = val.trim();
            count++;
        }
    }
    return count > 0 ? out : null;
}

function sanitizeThinkingLevels(raw) {
    const list = toArray(raw);
    if (!list) return null;
    const out = [];
    for (const item of list) {
        if (typeof item !== "string") continue;
        const norm = item.trim().toLowerCase();
        if (!VALID_THINKING_LEVELS.includes(norm)) continue;
        if (!out.includes(norm)) out.push(norm);
    }
    return out.length > 0 ? out : null;
}

function sanitizeCapabilities(raw) {
    if (!isPlainObject(raw)) return {};
    const out = {};
    for (const key of Object.keys(raw)) {
        const val = raw[key];
        if (typeof val === "boolean") {
            out[key] = val;
        } else if (typeof val === "number" && Number.isFinite(val)) {
            out[key] = val;
        } else if (typeof val === "string" && val.length <= 128) {
            out[key] = val;
        }
    }
    return out;
}

function sanitizeThinkingProfile(raw) {
    if (!isPlainObject(raw)) return null;
    const levels = sanitizeThinkingLevels(raw.levels);
    if (!levels) return null;
    const rawDesc = typeof raw.descProfile === "string" ? raw.descProfile.trim().toLowerCase() : "";
    const descProfile = VALID_DESC_PROFILES.includes(rawDesc) ? rawDesc : "generic";
    const defaultEffort = (typeof raw.defaultEffort === "string" && _EFFORT_VAL_RE.test(raw.defaultEffort.trim()))
        ? raw.defaultEffort.trim() : "";
    const effortMap = sanitizeEffortMap(raw.effortMap);
    return {
        levels: levels,
        descProfile: descProfile,
        defaultEffort: defaultEffort,
        effortMap: effortMap,
    };
}

function resolveModelThinking(entry, thinkingProfiles) {
    const profiles = isPlainObject(thinkingProfiles) ? thinkingProfiles : {};
    const profileName = _nonEmptyString(entry?.thinkingProfile, "");
    const profile = profileName && isPlainObject(profiles[profileName]) ? profiles[profileName] : null;

    const entryLevels = sanitizeThinkingLevels(entry?.thinkingLevels);
    const profileLevels = toArray(profile?.levels);
    const levels = entryLevels || (profileLevels ? profileLevels.slice() : null);

    const rawDesc = typeof entry?.descProfile === "string" ? entry.descProfile.trim().toLowerCase() : "";
    const descProfile = VALID_DESC_PROFILES.includes(rawDesc)
        ? rawDesc
        : (profile?.descProfile || "");

    const entryEffortMap = sanitizeEffortMap(entry?.effortMap);
    let effortMap = null;
    if (profile?.effortMap || entryEffortMap) {
        effortMap = Object.assign({}, profile?.effortMap || {}, entryEffortMap || {});
    }

    let defaultEffort = "";
    if (typeof entry?.defaultEffort === "string") {
        const trimmed = entry.defaultEffort.trim();
        if (trimmed === "" || _EFFORT_VAL_RE.test(trimmed)) defaultEffort = trimmed;
    } else if (profile?.defaultEffort) {
        defaultEffort = profile.defaultEffort;
    }

    return {
        thinkingProfile: profile ? profileName : "",
        descProfile: descProfile,
        thinkingLevels: levels,
        effortMap: effortMap,
        defaultEffort: defaultEffort,
    };
}

function sanitizeExtraParams(raw) {
    if (!isPlainObject(raw)) return {};
    try {
        return JSON.parse(JSON.stringify(raw));
    } catch (e) {
        return {};
    }
}

function _sanitizeApiModelEntry(id, raw, thinkingProfiles, forceFormat, warnings) {
    if (!isValidModelId(id) || !isPlainObject(raw)) {
        warnings.push(`Skipping invalid model entry '${id}'`);
        return null;
    }
    const apiFormat = forceFormat || _nonEmptyString(raw.api_format, "openai");
    if (!KNOWN_FORMATS.includes(apiFormat)) {
        warnings.push(`Skipping model '${id}' with unsupported api_format '${apiFormat}'`);
        return null;
    }
    const endpoint = typeof raw.endpoint === "string" ? raw.endpoint.trim() : "";
    if (!isSafeEndpoint(endpoint)) {
        warnings.push(`Skipping model '${id}' with invalid endpoint`);
        return null;
    }
    const thinking = resolveModelThinking(raw, thinkingProfiles);
    const rawThinkingLevel = typeof raw.thinkingLevel === "string" ? raw.thinkingLevel.trim().toLowerCase() : "";
    const thinkingLevel = rawThinkingLevel === "" || VALID_EFFORT_KEYS.includes(rawThinkingLevel) ? rawThinkingLevel : "";

    return {
        name: _nonEmptyString(raw.name, id),
        icon: typeof raw.icon === "string" ? raw.icon.trim() : "",
        description: typeof raw.description === "string" ? raw.description : "",
        descriptionTemplate: typeof raw.descriptionTemplate === "string" ? raw.descriptionTemplate.trim() : "",
        descriptionModelName: typeof raw.descriptionModelName === "string" ? raw.descriptionModelName.trim() : "",
        homepage: isSafeLink(raw.homepage) ? raw.homepage.trim() : "",
        endpoint: endpoint,
        model: _nonEmptyString(raw.model, id),
        requires_key: raw.requires_key !== false,
        key_id: typeof raw.key_id === "string" ? raw.key_id.trim() : "",
        key_get_link: isSafeLink(raw.key_get_link) ? raw.key_get_link.trim() : "",
        key_get_description: typeof raw.key_get_description === "string" ? raw.key_get_description : "",
        keyInstructionKey: typeof raw.keyInstructionKey === "string" ? raw.keyInstructionKey.trim() : "",
        api_format: apiFormat,
        extraParams: sanitizeExtraParams(raw.extraParams),
        sendTemperature: raw.sendTemperature !== false,
        thinkingLevel: thinkingLevel,
        supportsSessions: raw.supportsSessions !== false,
        thinkingProfile: thinking.thinkingProfile,
        descProfile: thinking.descProfile,
        thinkingLevels: thinking.thinkingLevels,
        effortMap: thinking.effortMap,
        defaultEffort: thinking.defaultEffort,
        capabilities: sanitizeCapabilities(raw.capabilities),
    };
}

function _sanitizeCliPlanModel(id, raw, thinkingProfiles, warnings) {
    if (!isValidModelId(id) || !isPlainObject(raw)) {
        warnings.push(`Skipping invalid CLI plan model '${id}'`);
        return null;
    }
    const alias = _nonEmptyString(raw.alias, _nonEmptyString(raw.model, ""));
    const name = _nonEmptyString(raw.name, "");
    if (!alias || !name) {
        warnings.push(`Skipping CLI plan model '${id}' missing alias or name`);
        return null;
    }
    const thinking = resolveModelThinking(raw, thinkingProfiles);
    const rawThinkingLevel = typeof raw.thinkingLevel === "string" ? raw.thinkingLevel.trim().toLowerCase() : "";
    const thinkingLevel = rawThinkingLevel === "" || VALID_EFFORT_KEYS.includes(rawThinkingLevel) ? rawThinkingLevel : "";

    return {
        alias: alias,
        name: name,
        thinkingLevel: thinkingLevel,
        thinkingProfile: thinking.thinkingProfile,
        descProfile: thinking.descProfile,
        thinkingLevels: thinking.thinkingLevels,
        effortMap: thinking.effortMap,
        defaultEffort: thinking.defaultEffort,
        capabilities: sanitizeCapabilities(raw.capabilities),
    };
}

function _sanitizeCodexFallbackCatalog(rawList, warnings) {
    const list = toArray(rawList);
    if (!list) return [];
    const out = [];
    for (const item of list) {
        if (!isPlainObject(item)) continue;
        const slug = typeof item.slug === "string" ? item.slug.trim() : "";
        if (!_SLUG_RE.test(slug)) {
            warnings.push(`Skipping invalid codex fallback slug '${slug}'`);
            continue;
        }
        const name = _nonEmptyString(item.name, slug).slice(0, 80);
        const rawEfforts = toArray(item.efforts);
        const efforts = rawEfforts
            ? rawEfforts.filter(e => typeof e === "string" && _EFFORT_VAL_RE.test(e.trim())).map(e => e.trim())
            : [];
        const defaultEffort = typeof item.defaultEffort === "string" && _EFFORT_VAL_RE.test(item.defaultEffort.trim())
            ? item.defaultEffort.trim() : "";
        out.push({
            slug: slug,
            name: name,
            efforts: efforts,
            defaultEffort: defaultEffort,
        });
    }
    return out;
}

function _sanitizeTranslations(raw) {
    if (!isPlainObject(raw)) return {};
    const out = {};
    for (const locale of Object.keys(raw)) {
        const table = raw[locale];
        if (!isPlainObject(table)) continue;
        const cleanTable = {};
        for (const key of Object.keys(table)) {
            if (typeof table[key] === "string" && table[key].length > 0) {
                cleanTable[key] = table[key];
            }
        }
        if (Object.keys(cleanTable).length > 0) out[locale] = cleanTable;
    }
    return out;
}

function _sanitizeRetiredModels(raw) {
    if (!isPlainObject(raw)) return {};
    const out = {};
    for (const key of Object.keys(raw)) {
        const from = String(key).trim().toLowerCase();
        const to = typeof raw[key] === "string" ? raw[key].trim().toLowerCase() : "";
        if (from.length > 0 && to.length > 0 && from !== to) {
            out[from] = to;
        }
    }
    return out;
}

function resolveRetiredModel(modelId, retiredModels, maxHops) {
    if (typeof modelId !== "string") return "";
    const start = modelId.trim().toLowerCase();
    if (start.length === 0) return "";
    if (!isPlainObject(retiredModels)) return start;
    const limit = (typeof maxHops === "number" && Number.isFinite(maxHops) && maxHops > 0)
        ? Math.floor(maxHops) : MAX_RETIREMENT_HOPS;
    let cur = start;
    const seen = Object.create(null);
    seen[cur] = true;
    for (let hop = 0; hop < limit; hop++) {
        if (!Object.prototype.hasOwnProperty.call(retiredModels, cur)) break;
        const nextRaw = retiredModels[cur];
        if (typeof nextRaw !== "string") break;
        const next = nextRaw.trim().toLowerCase();
        if (next.length === 0) break;
        if (seen[next]) return start;
        seen[next] = true;
        cur = next;
    }
    return cur;
}

function findRetirementCycle(retiredModels, maxHops) {
    if (!isPlainObject(retiredModels)) return null;
    const limit = (typeof maxHops === "number" && Number.isFinite(maxHops) && maxHops > 0)
        ? Math.floor(maxHops) : 64;
    for (const key of Object.keys(retiredModels)) {
        const start = String(key).trim().toLowerCase();
        if (!start) continue;
        const path = [start];
        const seen = Object.create(null);
        seen[start] = 0;
        let cur = start;
        for (let hop = 0; hop < limit; hop++) {
            if (!Object.prototype.hasOwnProperty.call(retiredModels, cur)) break;
            const nextRaw = retiredModels[cur];
            if (typeof nextRaw !== "string") break;
            const next = nextRaw.trim().toLowerCase();
            if (!next) break;
            if (seen[next] !== undefined) {
                return path.slice(seen[next]).concat([next]);
            }
            seen[next] = path.length;
            path.push(next);
            cur = next;
        }
    }
    return null;
}

function parseCatalog(rawTextOrObject) {
    let data = rawTextOrObject;
    if (typeof rawTextOrObject === "string") {
        if (rawTextOrObject.trim().length === 0) {
            return { ok: false, error: "empty-input", detail: "Catalog input is empty" };
        }
        try {
            data = JSON.parse(rawTextOrObject);
        } catch (e) {
            return { ok: false, error: "invalid-json", detail: String(e) };
        }
    }
    if (!isPlainObject(data)) {
        return { ok: false, error: "invalid-root", detail: "Catalog root must be a JSON object" };
    }
    if (data.schemaVersion !== SUPPORTED_SCHEMA_VERSION) {
        return {
            ok: false,
            error: "unsupported-schema",
            schemaVersion: data.schemaVersion,
            detail: `Unsupported schemaVersion: ${String(data.schemaVersion)}`
        };
    }

    const warnings = [];

    const thinkingProfiles = {};
    if (isPlainObject(data.thinkingProfiles)) {
        for (const name of Object.keys(data.thinkingProfiles)) {
            const clean = sanitizeThinkingProfile(data.thinkingProfiles[name]);
            if (clean) thinkingProfiles[name] = clean;
            else warnings.push(`Skipping invalid thinkingProfile '${name}'`);
        }
    }

    const geminiApiCatalog = {};
    if (isPlainObject(data.geminiApiCatalog)) {
        for (const id of Object.keys(data.geminiApiCatalog)) {
            const entry = _sanitizeApiModelEntry(id, data.geminiApiCatalog[id], thinkingProfiles, "gemini", warnings);
            if (entry) geminiApiCatalog[id] = entry;
        }
    }

    const apiModels = {};
    if (isPlainObject(data.apiModels)) {
        for (const id of Object.keys(data.apiModels)) {
            const entry = _sanitizeApiModelEntry(id, data.apiModels[id], thinkingProfiles, "", warnings);
            if (entry) apiModels[id] = entry;
        }
    }

    const cliPlans = {};
    if (isPlainObject(data.cliPlans)) {
        for (const fmt of Object.keys(data.cliPlans)) {
            if (!CLI_FORMATS.includes(fmt)) {
                warnings.push(`Skipping unsupported CLI plan '${fmt}'`);
                continue;
            }
            const rawPlan = data.cliPlans[fmt];
            if (!isPlainObject(rawPlan)) continue;
            const planOut = {};
            if (fmt === "codex-cli") {
                const legacyIds = {};
                if (isPlainObject(rawPlan.legacyIds)) {
                    for (const slug of Object.keys(rawPlan.legacyIds)) {
                        const target = rawPlan.legacyIds[slug];
                        if (typeof target === "string" && target.trim().length > 0) {
                            legacyIds[slug] = target.trim();
                        }
                    }
                }
                planOut.legacyIds = legacyIds;
                planOut.fallbackCatalog = _sanitizeCodexFallbackCatalog(rawPlan.fallbackCatalog, warnings);
            } else {
                const models = {};
                if (isPlainObject(rawPlan.models)) {
                    for (const id of Object.keys(rawPlan.models)) {
                        const entry = _sanitizeCliPlanModel(id, rawPlan.models[id], thinkingProfiles, warnings);
                        if (entry) models[id] = entry;
                    }
                }
                const modelKeys = Object.keys(models);
                const rawFirst = _nonEmptyString(rawPlan.firstPick, "");
                planOut.firstPick = (rawFirst && models[rawFirst]) ? rawFirst : (modelKeys[0] ?? "");
                planOut.models = models;
            }
            if (typeof rawPlan.icon === "string" && rawPlan.icon.trim().length > 0) planOut.icon = rawPlan.icon.trim();
            if (isSafeEndpoint(rawPlan.endpoint)) planOut.endpoint = rawPlan.endpoint.trim();
            if (isSafeLink(rawPlan.homepage)) planOut.homepage = rawPlan.homepage.trim();
            if (isSafeLink(rawPlan.setupHomepage)) planOut.setupHomepage = rawPlan.setupHomepage.trim();
            cliPlans[fmt] = planOut;
        }
    }

    const totalModels = Object.keys(apiModels).length
        + Object.keys(geminiApiCatalog).length
        + Object.keys(cliPlans).reduce((sum, fmt) => {
            const p = cliPlans[fmt];
            if (Array.isArray(p.fallbackCatalog)) return sum + p.fallbackCatalog.length;
            return sum + Object.keys(p.models || {}).length;
        }, 0);
    if (totalModels === 0) {
        return { ok: false, error: "empty-catalog", detail: "Catalog contains no valid models" };
    }

    const rawDefaults = isPlainObject(data.defaults) ? data.defaults : {};
    const geminiIds = Object.keys(geminiApiCatalog);
    const rawGeminiDefault = _nonEmptyString(rawDefaults.geminiDefaultModel, "");
    const geminiDefaultModel = (rawGeminiDefault && geminiApiCatalog[rawGeminiDefault])
        ? rawGeminiDefault
        : (geminiIds[0] || "gemini-flash-latest");
    const defaults = {
        geminiDefaultModel: geminiDefaultModel,
        ollamaSuggestedModel: _nonEmptyString(rawDefaults.ollamaSuggestedModel, "llama3.2:3b"),
        fallbackOnlineModel: _nonEmptyString(rawDefaults.fallbackOnlineModel, "gemini"),
    };

    const rawGroup = isPlainObject(data.geminiGroup) ? data.geminiGroup : {};
    const geminiGroup = {
        id: _nonEmptyString(rawGroup.id, "gemini"),
        name: _nonEmptyString(rawGroup.name, "Gemini"),
        icon: _nonEmptyString(rawGroup.icon, "google-gemini-symbolic"),
        homepage: isSafeLink(rawGroup.homepage) ? rawGroup.homepage.trim() : "https://aistudio.google.com",
        key_id: _nonEmptyString(rawGroup.key_id, "gemini"),
        key_get_link: isSafeLink(rawGroup.key_get_link) ? rawGroup.key_get_link.trim() : "https://aistudio.google.com/app/apikey",
        keyInstructionKey: _nonEmptyString(rawGroup.keyInstructionKey, "gemini-free"),
    };

    const retiredModels = _sanitizeRetiredModels(data.retiredModels);
    const cycle = findRetirementCycle(retiredModels);
    if (cycle) {
        warnings.push(`Cycle detected in retiredModels: ${cycle.join(" -> ")}`);
    }

    return {
        ok: true,
        warnings: warnings,
        catalog: {
            schemaVersion: SUPPORTED_SCHEMA_VERSION,
            catalogVersion: _nonEmptyString(data.catalogVersion, ""),
            defaults: defaults,
            thinkingProfiles: thinkingProfiles,
            geminiGroup: geminiGroup,
            geminiApiCatalog: geminiApiCatalog,
            apiModels: apiModels,
            cliPlans: cliPlans,
            retiredModels: retiredModels,
            translations: _sanitizeTranslations(data.translations),
        }
    };
}

// A string the catalog brings, such as the description of a model newer than
// the shell's own translations, is looked up in the catalog first.
function trCatalog(text, languageCode, catalogTranslations, fallbackTranslator) {
    if (!text) return "";
    const key = String(text);
    const table = isPlainObject(catalogTranslations) ? catalogTranslations[languageCode] : null;
    if (isPlainObject(table) && Object.prototype.hasOwnProperty.call(table, key)) return table[key];
    return typeof fallbackTranslator === "function" ? fallbackTranslator(key) : key;
}
