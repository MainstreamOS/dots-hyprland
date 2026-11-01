# Simplified Chinese completion notes

Catalog: `zh_CN.json`. Source: all 3,221 keys of `en_US.json`, based on mainstream `10067ac75`.

Completed 2,243 previously English-identical values. Corrected 28 existing translations for concrete defects or glossary inconsistencies; the other 887 existing translations are preserved. All 65 remaining English-identical values are intentional and individually listed below. Bluetooth and Google Lens were restored literally from old localized values, so the unchanged count also includes those two restored names. Keys and their order are unchanged.

## Validation and review

- Every batch passed structural validation before writing. The full catalog passes `python3 tools/catalog-qa.py zh_CN`: JSON uniqueness and exact source key set, placeholders and printf order, real line breaks, joining whitespace, markup and Markdown, protected names, numbers, URLs, paths, flags and config filenames.
- All 47 printf-format messages were exercised through the actual `sdata/lib/tr.sh` translator with distinct arguments. English key order matches exactly and an additional slash-command audit passes.
- Twelve validator regression tests pass. Separate checker commits handle Chinese punctuation and Unicode ellipses around paths/URLs without accepting changed destinations; catalog content is kept in its own commit.
- A separate fresh-context review covered 1,305 unique keys: a 200-key source-feature sample across 83 buckets, all 321 actual runtime-placeholder keys plus Zerochan's percent-encoded URL, 695 warning/destructive/access/recovery candidates, 157 supplementary candidates, every final English-identical value and the ambiguity/correction checks. Sets overlap and are deduplicated. Corrections through zh-12 were reread before acceptance.
- Sampling groups keys by the first candidate source: settings/<first component after modules/settings/>, desktop/<first after modules/ii/>, services/AI when the source contains /Ai. or /ai/, otherwise services/other; sdata/ becomes scripts; no location becomes legacy; other paths use apps/<basename>. Sort buckets lexically and each bucket's keys by raw SHA256 of `zh_CN-fresh-context-review-v1` + NUL + key. Select round-robin by bucket item index until 200.
- Compact UTF-8 JSON serialization of the sample keys (`ensure_ascii=False`, separators comma and colon) has SHA256 `2827baeecb3a88c4a40c00de9924627b98cee46d3050eadef3b44d14c3500070`. The 1,305 inspected keys in English catalog order hash to `c16a2eb1c79be21f8011b978082b6a9fbb7082fd7645c9e4a3a7d7d14be7b641` with the same serialization.
- Source checks preserve boot/EFI/hibernation consequences, read-only recovery, account rights, sharing/firewall conditions, privacy, pairing checks and assistant approval duration. Junction is the GPU hotspot; Call is a history noun; Calling is outgoing. The launcher full-list switch is scoped to overview being disabled, not all application windows.
- Root also read the existing translations and scanned recurring glossary terms. Sound context-specific translations remain: Border 内圈 is the clock date style, Visibility 能见度 is weather, Launch on startup 启动时锁屏 controls lock.launchOnStartup. Token count uses 词元; access tokens use 访问令牌. Existing Bar terminology remains 条栏 throughout the translated interface.
- No native-speaker review or live language preview was performed. These are translations with automated validation and a separate review.

## Existing translations corrected

| Exact English key | Reason |
| --- | --- |
| Bluetooth devices | Preserve the exact technology/product name required by the handoff, including the ASCII Wi-Fi hyphen. |
| Usage: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt><br>Supply <tt>i</tt> when you want images<br>Examples:<br><tt>%1superpaste 4i</tt> for the last 4 images<br><tt>%1superpaste 7</tt> for the last 7 entries | Restore literal command metavariables or argument syntax; these had been translated. |
| Lap | Name the stopwatch lap action 计圈, rather than generic timekeeping; match its adjacent instructions. |
| Clean stuff \| Excellent quality, no NSFW | Describe non-NSFW content rather than cleaning-related content. |
| Usage: %1tool TOOL_NAME | Restore literal command metavariables or argument syntax; these had been translated. |
| Waifus only \| Excellent quality, limited quantity | Retain the specific waifu/female anime-character meaning omitted by generic characters. |
| Could be better if you make a ton of typos,<br>but results can be weird and might not work with acronyms<br>(e.g. "GIMP" might not give you the paint program) | Restore the original real line breaks and preserve the description and conditions. |
| Connect to Wi-Fi | Preserve the exact technology/product name required by the handoff, including the ASCII Wi-Fi hyphen. |
| Bluetooth | Preserve the exact technology/product name required by the handoff, including the ASCII Wi-Fi hyphen. |
| To set an API key, pass it with the %4 command<br><br>To view the key, pass "get" with the command<br/><br><br>### For %1:<br><br>**Link**: %2<br><br>%3 | Use ASCII quotes around the literal typed get argument. |
| When enabled keeps the content of the right sidebar loaded to reduce the delay when opening,<br>at the cost of around 15MB of consistent RAM usage. Delay significance depends on your system's performance.<br>Using a custom kernel like linux-cachyos might help | Restore the line breaks and exact RAM identifier while preserving the memory/performance caveats. |
| Usage: %1save CHAT_NAME | Restore literal command metavariables or argument syntax; these had been translated. |
| Usage: %1load CHAT_NAME | Restore literal command metavariables or argument syntax; these had been translated. |
| Unmuted | Name the unmuted audio state instead of a generic opened state. |
| Why this is cool:<br>For non-0 values, it won't trigger when you reach the<br>screen corner along the horizontal edge, but it will when<br>you do along the vertical edge | Restore the original real line breaks and preserve the description and conditions. |
| Audio input \| Right-click for volume mixer & device selector | Use the sound existing 音量混合器 mixer term, rather than a sound synthesizer. |
| Region selector (screen snipping/Google Lens) | Preserve the exact technology/product name required by the handoff, including the ASCII Wi-Fi hyphen. |
| Could be images or parts of the screen that have some containment.<br>Might not always be accurate.<br>This is done with an image processing algorithm run locally and no AI is used. | Restore the original real line breaks and preserve the description and conditions. |
| Google Lens | Preserve the exact technology/product name required by the handoff, including the ASCII Wi-Fi hyphen. |
| Padding | Use the UI internal-padding term instead of an unsupported extra-margin qualifier. |
| Audio output \| Right-click for volume mixer & device selector | Use the sound existing 音量混合器 mixer term, rather than a sound synthesizer. |
| **Pricing**: free tier and pay-as-you-go.<br><br>**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project, go to Get API key | Correct the mistyped pay-as-you-go expression to 按量付费. |
| Signed in. The plan models are in the picker now: type /model to choose between Gemini 3.8 Flash (High, Medium, Low) and Gemini 3.1 Pro (High, Low). | Identify subscription models, distinct from execution Plan. |
| Set thinking level (reasoning effort). Values: minimal, low, medium, high, auto. Replaces deprecated thinking budget. | Use the established 推理强度 reasoning-effort term. |
| Signed in. Gemini Flash and Gemini Pro are in the picker now. Adjust thinking level with the reasoning pill or /think. | Name the reasoning capsule, rather than medication. |
| High — Deep thinking & complex math | Keep High distinct from Max instead of calling both the highest level. |
| Commands: /model <name> · /mode [ask\|auto\|plan] | Restore literal command metavariables or argument syntax; these had been translated. |
| Only local models are allowed right now. To use online models, set AI to Yes in Settings > Interface > Left Sidebar. | Translate the remaining Left Sidebar breadcrumb to its actual label. |

## Intentionally English-identical values

Each remaining value was checked individually. None is untranslated English prose.

| Exact English key | Reason |
| --- | --- |
| illogical-impulse | Preserved product, project, executable, command label or named layout. |
| GitHub | Preserved product, project, executable, command label or named layout. |
| Cloudflare WARP (1.1.1.1) | Preserved product, project, executable, command label or named layout. |
| Bluetooth | Preserved product, project, executable, command label or named layout. |
| AI | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| Cloudflare WARP | Preserved product, project, executable, command label or named layout. |
| EasyEffects | Preserved product, project, executable, command label or named layout. |
| Google Lens | Preserved product, project, executable, command label or named layout. |
| %1 nits | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| %1s | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| %1s… | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| %1… | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| 0° | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| 50 % APL  ·  %1 nits | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| dd/MM | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| dd.MM | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| LCD HDR 1000 | Preserved product, project, executable, command label or named layout. |
| LCD HDR 600 | Preserved product, project, executable, command label or named layout. |
| MM/dd | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| OLED / QD-OLED | Preserved product, project, executable, command label or named layout. |
| VRAM: | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| DaVinci Resolve | Preserved product, project, executable, command label or named layout. |
| DaVinci Resolve Studio | Preserved product, project, executable, command label or named layout. |
| Master | Preserved product, project, executable, command label or named layout. |
| Monocle | Preserved product, project, executable, command label or named layout. |
| OBS Studio | Preserved product, project, executable, command label or named layout. |
| end-4 — Dotfiles | Preserved product, project, executable, command label or named layout. |
| %1 (%2) | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| Discord | Preserved product, project, executable, command label or named layout. |
| GitHub Sponsors | Preserved product, project, executable, command label or named layout. |
| Ko-fi | Preserved product, project, executable, command label or named layout. |
| Patreon | Preserved product, project, executable, command label or named layout. |
| CRT | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| Mainstream dotfiles — updatems | Preserved product, project, executable, command label or named layout. |
| ok | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| updatems | Preserved product, project, executable, command label or named layout. |
| updatems-system | Preserved product, project, executable, command label or named layout. |
| macrecovery | Preserved product, project, executable, command label or named layout. |
| <none> | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| GIMP | Preserved product, project, executable, command label or named layout. |
| Krita | Preserved product, project, executable, command label or named layout. |
| LibreOffice | Preserved product, project, executable, command label or named layout. |
| OnlyOffice | Preserved product, project, executable, command label or named layout. |
| Sunshine | Preserved product, project, executable, command label or named layout. |
| Moonlight | Preserved product, project, executable, command label or named layout. |
| Blender | Preserved product, project, executable, command label or named layout. |
| 15 fps | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| 30 fps | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| WiVRn | Preserved product, project, executable, command label or named layout. |
| Antigravity CLI — agy update | Preserved product, project, executable, command label or named layout. |
| Antigravity: | Preserved product, project, executable, command label or named layout. |
| Ollama | Preserved product, project, executable, command label or named layout. |
| UltraCode | Preserved product, project, executable, command label or named layout. |
| GIF | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| Instagram Reel | Preserved product, project, executable, command label or named layout. |
| %1 B | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| %1 KB | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| %1 MB | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| %1 GB | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| LocalSend | Preserved product, project, executable, command label or named layout. |
| RAM | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| CPU | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| Ethernet | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| Wi-Fi | Unit, format, acronym, placeholder-only label or updater status/sentinel. |
| Dwindle | Preserved product, project, executable, command label or named layout. |

## Shared-key decisions and source issues

- `Play` is both a gaming category (`welcome-tutorial.qml:876`) and six media playback buttons. 播放 correctly serves the actionable media controls but is a compromise for the gaming heading, which needs its own source key. No source key was changed.
- `From` 从 and `To` 至 cover both gradient endpoints and the message recipient label without inventing context markers. The clock date style Border keeps 内圈, while actual window-border controls use 边框.
- `Interface` also serves an assistant-role fallback; keep 界面. Execution Plan uses 计划, while subscription access uses 订阅. The Locked binding flag's explanation clarifies that the shortcut works while locked.
- The streaming-privacy setting says while streaming, but IslandPhonePrivacy.qml suppresses alerts whenever selected Discord/OBS windows or processes exist, without verifying an active stream. The translation preserves presentation-only hiding; this source behavior needs a separate product decision.
- Preserve boot entries `Snapshots` and `linux` literally; recovery descriptions use 快照. Keep executable names, service names, paths and update commands unchanged.
- Older help says Ctrl+P detaches the sidebar, while newer controls use Ctrl+D to detach and Ctrl+P to pin. Supplied shortcuts remain unchanged; reconcile the source separately.
- The historical provider tooltip uses `%2mode PROVIDER`, while execution help uses `ask|auto|plan`. Preserve supplied syntax and flag the inconsistency.
- One update-advice key contains literal `\u2014` text. Its value uses natural Chinese punctuation; the lookup key is unchanged.
- Model/provider descriptions are translated as supplied, not externally verified claims about current pricing, identifiers or capabilities.

## Historical reasoning review

Historical review record. Current rules and display names are consolidated in
[TERMINOLOGY.md](../../TERMINOLOGY.md); the English-preservation decisions in this
old report are superseded where the current guide specifies localized labels.

This is the focused follow-up requested after Ukrainian completion. It applies
the owner’s updated terminology, HANDOFF.md, and corrected es_MX example from
`/home/itsjustdroid/Downloads/updated-reasoning`. It supplements the initial
glossary and completion notes; the decisions below supersede older decisions
on these terms. Good existing values outside concrete findings are preserved.

Changes: **28 of 3,221 values**. Source English keys and order are
unchanged. **77 values remain English-identical**; new ones introduced
by this review are explicitly listed below. Other identical entries retain the
individual audit from the original completion notes.

### Review and checks

- Root read the 90 related entries and all changes. Independent fresh-context review read the complete group-2 packet (360 records across four locales), including this locale’s 90 entries. Source context was checked for ambiguous controls.
- The separate 200-key feature sample and all required placeholder/risk reviews from the original locale completion are retained; this follow-up is a focused re-review, not a claim of another full-catalog linguistic review.
- Final structural checks pass for all 3,221 keys: JSON, key order, placeholders, line breaks/joining whitespace, markup/Markdown/code, names, URLs, paths and flags.
- All 47 printf messages pass through the actual sdata/lib/tr.sh formatter with distinct arguments. Expanded name/identifier and slash-command audits pass.
- The independent reviewer found no further concrete defect in this locale’s focused packet.
- No native-speaker verification or live language preview was performed. Automated checks and independent review do not replace eventual local-user/UI-fit feedback.

### Updated terminology decisions

| English | Final label |
| --- | --- |
| Material cookie | Material cookie |
| Cookie | Cookie |
| Dotfiles | Dotfiles |
| Superpaste | Superpaste |
| Dynamic Island | 灵动岛 |
| Island position | 灵动岛位置 |
| Island style | 灵动岛样式 |
| Pills | 胶囊 |
| Hug | 延展 |
| Notch | Notch |
| Earbang protection | 音量突增保护 |
| Unmuted | 已取消静音 |
| Home | 主文件夹 |
| Swap | 虚拟内存 |
| Tray | 托盘 |
| System tray | 系统托盘 |
| Blur | 模糊 |

All seven named palette presets stay in English: Fruit Salad, Neutral, Tonal Spot, Expressive, Rainbow, Fidelity, Monochrome.
Hyprland scratchpad, submap, fake fullscreen and pseudo-tiling stay literal.
Capitalization such as Material Cookie remains where it is already recognizable
English and correct for the locale; no case-only rewrites were made.

灵动岛 remains the established localized Dynamic Island name, an explicit
exception allowed by the guidance. Its existing compact compounds remain.
主文件夹 is the established personal-folder label. 已取消静音 is already a
natural restored-audio state, so it was preserved.

### Exact value changes

| Exact English key | Previous committed value | Reviewed value | Reason |
| --- | --- | --- | --- |
| Material cookie | Material 曲奇 | Material cookie | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Fruit Salad | 水果沙拉 | Fruit Salad | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Dotfiles | 配置文件 | Dotfiles | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Neutral | 中性 | Neutral | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Tonal Spot | 色调点 | Tonal Spot | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Expressive | 表现力 | Expressive | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Hug | 贴合 | 延展 | Name the edge-spanning style; the earlier wording meant an embrace or attachment to an edge. |
| Superpaste | 超级粘贴 | Superpaste | Preserve the Superpaste command/feature name. |
| Rainbow | 彩虹 | Rainbow | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Fidelity | 保真 | Fidelity | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Earbang protection | 防爆音保护 | 音量突增保护 | Name sudden volume-jump protection concisely; this is neither visual flashing nor headphone hardware protection. |
| Cookie clock settings | 曲奇时钟设置 | Cookie 时钟设置 | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Monochrome | 单色 | Monochrome | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Use old sine wave cookie implementation | 使用旧版正弦波形曲奇实现 | 使用旧版正弦波形 Cookie 实现 | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Anti-flashbang | 防高亮保护 | 防闪 | Use the same visual-flash-protection term as the other levels of this control. |
| Cookie | 曲奇 | Cookie | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Enter submap | 进入快捷键子映射 | 进入 submap | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Special (scratchpad) | 特殊（暂存区） | 特殊（scratchpad） | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle fake fullscreen | 切换伪全屏 | 切换 fake fullscreen | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle pseudo-tiling | 切换伪平铺 | 切换 pseudo-tiling | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle scratchpad | 切换暂存区 | 切换 scratchpad | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| How deep the frost goes. Deeper costs more to draw. | 毛玻璃效果的深度。越深，绘制开销越大。 | 模糊的深度。越深，绘制开销越大。 | Use the chosen blur term consistently for blur and frosted surfaces. |
| no frost | 无毛玻璃 | 无模糊 | Use the chosen blur term consistently for blur and frosted surfaces. |
| Notch | 凹口 | Notch | Preserve Notch as the named drawn style, not a physical hardware-cutout noun. |
| Toggle the scratchpad workspace | 切换暂存工作区 | 切换 scratchpad 工作区 | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Exit the keybind submap | 退出快捷键子映射 | 退出快捷键 submap | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Thinking Level: %1<br>Click to cycle (minimal → low → medium → high → auto) | 思考级别：%1<br>点击切换（minimal → low → medium → high → auto） | 思考级别：%1<br>点击切换（最低 → 低 → 中 → 高 → 自动） | Translate visible click-cycle effort labels; accepted typed command arguments elsewhere remain literal. |
| Frosted widget backgrounds | 毛玻璃小组件背景 | 模糊小组件背景 | Use the chosen blur term consistently for blur and frosted surfaces. |

### Newly English-identical values

These are restored names/identifiers, not untranslated prose.

- "Material cookie"
- "Fruit Salad"
- "Dotfiles"
- "Neutral"
- "Tonal Spot"
- "Expressive"
- "Superpaste"
- "Rainbow"
- "Fidelity"
- "Monochrome"
- "Cookie"
- "Notch"

### Source-confirmed exceptions and remaining limits

- Standalone Swap means memory in Resources.qml, ResourcesPanel.qml and ResourcesPopup.qml. Window-action keys use exchange verbs separately. The offline Spanish interpretation did not have source access.
- at in the automatic-suspend row is a battery percentage. Up %1 is uptime. Home in KeybindCaptureItem.qml is an untranslated X11 keysym and does not share the translated personal-folder call.
- Cookie/Material cookie are shape names; Expressive font is a normal descriptive font role and stays translated. No source strings, commands, accepted arguments, runtime names or configuration keys were changed.
- Longer accurate compounds still need eventual visual fit checks. No explanatory label expansions or new manual wrapping line breaks were added.

## Consolidated display-name pass, 2026-10-31

The current policy and approved terms are consolidated in [TERMINOLOGY.md](../../TERMINOLOGY.md). Earlier English-preservation rules and allowlists above are historical. The current pass changes 12 display values, preserving English keys, command syntax, identifiers and all formatting. These are self-reviewed working choices, not native-speaker-verified.

- "Material cookie" → "Material 饼干"
- "Fruit Salad" → "水果沙拉"
- "Neutral" → "中性"
- "Tonal Spot" → "色调点缀"
- "Expressive" → "表现力"
- "Rainbow" → "彩虹"
- "Fidelity" → "保真"
- "Cookie clock settings" → "饼干时钟设置"
- "Monochrome" → "单色"
- "Use old sine wave cookie implementation" → "使用旧版正弦波饼干实现"
- "Cookie" → "饼干"
- "Notch" → "刘海"

Current intentionally English-identical count: 67. Names, units, literal formats and natural shared vocabulary remain valid; the lower count is not the purpose of this pass.
