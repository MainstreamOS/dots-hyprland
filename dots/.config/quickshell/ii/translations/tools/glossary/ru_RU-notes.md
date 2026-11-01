# Russian completion notes

Catalog: `ru_RU.json`. Source: all 3,221 keys of `en_US.json`, based on mainstream `ab646c20d`.

Completed 2,209 previously English-identical values. Corrected 82 existing translations for concrete defects or glossary inconsistencies; the other 859 existing translations are preserved. All 72 remaining English-identical values are intentional and listed below. The corrected old singular Dotfile now uses the proper unchanged term Dotfiles, so this unchanged count is not simply the baseline count minus new translations. Keys and their order are unchanged.

## Validation and review

- Every batch passed structural validation before writing. The full catalog passes `python3 tools/catalog-qa.py ru_RU`: JSON uniqueness and exact key set, placeholders and printf order, real line breaks, joining whitespace, markup and Markdown, protected names, numbers, URLs, paths, flags and config filenames.
- All 47 printf-format messages were exercised through the actual `sdata/lib/tr.sh` translator with distinct arguments. Exact English key order and a separate slash-command audit pass. Eleven validator regression tests pass.
- A separate fresh-context review covered 1,410 unique keys: a 200-key source-feature sample, all 321 actual runtime-placeholder keys, the Zerochan URL, 502 warning/action/access/error candidates, all 363 mapped phone/Island keys, critical account/recovery/sharing/drive/permission sources, script warnings, all 72 English-identical values and the correction batches. Counts overlap and are deduplicated.
- The sample seed is `ru_RU-review-2026-10-27`. Group by first candidate source's `settings/<first segment>`, `desktop/<first segment>`, `services/<first segment>`, otherwise filename or unmapped. Sort each group by SHA256 of seed + NUL + English key. For n = 0…199, sort remaining nonempty group names, choose n modulo group count, and pop the first key. This selects 200 keys from 107 candidate-source groups. Sample keys joined with newline, no trailing newline, hash to `5440bd6ac3554ce641c8aa323109646266ce98a9f5819183f78f4515d11a219d`; all reviewed keys in English order hash to `0ba57ce8e70b11ee653ba5b72b27274a7e51cc8b822cbb146538fdb598ef8b71`.
- Reviewed catalog SHA256: `1a0b5a3c7418b5749788a84497eb75346c44f2f3783b1465afc6a4237a1e8b6e`. Source contexts confirm hibernation and EFI/kernel warnings, snapshot/read-only recovery, sharing/firewall restrictions, account rights, pairing-code checks, approval duration and streaming-alert scope. Their conditions and consequences are retained.
- Concrete review corrections include the notification-count form, title-bar terminology, gamma and discovered-drive count labels, split-time terminology and the omitted Google Cloud setup steps. Source checks distinguish memory Swap, GPU hotspot Junction, Call as a history noun, and outgoing Calling. `%1 file changed` is used only when the count is exactly 1.
- Glossary scans cover workspaces, dock, sidebars, app drawer, capsules, tray, title bars, themes, sleep, snapshots, pinning, AI modes and subscription models. Sound existing compact labels are preserved rather than restyled.
- No native-speaker review or live language preview was performed. These are translations with automated validation and a separate review.

## Existing translations corrected

| Exact English key | Reason |
| --- | --- |
| Style: Blurred | Restore the Style qualifier on the blurred appearance subsection. |
| No pending tasks | Identify pending tasks rather than a generic empty surface. |
| Critical warning | Name the warning threshold rather than showing only a percentage abbreviation. |
| Web search | Restore the web-search scope omitted by the generic Find action. |
| Full | Correct the opposite meaning: Full had been translated Hollow. |
| Code saved to file | Restore that the saved code is written to a file. |
| No API key<br>Set it with /key YOUR_API_KEY | Restore literal command metavariables and executable syntax; these had been translated. |
| %1 notifications | Use a count-neutral construction; the notification count includes 1 and 2 with no singular branch. |
| Qt apps | Correct the genitive case used as a standalone category label. |
| Usage: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt><br>Supply <tt>i</tt> when you want images<br>Examples:<br><tt>%1superpaste 4i</tt> for the last 4 images<br><tt>%1superpaste 7</tt> for the last 7 entries | Restore literal command metavariables and executable syntax; these had been translated. |
| Reset | Use the glossary UI reset term instead of the nonstandard transliteration Ресет. |
| Dark/Light toggle | Use the glossary switch term consistently instead of тоггл. |
| This is usually safe and needed for your browser and AI sidebar anyway<br>Mostly useful for those who use lock on startup instead of a display manager that does it (GDM, SDDM, etc.) | Use the established ИИ and боковая панель terms for the same assistant sidebar. |
| Shell & utilities | Correct the oblique noun cases used as a standalone section heading. |
| Dotfiles | Keep the established plural project/configuration term instead of the incorrect singular Dotfile. |
| Mic toggle | Use the glossary switch term consistently instead of тоггл. |
| Make sure your player has MPRIS support<br>or try turning off duplicate player filtering | Restore the actual setting meaning instead of inventing the literal filterDuplicatePlayers config key. |
| Pills | Name capsule-shaped UI containers rather than medication or an adjective. |
| API key is set<br>Change with /key YOUR_API_KEY | Restore literal command metavariables and executable syntax; these had been translated. |
| Usage: %1tool TOOL_NAME | Restore literal command metavariables and executable syntax; these had been translated. |
| Workspaces | Remove the unsupported restriction to workspaces on the bar. |
| Calendar | Correct the wrong object Date for the calendar panel. |
| Volume limit | Name the volume limit rather than an unspecified sound threshold. |
| Invalid API provider. Supported: <br>- | Restore API and the source joining whitespace. |
| Hug | Describe the edge-hugging style instead of a capture action; follow the glossary. |
| Tip: right-clicking a group<br>also expands it | Restore the source line break and the notification-group tooltip meaning. |
| Terminal | Correct the genitive noun used as a standalone app label. |
| Keybinds | Use the glossary term consistently with the keybinding editor and settings. |
| Float | Use the glossary term shared by floating surfaces and window layouts. |
| Advanced | Identify advanced settings, rather than unrelated miscellaneous settings. |
| Current tool: %1<br>Set it with %2tool TOOL | Restore literal command metavariables and executable syntax; these had been translated. |
| Allows you to open sidebars by clicking or hovering screen corners regardless of bar position | Restore click/hover triggers and the independent-of-bar-position condition. |
| Load: | Identify CPU/GPU load instead of an ambiguous Used abbreviation. |
| Current model: %1<br>Set it with %2model MODEL | Restore literal command metavariables and executable syntax; these had been translated. |
| Looks a bit softer and more consistent with different number of sides,<br>but has less impressive morphing | Correct the misspelling and translate morphing rather than compression. |
| Can only be turned on using the 'Dots' or 'Full' dial style for aesthetic reasons | Match the corrected Full dial-style label so the instruction identifies a real option. |
| Choose file | Do not restrict the generic file picker action to wallpaper. |
| Timeout duration (if not defined by notification) (ms) | Restore the condition that a notification can supply its own timeout. |
| User agent (for services that require it) | Restore the qualifier limiting user-agent use to services that require it. |
| Transparency | Keep the appearance property a noun instead of changing it to an enable action. |
| %1   •   %2 tasks | Use a count-neutral construction valid for every count, including 1. |
| Temperature<br>Change with /temp VALUE | Restore literal command metavariables and executable syntax; these had been translated. |
| Night Light \| Right-click to toggle Auto mode | Use the existing Night Light term consistently with its other controls. |
| . Notes for Zerochan:<br>- You must enter a color<br>- Set your zerochan username in `sidebar.booru.zerochan.username` config option. You [might be banned for not doing so](https://www.zerochan.net/api#:~:text=The%20request%20may%20still%20be%20completed%20successfully%20without%20this%20custom%20header%2C%20but%20your%20project%20may%20be%20banned%20for%20being%20anonymous.)! | Restore the exact Zerochan URL, including its final period, and identify the required username setting. |
| Content | Correct the prepositional phrase used as a standalone palette option. |
| Style: general | Restore the Style qualifier on the general appearance subsection. |
| Free: | Identify free memory rather than the ambiguous Exists label. |
| Current API endpoint: %1<br>Set it with %2mode PROVIDER | Restore literal command metavariables and executable syntax; these had been translated. |
| Border | Correct the wrong concept Circular for a border control. |
| When enabled keeps the content of the right sidebar loaded to reduce the delay when opening,<br>at the cost of around 15MB of consistent RAM usage. Delay significance depends on your system's performance.<br>Using a custom kernel like linux-cachyos might help | Restore the literal MB and RAM units/names while preserving the opening-delay and kernel caveats. |
| %1 characters | Use a count-neutral construction valid for every count, including 1. |
| **Pricing**: free. Data used for training.<br><br>**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key | Restore Google Cloud and the alternative setup steps omitted from the instruction. |
| Usage: %1save CHAT_NAME | Restore literal command metavariables and executable syntax; these had been translated. |
| Commands, edit configs, search.<br>Takes an extra turn to switch to search mode if that's needed | Restore the extra-turn cost of switching to search mode. |
| Background | Use the general background term, distinct from desktop wallpaper. |
| Switched to search mode. Continue with the user's request. | Restore the explicit instruction to continue the user's request. |
| Performance Profile toggle | Use the glossary switch term and retain the full profile meaning. |
| Usage: %1load CHAT_NAME | Restore literal command metavariables and executable syntax; these had been translated. |
| Language not listed or incomplete translations?<br>You can choose to generate translations for it with Gemini.<br>1. Open the left sidebar with Super+A, set model to Gemini (if it isn't already)<br>2. Type /key, hit Enter and follow the instructions<br>3. Type /key YOUR_API_KEY<br>4. Type the locale of your language below and press Generate | Restore literal command metavariables and executable syntax; these had been translated. |
| Locale code, e.g. fr_FR, de_DE, zh_CN... | Restore the exact source example locale identifiers. |
| Use system file picker | Distinguish a file-selection dialog from a file manager app. |
| Windows | Correct the genitive plural used as a standalone Windows category. |
| Unmuted | Use clear sound-state wording rather than a nonstandard truncated label. |
| Why this is cool:<br>For non-0 values, it won't trigger when you reach the<br>screen corner along the horizontal edge, but it will when<br>you do along the vertical edge | Restore the explicit 0 condition and all source line breaks. |
| Layers | Correct the genitive plural used as a standalone layer label. |
| Quick toggles | Use the glossary switch term consistently instead of тогглы. |
| Muted | Use the same clear sound-state pair as Unmuted. |
| Edit quick toggles | Use the glossary switch term consistently instead of тогглы. |
| with vertical offset | Restore the missing preposition in this joining phrase. |
| Rectangular selection | Restore the rectangle shape instead of calling it a generic normal selection. |
| Normal | Serve both normal number style and normal keybinding type; Arabic is wrong for keybindings. |
| Pin | Use a complete action verb consistent with the dock and tray pin controls. |
| Unpin | Use a complete action verb consistent with the dock and tray unpin controls. |
| Aligns the date and quote to left, center or right depending on its position on the screen. | Restore the date/quote objects and the three alignment choices. |
| Click to show | Click does not require holding the mouse button. |
| Display modifiers and keys in multiple keycap (e.g., "Ctrl + A" instead of "Ctrl A" or "󰘴 + A" instead of "󰘴 A") | Restore separate keycaps and the omitted symbol examples. |
| Font weight | Remove the spurious trailing space from the label. |
| **Pricing**: free tier, with data used for training. Web search needs billing turned on.<br><br>**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key | Restore Google Cloud and the alternative setup steps omitted from the instruction. |
| Signed in. The plan models are in the picker now: type /model to choose between Gemini 3.8 Flash (High, Medium, Low) and Gemini 3.1 Pro (High, Low). | Distinguish subscription models from execution Plan mode. |
| Signed in. Gemini Flash and Gemini Pro are in the picker now. Adjust thinking level with the reasoning pill or /think. | Identify the reasoning capsule using the glossary container term. |
| Commands: /model <name> · /mode [ask\|auto\|plan] | Restore literal command metavariables and executable syntax; these had been translated. |
| Only local models are allowed right now. To use online models, set AI to Yes in Settings > Interface > Left Sidebar. | Translate the remaining English navigation breadcrumb to its actual Russian label. |

## Intentionally English-identical values

Each remaining value was individually audited. None is untranslated English prose.

| Exact English key | Reason |
| --- | --- |
| OK | Unit, technology/format identifier, command status token or placeholder-only text. |
| illogical-impulse | Product, project, executable or named layout/style. |
| Dotfiles | Product, project, executable or named layout/style. |
| Superpaste | Product, project, executable or named layout/style. |
| GitHub | Product, project, executable or named layout/style. |
| Cloudflare WARP (1.1.1.1) | Product, project, executable or named layout/style. |
| Bluetooth | Product, project, executable or named layout/style. |
| Cloudflare WARP | Product, project, executable or named layout/style. |
| Android | Product, project, executable or named layout/style. |
| EasyEffects | Product, project, executable or named layout/style. |
| Google Lens | Product, project, executable or named layout/style. |
| %1 nits | Unit, technology/format identifier, command status token or placeholder-only text. |
| %1s | Unit, technology/format identifier, command status token or placeholder-only text. |
| %1s… | Unit, technology/format identifier, command status token or placeholder-only text. |
| %1… | Unit, technology/format identifier, command status token or placeholder-only text. |
| 0° | Unit, technology/format identifier, command status token or placeholder-only text. |
| 50 % APL  ·  %1 nits | Unit, technology/format identifier, command status token or placeholder-only text. |
| dd/MM | Unit, technology/format identifier, command status token or placeholder-only text. |
| dd.MM | Unit, technology/format identifier, command status token or placeholder-only text. |
| LCD HDR 1000 | Unit, technology/format identifier, command status token or placeholder-only text. |
| LCD HDR 600 | Unit, technology/format identifier, command status token or placeholder-only text. |
| MM/dd | Unit, technology/format identifier, command status token or placeholder-only text. |
| OLED / QD-OLED | Unit, technology/format identifier, command status token or placeholder-only text. |
| VRAM: | Unit, technology/format identifier, command status token or placeholder-only text. |
| DaVinci Resolve | Product, project, executable or named layout/style. |
| DaVinci Resolve Studio | Product, project, executable or named layout/style. |
| Master | Product, project, executable or named layout/style. |
| Monocle | Product, project, executable or named layout/style. |
| OBS Studio | Product, project, executable or named layout/style. |
| end-4 — Dotfiles | Product, project, executable or named layout/style. |
| %1 (%2) | Unit, technology/format identifier, command status token or placeholder-only text. |
| Discord | Product, project, executable or named layout/style. |
| GitHub Sponsors | Product, project, executable or named layout/style. |
| Ko-fi | Product, project, executable or named layout/style. |
| Patreon | Product, project, executable or named layout/style. |
| CRT | Unit, technology/format identifier, command status token or placeholder-only text. |
| ok | Unit, technology/format identifier, command status token or placeholder-only text. |
| updatems | Product, project, executable or named layout/style. |
| updatems-system | Product, project, executable or named layout/style. |
| macrecovery | Product, project, executable or named layout/style. |
| AUR (yay/paru): | Unit, technology/format identifier, command status token or placeholder-only text. |
| Flatpak: | Unit, technology/format identifier, command status token or placeholder-only text. |
| Snap: | Unit, technology/format identifier, command status token or placeholder-only text. |
| Dotfiles (updatems): | Unit, technology/format identifier, command status token or placeholder-only text. |
| <none> | Unit, technology/format identifier, command status token or placeholder-only text. |
| GIMP | Product, project, executable or named layout/style. |
| Krita | Product, project, executable or named layout/style. |
| LibreOffice | Product, project, executable or named layout/style. |
| OnlyOffice | Product, project, executable or named layout/style. |
| Sunshine | Product, project, executable or named layout/style. |
| Moonlight | Product, project, executable or named layout/style. |
| Blender | Product, project, executable or named layout/style. |
| 15 fps | Unit, technology/format identifier, command status token or placeholder-only text. |
| 30 fps | Unit, technology/format identifier, command status token or placeholder-only text. |
| WiVRn | Product, project, executable or named layout/style. |
| Antigravity CLI — agy update | Product, project, executable or named layout/style. |
| Antigravity: | Product, project, executable or named layout/style. |
| Ollama | Product, project, executable or named layout/style. |
| UltraCode | Product, project, executable or named layout/style. |
| GIF | Unit, technology/format identifier, command status token or placeholder-only text. |
| Instagram Reel | Product, project, executable or named layout/style. |
| %1 B | Unit, technology/format identifier, command status token or placeholder-only text. |
| %1 KB | Unit, technology/format identifier, command status token or placeholder-only text. |
| %1 MB | Unit, technology/format identifier, command status token or placeholder-only text. |
| %1 GB | Unit, technology/format identifier, command status token or placeholder-only text. |
| LocalSend | Product, project, executable or named layout/style. |
| RAM | Unit, technology/format identifier, command status token or placeholder-only text. |
| CPU | Unit, technology/format identifier, command status token or placeholder-only text. |
| Ethernet | Unit, technology/format identifier, command status token or placeholder-only text. |
| Wi-Fi | Unit, technology/format identifier, command status token or placeholder-only text. |
| Dynamic Island | Product, project, executable or named layout/style. |
| Dwindle | Product, project, executable or named layout/style. |

## Shared-key decisions and source issues

- `To` serves the gradient end-color field (`DecorationsConfig.qml:1211`) and a new-message recipient (`PhoneThreadView.qml:960`). Existing До fits the gradient, but the recipient needs Кому. Keep До under the source-edit restriction; separate source keys are needed for a fully correct recipient label.
- `Play` is the gaming category (`welcome-tutorial.qml:876`) and the playback action (`PhoneAudioAttachment.qml:48`, `PhoneVideoAttachment.qml:211`, `SidebarMediaPlayer.qml:458`). Keep Играть as the agreed compromise. Воспроизвести is the precise media action but would break the gaming category, so separate source keys are preferable.
- `Normal` is used for number style and keybinding type. Обычный works for both; the old Арабский was wrong for keybindings. Memory `Swap` remains Своп; window swapping uses Поменять местами in its specific action keys.
- `Interface` labels both settings and an assistant-role fallback. Keep Интерфейс. Execution Plan uses План; subscription descriptions use Подписка. `Locked` labels clock state and a binding flag; the flag description clarifies that it works while the screen is locked.
- Preserve boot-menu entries `Snapshots` and `linux` literally. Recovery descriptions use снимок. Preserve the supplied kernel commands, service names and package identifiers.
- Older help says Ctrl+P detaches the sidebar, while newer controls use Ctrl+D to detach and Ctrl+P to pin. Supplied shortcuts remain unchanged; reconcile the source separately.
- The historical API-provider tooltip uses `%2mode PROVIDER`, while current execution-mode help lists `ask|auto|plan`. Preserve the supplied syntax and flag the inconsistency.
- One update-advice key contains literal `\u2014` text. Its Russian value uses natural punctuation; the lookup key is unchanged.
- Model/provider descriptions are translated as supplied, not externally verified claims about current prices, identifiers or capabilities.

## Follow-up source clarification

- `Open on all apps when off` controls `overview.showAllAppsWhenOff`: show the complete app list when workspace overview is disabled, rather than applying to every application window. Clarified the label after checking InterfaceConfig.qml:612–632 and Overview.qml:110; a separate focused review confirmed the value.
- The API-key help keeps the typed literal argument `"get"` in ASCII quotes, as required by the handoff. No argument or placeholder changed.

## Historical reasoning review

Historical review record. Current rules and display names are consolidated in
[TERMINOLOGY.md](../../TERMINOLOGY.md); the English-preservation decisions in this
old report are superseded where the current guide specifies localized labels.

This is the focused follow-up requested after Ukrainian completion. It applies
the owner’s updated terminology, HANDOFF.md, and corrected es_MX example from
`/home/itsjustdroid/Downloads/updated-reasoning`. It supplements the initial
glossary and completion notes; the decisions below supersede older decisions
on these terms. Good existing values outside concrete findings are preserved.

Changes: **25 of 3,221 values**. Source English keys and order are
unchanged. **81 values remain English-identical**; new ones introduced
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
| Material cookie | Material Cookie |
| Cookie | Cookie |
| Dotfiles | Dotfiles |
| Superpaste | Superpaste |
| Dynamic Island | Dynamic Island |
| Island position | Положение острова |
| Island style | Стиль острова |
| Pills | Капсулы |
| Hug | Растянутый |
| Notch | Notch |
| Earbang protection | Защита от скачков громкости |
| Unmuted | Звук включён |
| Home | Домашняя папка |
| Swap | Своп |
| Tray | Трей |
| System tray | Системный трей |
| Blur | Размытие |

All seven named palette presets stay in English: Fruit Salad, Neutral, Tonal Spot, Expressive, Rainbow, Fidelity, Monochrome.
Hyprland scratchpad, submap, fake fullscreen and pseudo-tiling stay literal.
Capitalization such as Material Cookie remains where it is already recognizable
English and correct for the locale; no case-only rewrites were made.

### Exact value changes

| Exact English key | Previous committed value | Reviewed value | Reason |
| --- | --- | --- | --- |
| at | в | при | The actual caller is a battery-percentage threshold (PowerConfig.qml:434), not a clock time or physical location. |
| Fruit Salad | Фруктовый салат | Fruit Salad | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Neutral | Нейтральность | Neutral | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Tonal Spot | Тональное пятно | Tonal Spot | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Expressive | Выразительность | Expressive | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Hug | Вдоль края | Растянутый | Name the edge-spanning style; the earlier wording meant an embrace or attachment to an edge. |
| Rainbow | Радуга | Rainbow | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Fidelity | Точность | Fidelity | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Earbang protection | Защита ушей | Защита от скачков громкости | Name sudden volume-jump protection concisely; this is neither visual flashing nor headphone hardware protection. |
| Monochrome | Монохром | Monochrome | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Anti-flashbang | Анти-вспышка | Защита от вспышек | Use the same visual-flash-protection term as the other levels of this control. |
| Cookie | Cookie MD3 | Cookie | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Enter submap | Войти в подрежим клавиш | Войти в submap | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Special (scratchpad) | Специальное (буфер окон) | Специальное (scratchpad) | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle fake fullscreen | Переключить псевдополноэкранный режим | Переключить fake fullscreen | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle pseudo-tiling | Переключить псевдоплиточный режим | Переключить pseudo-tiling | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle scratchpad | Переключить буфер окон | Переключить scratchpad | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| How deep the frost goes. Deeper costs more to draw. | Глубина матового размытия. Более глубокое требует больше ресурсов отрисовки. | Глубина размытия. Более глубокое требует больше ресурсов отрисовки. | Use the chosen blur term consistently for blur and frosted surfaces. |
| Notch | Вырез | Notch | Preserve Notch as the named drawn style, not a physical hardware-cutout noun. |
| Toggle the scratchpad workspace | Переключить пространство буфера окон | Переключить пространство scratchpad | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Exit the keybind submap | Выйти из подрежима клавиш | Выйти из submap клавиш | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Signed in. The plan models are in the picker now: type /model to choose between Gemini 3.8 Flash (High, Medium, Low) and Gemini 3.1 Pro (High, Low). | Вход выполнен. Модели подписки добавлены в список: введите /model для выбора между Gemini 3.8 Flash (High, Medium, Low) и Gemini 3.1 Pro (High, Low). | Вход выполнен. Модели подписки добавлены в список: введите /model для выбора между Gemini 3.8 Flash (высокий, средний, низкий) и Gemini 3.1 Pro (высокий, низкий). | The parenthesized names are visible effort levels, not literal command arguments. |
| Thinking Level: %1<br>Click to cycle (minimal → low → medium → high → auto) | Уровень рассуждений: %1<br>Нажмите для переключения (minimal → low → medium → high → auto) | Уровень рассуждений: %1<br>Нажмите для переключения (минимальный → низкий → средний → высокий → авто) | Translate visible click-cycle effort labels; accepted typed command arguments elsewhere remain literal. |
| Press Super to search apps in the island. | Нажмите Super для поиска приложений в острове. | Нажмите Super для поиска приложений на острове. | Use the locale’s concise Island term in short compounds; the full feature keeps its name. |
| Frosted widget backgrounds | Матовые фоны виджетов | Размытые фоны виджетов | Use the chosen blur term consistently for blur and frosted surfaces. |

### Newly English-identical values

These are restored names/identifiers, not untranslated prose.

- "Fruit Salad"
- "Neutral"
- "Tonal Spot"
- "Expressive"
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

- "Material cookie" → "Печенье Material"
- "Fruit Salad" → "Фруктовый салат"
- "Neutral" → "Нейтральная"
- "Tonal Spot" → "Тональный акцент"
- "Expressive" → "Выразительная"
- "Rainbow" → "Радуга"
- "Fidelity" → "Точность цвета"
- "Cookie clock settings" → "Настройки часов «Печенье»"
- "Monochrome" → "Монохромная"
- "Use old sine wave cookie implementation" → "Использовать старую реализацию «Печенья» на синусоиде"
- "Cookie" → "Печенье"
- "Notch" → "Вырез"

Current intentionally English-identical count: 72. Names, units, literal formats and natural shared vocabulary remain valid; the lower count is not the purpose of this pass.
