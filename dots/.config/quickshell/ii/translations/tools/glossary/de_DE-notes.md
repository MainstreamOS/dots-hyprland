# German completion notes

Catalog: `de_DE.json`. Source: all 3,221 keys of `en_US.json`, based on mainstream `9b0effd69`.

Completed 2,251 previously English-identical values. Corrected 48 existing translations for concrete defects or glossary inconsistencies; the other 783 existing translations are preserved. All 140 remaining English-identical values are intentional and listed below. Keys and their order are unchanged.

## Validation and review

- Every translation batch passed structural checks before it was written. The full catalog passes `python3 tools/catalog-qa.py de_DE`: JSON and key uniqueness, key set, placeholders and printf order, line breaks, joining whitespace, markup and Markdown, protected names, numbers, URLs, paths, flags and config filenames.
- Eleven regression checks include German compounds, possessives, localized key names and shortcut punctuation. The separate validator commit preserves executable examples and rejects changed command metavariables.
- All 47 printf-format messages were exercised through the actual `sdata/lib/tr.sh` translator with distinct test arguments. English key order matches exactly; an additional audit found no changed slash-command tokens.
- A fresh-context review covered 1,489 unique pairs (46.23%): a 200-key sample across 111 source feature buckets, all 321 actual runtime-placeholder keys, all 140 English-identical values, 1,012 broad warning/error/destructive/access/permission/recovery candidates and 54 otherwise uncovered keys on relevant source surfaces. Overlaps are removed from the total. The QA regex reports 322 placeholder-bearing keys because percent escapes in the Zerochan URL also match; that additional key was reviewed.
- Sampling sorted source-feature buckets lexically, sorted keys within each by SHA-256, then selected round-robin until 200. Source QML and shell code resolved ambiguous controls. The source-location map helped sampling but was not treated as authoritative context.
- Concrete findings were corrected: charge-warning meaning, imperative grammar, count-neutral px/min, firewall connection-zone assignment, streaming display suppression, error-panel dismissal, and glossary consistency. Additional source checks distinguish the AMD GPU Hotspot label and the Anruf history noun.
- Terminology scans cover workspaces, sidebars, app drawer, tray, wallpapers, Night Light, snapshots, capsules, pinning, sleep state and AI modes. Existing technical loanwords such as Prompt, Tool and Reasoning remain where sound; existing Fokus is retained for Pomodoro.
- No native-speaker review or live language preview was performed. These are translations with automated validation and separate review.

## Existing translations corrected

| Exact English key | Reason |
| --- | --- |
| No API key<br>Set it with /key YOUR_API_KEY | Restore the exact command metavariables and syntax; these had been translated. |
| Critically low battery | Name the low battery charge level, rather than describing the physical battery as low. |
| %1 notifications | Use a count-neutral label or minute abbreviation that also works for 1. |
| Automatically suspends the system when battery is low | Use the glossary sleep-state term Bereitschaft consistently for the same system suspend action. |
| Interface | Use the user-interface term Oberfläche, rather than Schnittstelle, which denotes an API or connection interface. |
| Usage: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt><br>Supply <tt>i</tt> when you want images<br>Examples:<br><tt>%1superpaste 4i</tt> for the last 4 images<br><tt>%1superpaste 7</tt> for the last 7 entries | Restore the exact command metavariables and syntax; these had been translated. |
| Up %1 | Translate system uptime rather than upward direction. |
| This is usually safe and needed for your browser and AI sidebar anyway<br>Mostly useful for those who use lock on startup instead of a display manager that does it (GDM, SDDM, etc.) | Use KI consistently with the existing AI label. |
| Conflicts with the shell's system tray implementation | Use the glossary Infobereich term consistently for the tray, distinct from the desktop bar. |
| Paired | Use the same device-pairing term as the Pair and Paired Devices controls. |
| Pills | Name the capsule-shaped UI containers consistently as Kapseln. |
| API key is set<br>Change with /key YOUR_API_KEY | Restore the exact command metavariables and syntax; these had been translated. |
| 12h AM/PM | Restore uppercase AM/PM, which distinguishes this format option from the lowercase one. |
| Please charge!<br>Automatic suspend triggers at %1 | Use the glossary sleep-state term Bereitschaft consistently for the same system suspend action. |
| Low battery | Name the low battery charge level, rather than describing the physical battery as low. |
| Suspend at | Use the glossary sleep-state term Bereitschaft consistently for the same system suspend action. |
| Sleep | Use the glossary sleep-state term Bereitschaft consistently for the same system suspend action. |
| Hug | Describe the edge-hugging style rather than a literal embrace. |
| Automatic suspend | Use the glossary sleep-state term Bereitschaft consistently for the same system suspend action. |
| ☕ Break: %1 minutes | Use a count-neutral label or minute abbreviation that also works for 1. |
| Low warning | Identify the low-charge and full-charge warning thresholds; these are not warning severity or completeness. |
| Current model: %1<br>Set it with %2model MODEL | Restore the exact command metavariables and syntax; these had been translated. |
| Connect to Wi-Fi | Preserve the Wi-Fi technology name required by the terminology guide. |
| Makes the clock always rotate. This is extremely expensive<br>(expect 50% usage on Intel UHD Graphics) and thus impractical. | Restore the clock object, Intel UHD Graphics name and original line break; the old value referred to the dock. |
| Can only be turned on using the 'Dots' or 'Full' dial style for aesthetic reasons | Reference the translated Zifferblatt options Punkte, Voll and Zahlen; also repair the misspelling ncht. |
| Can't be turned on when using 'Numbers' dial style for aesthetic reasons | Reference the translated Zifferblatt options Punkte, Voll and Zahlen; also repair the misspelling ncht. |
| %1   •   %2 tasks | Use a count-neutral label or minute abbreviation that also works for 1. |
| The hentai one \| Great quantity, a lot of NSFW, quality varies wildly | Repair the ungrammatical phrase Der Hentai eine while preserving quantity, NSFW and variable-quality qualifiers. |
| Temperature<br>Change with /temp VALUE | Restore the exact command metavariables and syntax; these had been translated. |
| To set an API key, pass it with the %4 command<br><br>To view the key, pass "get" with the command<br/><br><br>### For %1:<br><br>**Link**: %2<br><br>%3 | Correct the German imperative from übergebe to übergib. |
| 🌿 Long break: %1 minutes | Use a count-neutral label or minute abbreviation that also works for 1. |
| Current API endpoint: %1<br>Set it with %2mode PROVIDER | Restore the exact command metavariables and syntax; these had been translated. |
| When enabled keeps the content of the right sidebar loaded to reduce the delay when opening,<br>at the cost of around 15MB of consistent RAM usage. Delay significance depends on your system's performance.<br>Using a custom kernel like linux-cachyos might help | Repair the missing sentence subject and the incorrect noun gender for Kernel without changing the performance caveat. |
| 🔴 Focus: %1 minutes | Use a count-neutral label or minute abbreviation that also works for 1. |
| Interface Language | Use the user-interface term Oberfläche, rather than Schnittstelle, which denotes an API or connection interface. |
| %1 queries pending | Use a count-neutral label or minute abbreviation that also works for 1. |
| Language not listed or incomplete translations?<br>You can choose to generate translations for it with Gemini.<br>1. Open the left sidebar with Super+A, set model to Gemini (if it isn't already)<br>2. Type /key, hit Enter and follow the instructions<br>3. Type /key YOUR_API_KEY<br>4. Type the locale of your language below and press Generate | Restore the exact command metavariables and syntax; these had been translated. |
| When the previous option is off and this is on,<br>you can still hover the corner's end to open sidebar,<br>and the remaining area can be used for volume/brightness scroll | Repair the missing object in the pointer-hover instruction. |
| Please charge!<br>Automatic suspend triggers at %1% | Use the glossary sleep-state term Bereitschaft consistently for the same system suspend action. |
| Full warning | Identify the low-charge and full-charge warning thresholds; these are not warning severity or completeness. |
| Automatic Suspend | Use the glossary sleep-state term Bereitschaft consistently for the same system suspend action. |
| Signed in. Gemini Flash and Gemini Pro are in the picker now. Adjust thinking level with the reasoning pill or /think. | Identify the reasoning capsule, rather than an unrelated status badge. |
| Signed in. Gemini Flash and Gemini Pro are in the picker now. Adjust thinking level with /think. | Use the existing du register instead of switching to formal Sie. |
| %1 files changed | Use a count-neutral label or minute abbreviation that also works for 1. |
| Commands: /model <name> · /mode [ask\|auto\|plan] | Restore the exact command metavariables and syntax; these had been translated. |
| Search across all files in your home folder | Use the glossary Persönlicher Ordner term consistently for the home folder. |
| Signed in. The plan models are in the picker now: type /model to choose one. | Distinguish subscription models (Abo) from the execution Plan mode. |
| Only local models are allowed right now. To use online models, set AI to Yes in Settings > Interface > Left Sidebar. | Translate the embedded Left Sidebar breadcrumb and use the correct Oberfläche page label. |

## Intentional English-identical values

Each value below was individually audited. None is an untranslated prose message.

| Exact value | Reason |
| --- | --- |
| Start | German word, conventional German software loanword or abbreviation. |
| Info | German word, conventional German software loanword or abbreviation. |
| Audio | German word, conventional German software loanword or abbreviation. |
| Gamma | Unit, format, technical identifier or placeholder-only text. |
| Auto | German word, conventional German software loanword or abbreviation. |
| illogical-impulse | Product, project, style/layout or executable name. |
| Dotfiles | Product, project, style/layout or executable name. |
| Format | German word, conventional German software loanword or abbreviation. |
| Pause | German word, conventional German software loanword or abbreviation. |
| Desktop | German word, conventional German software loanword or abbreviation. |
| Wind | German word, conventional German software loanword or abbreviation. |
| Neutral | German word, conventional German software loanword or abbreviation. |
| 12h AM/PM | German word, conventional German software loanword or abbreviation. |
| Anime | Product, project, style/layout or executable name. |
| Dock | Product, project, style/layout or executable name. |
| Timer | German word, conventional German software loanword or abbreviation. |
| System | German word, conventional German software loanword or abbreviation. |
| Superpaste | Product, project, style/layout or executable name. |
| Weeb | Product, project, style/layout or executable name. |
| GitHub | Product, project, style/layout or executable name. |
| App | German word, conventional German software loanword or abbreviation. |
| Terminal | German word, conventional German software loanword or abbreviation. |
| Cloudflare WARP (1.1.1.1) | Product, project, style/layout or executable name. |
| 24h | Unit, format, technical identifier or placeholder-only text. |
| Emojis | German word, conventional German software loanword or abbreviation. |
| Distro | Product, project, style/layout or executable name. |
| Bluetooth | Product, project, style/layout or executable name. |
| Pomodoro | Product, project, style/layout or executable name. |
| Cloudflare WARP | Product, project, style/layout or executable name. |
| Details | German word, conventional German software loanword or abbreviation. |
| Android | Product, project, style/layout or executable name. |
| Internet | German word, conventional German software loanword or abbreviation. |
| EasyEffects | Product, project, style/layout or executable name. |
| Google Lens | Product, project, style/layout or executable name. |
| Auto, | German word, conventional German software loanword or abbreviation. |
| Normal | German word, conventional German software loanword or abbreviation. |
| %1 nits | Unit, format, technical identifier or placeholder-only text. |
| %1s | Unit, format, technical identifier or placeholder-only text. |
| %1s… | Unit, format, technical identifier or placeholder-only text. |
| %1… | Unit, format, technical identifier or placeholder-only text. |
| 0° | Unit, format, technical identifier or placeholder-only text. |
| 50 % APL  ·  %1 nits | Unit, format, technical identifier or placeholder-only text. |
| Apps | German word, conventional German software loanword or abbreviation. |
| Cookie | Product, project, style/layout or executable name. |
| dd/MM | Unit, format, technical identifier or placeholder-only text. |
| dd.MM | Unit, format, technical identifier or placeholder-only text. |
| Digital | German word, conventional German software loanword or abbreviation. |
| Emoji | German word, conventional German software loanword or abbreviation. |
| LCD HDR 1000 | Unit, format, technical identifier or placeholder-only text. |
| LCD HDR 600 | Unit, format, technical identifier or placeholder-only text. |
| Layout | German word, conventional German software loanword or abbreviation. |
| Layouts | German word, conventional German software loanword or abbreviation. |
| MM/dd | Unit, format, technical identifier or placeholder-only text. |
| OLED / QD-OLED | Unit, format, technical identifier or placeholder-only text. |
| Position | German word, conventional German software loanword or abbreviation. |
| Status | German word, conventional German software loanword or abbreviation. |
| Touchpad | German word, conventional German software loanword or abbreviation. |
| VRAM: | Unit, format, technical identifier or placeholder-only text. |
| Web | German word, conventional German software loanword or abbreviation. |
| Widgets | German word, conventional German software loanword or abbreviation. |
| (optional) | German word, conventional German software loanword or abbreviation. |
| Argument | German word, conventional German software loanword or abbreviation. |
| DaVinci Resolve | Product, project, style/layout or executable name. |
| DaVinci Resolve Studio | Product, project, style/layout or executable name. |
| Desktop + Big Picture | Product, project, style/layout or executable name. |
| Celsius | Unit, format, technical identifier or placeholder-only text. |
| Fahrenheit | Unit, format, technical identifier or placeholder-only text. |
| Horizontal | German word, conventional German software loanword or abbreviation. |
| Master | Product, project, style/layout or executable name. |
| Monocle | Product, project, style/layout or executable name. |
| Name | German word, conventional German software loanword or abbreviation. |
| OBS Studio | Product, project, style/layout or executable name. |
| Passphrase | German word, conventional German software loanword or abbreviation. |
| Scrolling | Product, project, style/layout or executable name. |
| Server | German word, conventional German software loanword or abbreviation. |
| Transparent | German word, conventional German software loanword or abbreviation. |
| end-4 — Dotfiles | Product, project, style/layout or executable name. |
| %1 (%2) | Unit, format, technical identifier or placeholder-only text. |
|  min | Unit, format, technical identifier or placeholder-only text. |
| Radius | German word, conventional German software loanword or abbreviation. |
| Minimal | German word, conventional German software loanword or abbreviation. |
| Discord | Product, project, style/layout or executable name. |
| min | Unit, format, technical identifier or placeholder-only text. |
| GitHub Sponsors | Product, project, style/layout or executable name. |
| Ko-fi | Product, project, style/layout or executable name. |
| Patreon | Product, project, style/layout or executable name. |
| CRT | Unit, format, technical identifier or placeholder-only text. |
| Zoom | German word, conventional German software loanword or abbreviation. |
| Pixel | German word, conventional German software loanword or abbreviation. |
| pctrade — Widgets | Product, project, style/layout or executable name. |
| ok | German word, conventional German software loanword or abbreviation. |
| updatems | Product, project, style/layout or executable name. |
| updatems-system | Product, project, style/layout or executable name. |
| macrecovery | Product, project, style/layout or executable name. |
| AUR (yay/paru): | Product, project, style/layout or executable name. |
| Flatpak: | Product, project, style/layout or executable name. |
| Snap: | Product, project, style/layout or executable name. |
| Dotfiles (updatems): | Product, project, style/layout or executable name. |
| <none> | Technical sentinel, preserved literally. |
| Videos | German word, conventional German software loanword or abbreviation. |
| GIMP | Product, project, style/layout or executable name. |
| Krita | Product, project, style/layout or executable name. |
| Office | German word, conventional German software loanword or abbreviation. |
| LibreOffice | Product, project, style/layout or executable name. |
| OnlyOffice | Product, project, style/layout or executable name. |
| Sunshine | Product, project, style/layout or executable name. |
| Moonlight | Product, project, style/layout or executable name. |
| Blender | Product, project, style/layout or executable name. |
| 15 fps | Unit, format, technical identifier or placeholder-only text. |
| 30 fps | Unit, format, technical identifier or placeholder-only text. |
| Administrator | German word, conventional German software loanword or abbreviation. |
| Standard | German word, conventional German software loanword or abbreviation. |
| Tour | German word, conventional German software loanword or abbreviation. |
| Signal: | German word, conventional German software loanword or abbreviation. |
| Download: | German word, conventional German software loanword or abbreviation. |
| Upload: | German word, conventional German software loanword or abbreviation. |
| WiVRn | Product, project, style/layout or executable name. |
| Antigravity: | Product, project, style/layout or executable name. |
| Code | German word, conventional German software loanword or abbreviation. |
| Downloads | German word, conventional German software loanword or abbreviation. |
| Extra | German word, conventional German software loanword or abbreviation. |
| Ollama | Product, project, style/layout or executable name. |
| Plan | German word, conventional German software loanword or abbreviation. |
| UltraCode | Product, project, style/layout or executable name. |
| GIF | Unit, format, technical identifier or placeholder-only text. |
| Video | German word, conventional German software loanword or abbreviation. |
| Instagram Reel | Product, project, style/layout or executable name. |
| %1 B | Unit, format, technical identifier or placeholder-only text. |
| %1 KB | Unit, format, technical identifier or placeholder-only text. |
| %1 MB | Unit, format, technical identifier or placeholder-only text. |
| %1 GB | Unit, format, technical identifier or placeholder-only text. |
| LocalSend | Product, project, style/layout or executable name. |
| Computer | German word, conventional German software loanword or abbreviation. |
| RAM | Unit, format, technical identifier or placeholder-only text. |
| CPU | Unit, format, technical identifier or placeholder-only text. |
| Ethernet | Unit, format, technical identifier or placeholder-only text. |
| Wi-Fi | Unit, format, technical identifier or placeholder-only text. |
| Dynamic Island | Product, project, style/layout or executable name. |
| GIFs | Unit, format, technical identifier or placeholder-only text. |
| Dwindle | Product, project, style/layout or executable name. |

## Shared-key decisions and source issues

- `Interface` labels both the settings page and an assistant-role fallback. The single German value Oberfläche follows the settings meaning; a separate source key would allow an independent assistant name.
- `Locked` appears in both clock state and keybinding metadata. Keep the existing Gesperrt label; the keybinding description clarifies that the binding works while the screen is locked.
- `Usage` serves both usage information and command help. Existing Verwendung is retained as the shared term. Execution Plan remains Plan; subscription descriptions use Abo.
- Preserve the boot-menu entries `Snapshots` and `linux` as literal UI references. Recovery descriptions use Schnappschuss.
- Older help says Ctrl+P detaches the sidebar, while newer controls use Ctrl+D for detach and Ctrl+P for pin. The translation preserves each supplied shortcut; the source instructions should be reconciled separately.
- The historical API-provider tooltip uses `%2mode PROVIDER`, while the current execution-mode help lists `ask|auto|plan`. Preserve the supplied syntax and flag the source inconsistency.
- One update-advice key contains literal `\u2014` text. Its German value uses natural punctuation; the lookup key is unchanged.
- Model/provider descriptions are translated as supplied and are not claims that their pricing, IDs or capabilities were externally verified.

## Historical reasoning review

Historical review record. Current rules and display names are consolidated in
[TERMINOLOGY.md](../../TERMINOLOGY.md); the English-preservation decisions in this
old report are superseded where the current guide specifies localized labels.

This is the focused follow-up requested after Ukrainian completion. It applies
the owner’s updated terminology, HANDOFF.md, and corrected es_MX example from
`/home/itsjustdroid/Downloads/updated-reasoning`. It supplements the initial
glossary and completion notes; the decisions below supersede older decisions
on these terms. Good existing values outside concrete findings are preserved.

Changes: **31 of 3,221 values**. Source English keys and order are
unchanged. **148 values remain English-identical**; new ones introduced
by this review are explicitly listed below. Other identical entries retain the
individual audit from the original completion notes.

### Review and checks

- Root read the 90 related entries and all changes. Independent fresh-context review read the complete group-1 packet (371 records across four locales), including this locale’s 90 entries. Source context was checked for ambiguous controls.
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
| Island position | Inselposition |
| Island style | Inselstil |
| Pills | Kapseln |
| Hug | Gestreckt |
| Notch | Notch |
| Earbang protection | Schutz vor Lautstärkesprüngen |
| Unmuted | Ton an |
| Home | Persönlicher Ordner |
| Swap | Swap |
| Tray | Infobereich |
| System tray | Infobereich |
| Blur | Unschärfe |

All seven named palette presets stay in English: Fruit Salad, Neutral, Tonal Spot, Expressive, Rainbow, Fidelity, Monochrome.
Hyprland scratchpad, submap, fake fullscreen and pseudo-tiling stay literal.
Capitalization such as Material Cookie remains where it is already recognizable
English and correct for the locale; no case-only rewrites were made.

### Exact value changes

| Exact English key | Previous committed value | Reviewed value | Reason |
| --- | --- | --- | --- |
| Style: Blurred | Stil: Verschwommen | Stil: Unscharf | Use the chosen blur term consistently for blur and frosted surfaces. |
| Blurred style | Verschwommener Stil | Unscharfer Stil | Use the chosen blur term consistently for blur and frosted surfaces. |
| at | um | bei | The actual caller is a battery-percentage threshold (PowerConfig.qml:434), not a clock time or physical location. |
| Fruit Salad | Fruchtsalat | Fruit Salad | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Tonal Spot | Tonaler Akzent | Tonal Spot | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Expressive | Ausdrucksvoll | Expressive | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Hug | Randbündig | Gestreckt | Name the edge-spanning style; the earlier wording meant an embrace or attachment to an edge. |
| Rainbow | Regenbogen | Rainbow | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Fidelity | Wiedergabetreue | Fidelity | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Earbang protection | Ohrschutz | Schutz vor Lautstärkesprüngen | Name sudden volume-jump protection concisely; this is neither visual flashing nor headphone hardware protection. |
| Monochrome | Monochrom | Monochrome | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Unmuted | Nicht stumm | Ton an | Use a natural sound-enabled state instead of an awkward negation. |
| Swap | Tauschen | Swap | All three current resource-panel callers mean disk-backed memory, not a window exchange action. |
| Enter submap | Tasten-Unterbelegung aktivieren | submap aktivieren | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Special (scratchpad) | Spezialbereich (Ablage) | Spezialbereich (scratchpad) | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle fake fullscreen | Scheinvollbild umschalten | fake fullscreen umschalten | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle pseudo-tiling | Pseudo-Kacheln umschalten | pseudo-tiling umschalten | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle scratchpad | Ablage umschalten | scratchpad umschalten | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| How deep the frost goes. Deeper costs more to draw. | Wie stark der Milchglaseffekt ist. Stärker bedeutet mehr Darstellungsaufwand. | Wie stark die Unschärfe ist. Stärker bedeutet mehr Darstellungsaufwand. | Use the chosen blur term consistently for blur and frosted surfaces. |
| no frost | kein Milchglas | keine Unschärfe | Use the chosen blur term consistently for blur and frosted surfaces. |
| No frost behind it | Kein Milchglas dahinter | Keine Unschärfe dahinter | Use the chosen blur term consistently for blur and frosted surfaces. |
| Notch | Kerbe | Notch | Preserve Notch as the named drawn style, not a physical hardware-cutout noun. |
| Toggle the scratchpad workspace | Ablage-Arbeitsbereich umschalten | scratchpad-Arbeitsbereich umschalten | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Exit the keybind submap | Tasten-Unterbelegung verlassen | Tasten-submap verlassen | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Signed in. The plan models are in the picker now: type /model to choose between Gemini 3.8 Flash (High, Medium, Low) and Gemini 3.1 Pro (High, Low). | Angemeldet. Die Abo-Modelle sind jetzt in der Auswahl: Gib /model ein, um zwischen Gemini 3.8 Flash (High, Medium, Low) und Gemini 3.1 Pro (High, Low) zu wählen. | Angemeldet. Die Abo-Modelle sind jetzt in der Auswahl: Gib /model ein, um zwischen Gemini 3.8 Flash (Hoch, Mittel, Niedrig) und Gemini 3.1 Pro (Hoch, Niedrig) zu wählen. | The parenthesized names are visible effort levels, not literal command arguments. |
| Thinking Level: %1<br>Click to cycle (minimal → low → medium → high → auto) | Denkstufe: %1<br>Klicken zum Wechseln (minimal → low → medium → high → auto) | Denkstufe: %1<br>Klicken zum Wechseln (Minimal → Niedrig → Mittel → Hoch → Auto) | Translate visible click-cycle effort labels; accepted typed command arguments elsewhere remain literal. |
| Press Super to search apps in the island. | Drücke Super, um Apps in der Island zu suchen. | Drücke Super, um Apps in der Insel zu suchen. | Use the locale’s concise Island term in short compounds; the full feature keeps its name. |
| Island panels | Island-Bereiche | Inselbereiche | Use the locale’s concise Island term in short compounds; the full feature keeps its name. |
| Island position | Island-Position | Inselposition | Use the locale’s concise Island term in short compounds; the full feature keeps its name. |
| Island style | Island-Stil | Inselstil | Use the locale’s concise Island term in short compounds; the full feature keeps its name. |
| Frosted widget backgrounds | Widget-Hintergründe aus Milchglas | Unscharfe Widget-Hintergründe | Use the chosen blur term consistently for blur and frosted surfaces. |

### Newly English-identical values

These are restored names/identifiers, not untranslated prose.

- "Fruit Salad"
- "Tonal Spot"
- "Expressive"
- "Rainbow"
- "Fidelity"
- "Monochrome"
- "Swap"
- "Notch"

### Source-confirmed exceptions and remaining limits

- Standalone Swap means memory in Resources.qml, ResourcesPanel.qml and ResourcesPopup.qml. Window-action keys use exchange verbs separately. The offline Spanish interpretation did not have source access.
- at in the automatic-suspend row is a battery percentage. Up %1 is uptime. Home in KeybindCaptureItem.qml is an untranslated X11 keysym and does not share the translated personal-folder call.
- Cookie/Material cookie are shape names; Expressive font is a normal descriptive font role and stays translated. No source strings, commands, accepted arguments, runtime names or configuration keys were changed.
- Longer accurate compounds still need eventual visual fit checks. No explanatory label expansions or new manual wrapping line breaks were added.

## Consolidated display-name pass, 2026-10-31

The current policy and approved terms are consolidated in [TERMINOLOGY.md](../../TERMINOLOGY.md). Earlier English-preservation rules and allowlists above are historical. The current pass changes 10 display values, preserving English keys, command syntax, identifiers and all formatting. These are self-reviewed working choices, not native-speaker-verified.

- "Material cookie" → "Material-Keks"
- "Fruit Salad" → "Obstsalat"
- "Tonal Spot" → "Tonaler Akzent"
- "Expressive" → "Ausdrucksstark"
- "Rainbow" → "Regenbogen"
- "Fidelity" → "Farbtreue"
- "Cookie clock settings" → "Keks-Uhr-Einstellungen"
- "Monochrome" → "Monochrom"
- "Use old sine wave cookie implementation" → "Alte Sinuswellen-Keks-Implementierung verwenden"
- "Cookie" → "Keks"

Current intentionally English-identical count: 141. Names, units, literal formats and natural shared vocabulary remain valid; the lower count is not the purpose of this pass.
