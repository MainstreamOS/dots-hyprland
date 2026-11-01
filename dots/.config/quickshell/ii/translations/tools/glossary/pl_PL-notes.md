# Polish completion notes

Catalog: `pl_PL.json`. English source: all 3,221 keys, SHA256
`d222d7ae70507e91f555e6bd621ed7b574f7c7f722ff73a8a4826260be17617b`.
Based on current mainstream `5f9bd6f8e`; follows the original translation handoff
and the owner’s updated 2026-10-28 terminology and es_MX reasoning example.

New locale: 3,123 translated values and 98 intentional English-identical
values. No existing Polish translations were replaced. Every remaining identical
value was individually audited below. English keys and order are unchanged.

## Validation and review

- Every batch passed `tools/catalog-qa.py`: exact keys, unique JSON, placeholders and printf argument order, actual newlines and joining whitespace, markup/backticks, protected names, numeric values, paths, flags and URLs.
- All 47 printf messages passed through the actual `sdata/lib/tr.sh` with distinct arguments. Exact catalog order and a separate slash-command audit also pass.
- All 13 validator regression tests pass, as do structural checks on the ten previously completed catalogs.
- Independent fresh-context review read all 1,631 packet records, with no gaps, and reported nine concrete corrections. All nine were fixed and independently reread against the final catalog; no further concrete issue was found.
- The review packet contains 1,631 unique pairs: a 200-key feature sample across 83 source buckets, all 321 runtime-placeholder keys, 497 warning/access/destructive/update/recovery candidates, 376 ambiguity candidates, all final 721 AI/phone/Island keys and all 98 English-identical entries. Sets overlap. The percent-encoded Zerochan URL is checked exactly as a protected URL.
- Sampling groups by first candidate source: settings/<first component after modules/settings/>, desktop/<first after modules/ii/>, services/AI for /Ai. or /ai/, otherwise services/other; sdata/ becomes scripts; absent source becomes legacy; other paths use apps/<basename>. Sort buckets lexically and keys by raw SHA256 of `pl_PL-fresh-context-review-v1` + NUL + key, then take round-robin by bucket depth until 200.
- Compact UTF-8 JSON (`ensure_ascii=False`, comma/colon separators) of sample keys hashes to `ef451ca863b210322f5ce7d47df39a77475a503d2f30fc17555b5c0ed4163dc5`; packet keys in catalog order hash to `d0f1c573692f06752d6a4d576cf4ba101be905696083f54151d4e47ce7334494`.
- Root checked glossary use, assembled fragments, current source for ambiguous labels, and every English-identical value.
- No native-speaker review or live language preview was performed. These are translations with automated checks and a separate review.

## Corrections from independent review

| Exact English key | Correction |
| --- | --- |
| Right-click volume control | Name the volume control inside the context menu, not an instruction to right-click a volume control. |
|  It replaced your saved copy. | Use an impersonal replacement-result suffix that composes with every theme-import message; retain its leading space. |
| Pinned by default | Use masculine singular agreement for the left sidebar. |
| Stop and send voice input (Right click or Esc to cancel) | The AI voice-input path sends transcribed text, not an audio recording. |
| Send voice input | Name the dictated text actually sent by the AI voice-input action. |
| Press Super to search apps in the island. | Use the natural Polish locative phrase na wyspie. |
| Disable calls, messages, and phone notifications while streaming | Hide Island presentation without claiming to disable phone communications. |
| Responsive scheduler | Use the Polish kernel task-scheduler term planista, not a timetable. |
| The scheduler is switched on but could not start. The standard one is running. Check the system log. | Keep kernel-scheduler terminology consistent in the failure notice. |

## Intentionally English-identical values

| Exact English key | Reason |
| --- | --- |
| Material cookie | Preserved product, project, layout, protocol, command or named preset. |
| Gamma | Gamma is the standard Polish color-control term. |
| 12h am/pm | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Fruit Salad | Preserved product, project, layout, protocol, command or named preset. |
| OK | Conventional OK confirmation. |
| illogical-impulse | Preserved product, project, layout, protocol, command or named preset. |
| Dotfiles | Preserved product, project, layout, protocol, command or named preset. |
| Format | Format is also the Polish noun for a display pattern; destructive drive formatting uses a different action key. |
| Neutral | Preserved product, project, layout, protocol, command or named preset. |
| 12h AM/PM | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Anime | Anime is the established genre term. |
| System | System is the Polish noun. |
| Tonal Spot | Preserved product, project, layout, protocol, command or named preset. |
| Expressive | Preserved product, project, layout, protocol, command or named preset. |
| Superpaste | Superpaste is the feature/command name. |
| Rainbow | Preserved product, project, layout, protocol, command or named preset. |
| GitHub | Preserved product, project, layout, protocol, command or named preset. |
| Fidelity | Preserved product, project, layout, protocol, command or named preset. |
| Terminal | Terminal is the Polish application/device term. |
| Cloudflare WARP (1.1.1.1) | Preserved product, project, layout, protocol, command or named preset. |
| 24h | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Bluetooth | Preserved product, project, layout, protocol, command or named preset. |
| Pomodoro | Preserved product, project, layout, protocol, command or named preset. |
| AI | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Cloudflare WARP | Preserved product, project, layout, protocol, command or named preset. |
| Monochrome | Preserved product, project, layout, protocol, command or named preset. |
| Android | Preserved product, project, layout, protocol, command or named preset. |
| Internet | Internet is the Polish technical noun. |
| EasyEffects | Preserved product, project, layout, protocol, command or named preset. |
| Google Lens | Preserved product, project, layout, protocol, command or named preset. |
| %1 nits | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| %1s | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| %1s… | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| %1… | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| 0° | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| 50 % APL  ·  %1 nits | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Cookie | Preserved product, project, layout, protocol, command or named preset. |
| dd/MM | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| dd.MM | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Emoji | Emoji is the established borrowed term. |
| LCD HDR 1000 | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| LCD HDR 600 | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| MM/dd | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| OLED / QD-OLED | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| VRAM: | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Argument | Argument is also the Polish noun. |
| DaVinci Resolve | Preserved product, project, layout, protocol, command or named preset. |
| DaVinci Resolve Studio | Preserved product, project, layout, protocol, command or named preset. |
| Fahrenheit | Preserved product, project, layout, protocol, command or named preset. |
| Master | Preserved product, project, layout, protocol, command or named preset. |
| Monocle | Preserved product, project, layout, protocol, command or named preset. |
| OBS Studio | Preserved product, project, layout, protocol, command or named preset. |
| end-4 — Dotfiles | Preserved product, project, layout, protocol, command or named preset. |
| %1 (%2) | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
|  min | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Notch | Preserved product, project, layout, protocol, command or named preset. |
| Discord | Preserved product, project, layout, protocol, command or named preset. |
| min | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| GitHub Sponsors | Preserved product, project, layout, protocol, command or named preset. |
| Ko-fi | Preserved product, project, layout, protocol, command or named preset. |
| Patreon | Preserved product, project, layout, protocol, command or named preset. |
| CRT | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| updatems | Preserved product, project, layout, protocol, command or named preset. |
| updatems-system | Preserved product, project, layout, protocol, command or named preset. |
| macrecovery | Preserved product, project, layout, protocol, command or named preset. |
| AUR (yay/paru): | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Flatpak: | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Snap: | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Dotfiles (updatems): | Preserved product, project, layout, protocol, command or named preset. |
| <none> | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| GIMP | Preserved product, project, layout, protocol, command or named preset. |
| Krita | Preserved product, project, layout, protocol, command or named preset. |
| LibreOffice | Preserved product, project, layout, protocol, command or named preset. |
| OnlyOffice | Preserved product, project, layout, protocol, command or named preset. |
| Sunshine | Preserved product, project, layout, protocol, command or named preset. |
| Moonlight | Preserved product, project, layout, protocol, command or named preset. |
| Blender | Preserved product, project, layout, protocol, command or named preset. |
| 15 fps | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| 30 fps | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Administrator | Administrator is also the Polish account-role noun. |
| WiVRn | Preserved product, project, layout, protocol, command or named preset. |
| Antigravity CLI — agy update | Preserved product, project, layout, protocol, command or named preset. |
| Antigravity: | Preserved product, project, layout, protocol, command or named preset. |
| Ollama | Preserved product, project, layout, protocol, command or named preset. |
| Plan | Plan is also the Polish planning-mode noun. |
| UltraCode | Preserved product, project, layout, protocol, command or named preset. |
| GIF | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| %1 B | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| %1 KB | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| %1 MB | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| %1 GB | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| LocalSend | Preserved product, project, layout, protocol, command or named preset. |
| RAM | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| CPU | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Ethernet | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Wi-Fi | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Dynamic Island | Preserved product, project, layout, protocol, command or named preset. |
| Dwindle | Preserved product, project, layout, protocol, command or named preset. |

## Shared keys, source context and remaining limits

- Polish has multiple plural forms; the lookup has none. Runtime counts use label forms such as `Pliki: %1`, invariant time units, or abbreviations. The theme-export suffix `images` is `obr.` after a number, valid for 1, 2 and 5. Separately selected singular keys retain their singular wording.
- Reply, recipient and device labels avoid declining unknown user-supplied names. Battery suffixes form `1h do pełnego naładowania` and `1h do rozładowania` in their sole current BatteryStrip caller.
- Standalone `Swap` is Pamięć wymiany: all current callers show resource statistics. The supplied offline Spanish reasoning inferred a window action; source evidence takes precedence. Window-exchange action keys use Zamień.
- The updated naming policy preserves Dotfiles/dotfiles, Cookie/Material cookie, all seven Material You palette names, scratchpad, submap, fake fullscreen, pseudo-tiling, Notch and Dynamic Island. Expressive font remains a translated font role. Short Island labels use wyspa. Hug is Rozciągnięty; pill is kapsułka, not medication. Blur and frost use rozmycie.
- Provider Plan is Subskrypcja; execution Plan stays Plan. Pomodoro uses Skupienie, while window input focus uses Aktywność okna/active-window actions. Personal Ring/Keyring is Pęk kluczy; package keyring is Baza kluczy pakietów.
- `Play` serves both a gaming heading and playback actions; Odtwórz prioritizes playback. The gaming heading needs a distinct English key. `From`/`To` use Od/Do for gradient endpoints and recipient labels.
- `Locked` is both a lock-screen state and a keybind flag. Zablokowano suits the lock-screen status, but the bindl option needs a separate source key for Przy blokadzie; its description and combined labels specify working while locked. `Launch on startup` currently controls the lock screen, so the label says Blokuj przy uruchomieniu.
- Streaming privacy suppresses the Island presentation of phone events, not phone communication itself. Current source checks for selected Discord/OBS windows/processes rather than confirming an active stream. Source wording/behavior needs separate attention.
- The sharing-password warning mentions accented characters and emoji, while validation only accepts printable ASCII. Keep the supplied warning; source should state the entire restriction. Clearing a network’s firewall zone removes its assignment, not the zone definition.
- Country names come from English iso3166.tab labels; do not assume localized country names or decline injected names. Localized model pricing/capabilities are translated as supplied, not externally verified.
- Literal `Snapshots`/`linux`, command arguments, CLI metavariables, shortcuts, filenames and script examples are preserved. Legacy shortcut instructions and the legacy provider-mode command differ from current controls; translations do not silently repair source behavior.
- An older git stash list instruction only lists stashes; the newer message includes explicit show/pop commands. Both keys remain intact pending a source correction.
- Standalone `think` has no identified current translated caller; the legacy descriptive value is rozumowanie. Every executable `/think` token remains unchanged.
- Long established Polish labels need live fit checks; none were given extra wrapping line breaks or invented context markers. The desktop launcher uses the compact loanword Launcher; the updater launch-helper process is distinct.
- Launch on startup, some pricing/help strings, font-role names and other isolated labels are shared or legacy. Preserve English keys; resolve a genuine per-caller conflict in source rather than adding context markers here.

## Historical reasoning review

Historical review record. Current rules and display names are consolidated in
[TERMINOLOGY.md](../../TERMINOLOGY.md); the English-preservation decisions in this
old report are superseded where the current guide specifies localized labels.

This is the focused follow-up requested after Ukrainian completion. It applies
the owner’s updated terminology, HANDOFF.md, and corrected es_MX example from
`/home/itsjustdroid/Downloads/updated-reasoning`. It supplements the initial
glossary and completion notes; the decisions below supersede older decisions
on these terms. Good existing values outside concrete findings are preserved.

Changes: **1 of 3,221 values**. Source English keys and order are
unchanged. **98 values remain English-identical**; new ones introduced
by this review are explicitly listed below. Other identical entries retain the
individual audit from the original completion notes.

### Review and checks

- Root read the 90 related entries and all changes. Independent fresh-context review read the complete group-3 packet (360 records across four locales), including this locale’s 90 entries. Source context was checked for ambiguous controls.
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
| Dynamic Island | Dynamic Island |
| Island position | Położenie wyspy |
| Island style | Styl wyspy |
| Pills | Kapsułki |
| Hug | Rozciągnięty |
| Notch | Notch |
| Earbang protection | Limit skoków głośności |
| Unmuted | Dźwięk włączony |
| Home | Katalog domowy |
| Swap | Pamięć wymiany |
| Tray | Zasobnik |
| System tray | Zasobnik systemowy |
| Blur | Rozmycie |

All seven named palette presets stay in English: Fruit Salad, Neutral, Tonal Spot, Expressive, Rainbow, Fidelity, Monochrome.
Hyprland scratchpad, submap, fake fullscreen and pseudo-tiling stay literal.
Capitalization such as Material Cookie remains where it is already recognizable
English and correct for the locale; no case-only rewrites were made.

### Exact value changes

| Exact English key | Previous committed value | Reviewed value | Reason |
| --- | --- | --- | --- |
| Thinking Level: %1<br>Click to cycle (minimal → low → medium → high → auto) | Poziom rozumowania: %1<br>Kliknij, aby przełączać (minimal → low → medium → high → auto) | Poziom rozumowania: %1<br>Kliknij, aby przełączać (minimalny → niski → średni → wysoki → auto) | Translate visible click-cycle effort labels; accepted typed command arguments elsewhere remain literal. |

### Newly English-identical values

These are restored names/identifiers, not untranslated prose.

None.

### Source-confirmed exceptions and remaining limits

- Standalone Swap means memory in Resources.qml, ResourcesPanel.qml and ResourcesPopup.qml. Window-action keys use exchange verbs separately. The offline Spanish interpretation did not have source access.
- at in the automatic-suspend row is a battery percentage. Up %1 is uptime. Home in KeybindCaptureItem.qml is an untranslated X11 keysym and does not share the translated personal-folder call.
- Cookie/Material cookie are shape names; Expressive font is a normal descriptive font role and stays translated. No source strings, commands, accepted arguments, runtime names or configuration keys were changed.
- Longer accurate compounds still need eventual visual fit checks. No explanatory label expansions or new manual wrapping line breaks were added.

## Consolidated display-name pass, 2026-10-31

The current policy and approved terms are consolidated in [TERMINOLOGY.md](../../TERMINOLOGY.md). Earlier English-preservation rules and allowlists above are historical. The current pass changes 12 display values, preserving English keys, command syntax, identifiers and all formatting. These are self-reviewed working choices, not native-speaker-verified.

- "Material cookie" → "Ciastko Material"
- "Fruit Salad" → "Sałatka owocowa"
- "Neutral" → "Neutralny"
- "Tonal Spot" → "Akcent tonalny"
- "Expressive" → "Ekspresyjny"
- "Rainbow" → "Tęcza"
- "Fidelity" → "Wierność"
- "Cookie clock settings" → "Ustawienia zegara Ciastko"
- "Monochrome" → "Monochromatyczny"
- "Use old sine wave cookie implementation" → "Użyj starej implementacji Ciastka opartej na sinusoidzie"
- "Cookie" → "Ciastko"
- "Notch" → "Wcięcie"

Current intentionally English-identical count: 88. Names, units, literal formats and natural shared vocabulary remain valid; the lower count is not the purpose of this pass.
