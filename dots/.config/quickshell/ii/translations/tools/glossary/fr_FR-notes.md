# French completion notes

Catalog: `fr_FR.json`. Source: all 3,221 keys of `en_US.json`, based on mainstream `f1ea644d5`.

Completed 2,249 previously English-identical values. Corrected 41 existing translations for concrete defects or glossary inconsistencies; the other 776 existing translations are preserved. All 155 remaining English-identical values are intentional and listed below. Keys and their order are unchanged.

## Validation and review

- Every batch passed structural validation before writing. The full catalog passes `python3 tools/catalog-qa.py fr_FR`: unique JSON keys and exact source key set, placeholders and printf order, real line breaks, joining whitespace, markup and Markdown, protected names, numbers, URLs, paths, flags and config filenames.
- All 47 printf-format messages were exercised through the actual `sdata/lib/tr.sh` translator with distinct arguments. Key order matches English exactly; a separate audit found no changed slash-command tokens. Eleven validator regression tests pass.
- A separate fresh-context review covered 1,857 unique English/French pairs: a deterministic 200-key source-feature sample, all 321 actual runtime-placeholder keys, 632 broad warning/destructive/access/security/recovery candidates, all 155 English-identical values, and further source, long-description, protection, network, battery, credential, negative-state and glossary sweeps. The first four overlapping sets contain 1,173 unique keys; further sweeps add 684. The Zerochan URL key was also checked; its percent-encoded characters are not runtime placeholders.
- Sampling buckets keys by their lexicographically first source path (line suffix removed, unmapped keys in their own bucket), sorts buckets lexically and keys within each by SHA256, then selects round-robin until 200. The sample covers 200 of 235 buckets; SHA256 of the selected English keys joined with newline: `5987c9c5ce2c193fdc6bf6dda72d4a3b08c1868256f3befdc828eff127497510`.
- Review corrections repair a notification tooltip, fuzzy-search description, forced-shutdown warning and outgoing-call direction. Source context also confirms battery-charge thresholds, AMD GPU hotspot temperature, connection-zone assignment, streaming notification suppression, sleep-state wording and count-neutral units.
- Glossary scans cover workspaces, sidebars, app drawer, capsules, tray, themes, Night Light, snapshots, pinning, subscription and execution modes. Existing conversation Save remains Sauvegarder to match the actual button; new general save controls use Enregistrer.
- No native-speaker review or live language preview was performed. These are translations with automated validation and a separate review.

## Existing translations corrected

| Exact English key | Reason |
| --- | --- |
| No API key<br>Set it with /key YOUR_API_KEY | Restore literal command metavariables and executable syntax; these had been translated. |
| Automatically suspends the system when battery is low | Use the established mise en veille term consistently for system suspend. |
| Usage: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt><br>Supply <tt>i</tt> when you want images<br>Examples:<br><tt>%1superpaste 4i</tt> for the last 4 images<br><tt>%1superpaste 7</tt> for the last 7 entries | Restore literal command metavariables and executable syntax; these had been translated. |
| This is usually safe and needed for your browser and AI sidebar anyway<br>Mostly useful for those who use lock on startup instead of a display manager that does it (GDM, SDDM, etc.) | Use panneau latéral consistently and translate the remaining English navigation breadcrumb. |
| Paired | Use the same device-association term as the Pair controls. |
| Pills | Name capsule-shaped UI containers Pastilles, rather than medication. |
| API key is set<br>Change with /key YOUR_API_KEY | Restore literal command metavariables and executable syntax; these had been translated. |
| Usage: %1tool TOOL_NAME | Restore literal command metavariables and executable syntax; these had been translated. |
| Please charge!<br>Automatic suspend triggers at %1 | Use the established mise en veille term consistently for system suspend. |
| Suspend at | Use the established mise en veille term consistently for system suspend. |
| Hug | Describe the edge-hugging style, rather than an embrace. |
| Automatic suspend | Use the established mise en veille term consistently for system suspend. |
| Tip: right-clicking a group<br>also expands it | Replace the non-French verb expand with développer in the notification tooltip. |
| ☕ Break: %1 minutes | Use a count-neutral label or min abbreviation that also works when the value is 1. |
| Low warning | Identify the low-charge warning threshold, rather than weak warning severity. |
| Current tool: %1<br>Set it with %2tool TOOL | Restore literal command metavariables and executable syntax; these had been translated. |
| Current model: %1<br>Set it with %2model MODEL | Restore literal command metavariables and executable syntax; these had been translated. |
| %1   •   %2 tasks | Use a count-neutral label or min abbreviation that also works when the value is 1. |
| Temperature<br>Change with /temp VALUE | Restore literal command metavariables and executable syntax; these had been translated. |
| Use Levenshtein distance-based algorithm instead of fuzzy | Identify fuzzy search matching, rather than graphical blur. |
| 🌿 Long break: %1 minutes | Use a count-neutral label or min abbreviation that also works when the value is 1. |
| Current API endpoint: %1<br>Set it with %2mode PROVIDER | Restore literal command metavariables and executable syntax; these had been translated. |
| Remember that on most devices one can always hold the power button to force shutdown<br>This only makes it a tiny bit harder for accidents to happen | Repair the ungrammatical shutdown-warning sentence while preserving its limited accident-prevention scope. |
| When enabled keeps the content of the right sidebar loaded to reduce the delay when opening,<br>at the cost of around 15MB of consistent RAM usage. Delay significance depends on your system's performance.<br>Using a custom kernel like linux-cachyos might help | Repair the opening grammar and preserve the literal MB unit required by the source. |
| 🔴 Focus: %1 minutes | Use the existing Pomodoro term Concentration and the count-neutral min abbreviation. |
| %1 characters | Use a count-neutral label or min abbreviation that also works when the value is 1. |
| Usage: %1save CHAT_NAME | Restore literal command metavariables and executable syntax; these had been translated. |
| Usage: %1load CHAT_NAME | Restore literal command metavariables and executable syntax; these had been translated. |
| %1 queries pending | Use a count-neutral label or min abbreviation that also works when the value is 1. |
| Language not listed or incomplete translations?<br>You can choose to generate translations for it with Gemini.<br>1. Open the left sidebar with Super+A, set model to Gemini (if it isn't already)<br>2. Type /key, hit Enter and follow the instructions<br>3. Type /key YOUR_API_KEY<br>4. Type the locale of your language below and press Generate | Restore literal command metavariables and executable syntax; these had been translated. |
| Why this is cool:<br>For non-0 values, it won't trigger when you reach the<br>screen corner along the horizontal edge, but it will when<br>you do along the vertical edge | Preserve the explicit numeric 0 in the hot-corner condition. |
| Please charge!<br>Automatic suspend triggers at %1% | Use the established mise en veille term consistently for system suspend. |
| Full warning | Identify a full-battery warning, rather than a complete warning. |
| Padding | Use the UI spacing term Marge intérieure, rather than upholstery. |
| Signed in. Gemini Flash and Gemini Pro are in the picker now. Adjust thinking level with the reasoning pill or /think. | Restore the reasoning qualifier on the capsule control. |
| %1 files changed | Use a count-neutral label or min abbreviation that also works when the value is 1. |
| All files in ~ (%1 matches) | Use a count-neutral label or min abbreviation that also works when the value is 1. |
| Commands: /model <name> · /mode [ask\|auto\|plan] | Restore literal command metavariables and executable syntax; these had been translated. |
| The clipboard text was cut to 50,000 characters. | Use the French narrow nonbreaking thousands separator while preserving the exact number. |
| Signed in. The plan models are in the picker now: type /model to choose one. | Distinguish subscription models from execution Plan mode. |
| Only local models are allowed right now. To use online models, set AI to Yes in Settings > Interface > Left Sidebar. | Use panneau latéral consistently and translate the remaining English navigation breadcrumb. |

## Intentionally English-identical values

Each remaining value was individually checked; none is untranslated English prose.

| Exact English key | Reason |
| --- | --- |
| Info | French word, established French loanword or abbreviation; the same spelling is correct. |
| Interface | French word, established French loanword or abbreviation; the same spelling is correct. |
| Audio | French word, established French loanword or abbreviation; the same spelling is correct. |
| Volume | French word, established French loanword or abbreviation; the same spelling is correct. |
| Gamma | French word, established French loanword or abbreviation; the same spelling is correct. |
| 12h am/pm | Unit, format, technical identifier or unchanged French placeholder label. |
| OK | French word, established French loanword or abbreviation; the same spelling is correct. |
| Auto | French word, established French loanword or abbreviation; the same spelling is correct. |
| illogical-impulse | Product, project, executable or named style/layout. |
| Dotfiles | French word, established French loanword or abbreviation; the same spelling is correct. |
| Configuration | French word, established French loanword or abbreviation; the same spelling is correct. |
| Format | French word, established French loanword or abbreviation; the same spelling is correct. |
| Pause | French word, established French loanword or abbreviation; the same spelling is correct. |
| Documentation | French word, established French loanword or abbreviation; the same spelling is correct. |
| 12h AM/PM | Unit, format, technical identifier or unchanged French placeholder label. |
| Anime | French word, established French loanword or abbreviation; the same spelling is correct. |
| Dock | Product, project, executable or named style/layout. |
| Session | French word, established French loanword or abbreviation; the same spelling is correct. |
| Services | French word, established French loanword or abbreviation; the same spelling is correct. |
| Notifications | French word, established French loanword or abbreviation; the same spelling is correct. |
| Superpaste | Product, project, executable or named style/layout. |
| Weeb | French word, established French loanword or abbreviation; the same spelling is correct. |
| GitHub | Product, project, executable or named style/layout. |
| Action | French word, established French loanword or abbreviation; the same spelling is correct. |
| Terminal | French word, established French loanword or abbreviation; the same spelling is correct. |
| Cloudflare WARP (1.1.1.1) | Product, project, executable or named style/layout. |
| 24h | Unit, format, technical identifier or unchanged French placeholder label. |
| Emojis | French word, established French loanword or abbreviation; the same spelling is correct. |
| Page %1 | Unit, format, technical identifier or unchanged French placeholder label. |
| Distro | French word, established French loanword or abbreviation; the same spelling is correct. |
| Bluetooth | French word, established French loanword or abbreviation; the same spelling is correct. |
| Pomodoro | French word, established French loanword or abbreviation; the same spelling is correct. |
| Vertical | French word, established French loanword or abbreviation; the same spelling is correct. |
| Cloudflare WARP | Product, project, executable or named style/layout. |
| Monochrome | French word, established French loanword or abbreviation; the same spelling is correct. |
| Discussions | French word, established French loanword or abbreviation; the same spelling is correct. |
| Microphone | French word, established French loanword or abbreviation; the same spelling is correct. |
| Android | Product, project, executable or named style/layout. |
| Internet | French word, established French loanword or abbreviation; the same spelling is correct. |
| EasyEffects | Product, project, executable or named style/layout. |
| Google Lens | Product, project, executable or named style/layout. |
| Applications | French word, established French loanword or abbreviation; the same spelling is correct. |
| Auto, | French word, established French loanword or abbreviation; the same spelling is correct. |
| Normal | French word, established French loanword or abbreviation; the same spelling is correct. |
| %1 nits | Unit, format, technical identifier or unchanged French placeholder label. |
| %1s | Unit, format, technical identifier or unchanged French placeholder label. |
| %1s… | Unit, format, technical identifier or unchanged French placeholder label. |
| %1… | Unit, format, technical identifier or unchanged French placeholder label. |
| 0° | Unit, format, technical identifier or unchanged French placeholder label. |
| 1 minute | French word, established French loanword or abbreviation; the same spelling is correct. |
| 10 minutes | French word, established French loanword or abbreviation; the same spelling is correct. |
| 15 minutes | French word, established French loanword or abbreviation; the same spelling is correct. |
| 2 minutes | French word, established French loanword or abbreviation; the same spelling is correct. |
| 30 minutes | French word, established French loanword or abbreviation; the same spelling is correct. |
| 5 minutes | French word, established French loanword or abbreviation; the same spelling is correct. |
| 50 % APL  ·  %1 nits | Unit, format, technical identifier or unchanged French placeholder label. |
| Actions | French word, established French loanword or abbreviation; the same spelling is correct. |
| Animations | French word, established French loanword or abbreviation; the same spelling is correct. |
| Cookie | Product, project, executable or named style/layout. |
| dd/MM | Unit, format, technical identifier or unchanged French placeholder label. |
| dd.MM | Unit, format, technical identifier or unchanged French placeholder label. |
| Emoji | French word, established French loanword or abbreviation; the same spelling is correct. |
| LCD HDR 1000 | Product, project, executable or named style/layout. |
| LCD HDR 600 | Product, project, executable or named style/layout. |
| Mode | French word, established French loanword or abbreviation; the same spelling is correct. |
| MM/dd | French word, established French loanword or abbreviation; the same spelling is correct. |
| Notes | French word, established French loanword or abbreviation; the same spelling is correct. |
| OLED / QD-OLED | Product, project, executable or named style/layout. |
| Orientation | French word, established French loanword or abbreviation; the same spelling is correct. |
| Portrait | French word, established French loanword or abbreviation; the same spelling is correct. |
| Position | French word, established French loanword or abbreviation; the same spelling is correct. |
| Rectangle | French word, established French loanword or abbreviation; the same spelling is correct. |
| VRAM: | Unit, format, technical identifier or unchanged French placeholder label. |
| Web | French word, established French loanword or abbreviation; the same spelling is correct. |
| Widgets | French word, established French loanword or abbreviation; the same spelling is correct. |
| Argument | French word, established French loanword or abbreviation; the same spelling is correct. |
| DaVinci Resolve | Product, project, executable or named style/layout. |
| DaVinci Resolve Studio | Product, project, executable or named style/layout. |
| Direction | French word, established French loanword or abbreviation; the same spelling is correct. |
| Celsius | French word, established French loanword or abbreviation; the same spelling is correct. |
| Fahrenheit | French word, established French loanword or abbreviation; the same spelling is correct. |
| Horizontal | French word, established French loanword or abbreviation; the same spelling is correct. |
| Local | French word, established French loanword or abbreviation; the same spelling is correct. |
| Master | Product, project, executable or named style/layout. |
| Monocle | Product, project, executable or named style/layout. |
| OBS Studio | Product, project, executable or named style/layout. |
| Transparent | French word, established French loanword or abbreviation; the same spelling is correct. |
| Type | French word, established French loanword or abbreviation; the same spelling is correct. |
| end-4 — Dotfiles | Product, project, executable or named style/layout. |
| %1 (%2) | Unit, format, technical identifier or unchanged French placeholder label. |
| Simple | French word, established French loanword or abbreviation; the same spelling is correct. |
|  min | Unit, format, technical identifier or unchanged French placeholder label. |
| images | French word, established French loanword or abbreviation; the same spelling is correct. |
| Passes | French word, established French loanword or abbreviation; the same spelling is correct. |
| Angle | French word, established French loanword or abbreviation; the same spelling is correct. |
| Saturation | French word, established French loanword or abbreviation; the same spelling is correct. |
| Minimal | French word, established French loanword or abbreviation; the same spelling is correct. |
| Placement | French word, established French loanword or abbreviation; the same spelling is correct. |
| Discord | Product, project, executable or named style/layout. |
| Style | French word, established French loanword or abbreviation; the same spelling is correct. |
| min | Unit, format, technical identifier or unchanged French placeholder label. |
| GitHub Sponsors | Product, project, executable or named style/layout. |
| Ko-fi | Product, project, executable or named style/layout. |
| Patreon | Product, project, executable or named style/layout. |
| Session (5h) | French word, established French loanword or abbreviation; the same spelling is correct. |
| CRT | Unit, format, technical identifier or unchanged French placeholder label. |
| Zoom | French word, established French loanword or abbreviation; the same spelling is correct. |
| Pixel | French word, established French loanword or abbreviation; the same spelling is correct. |
| pctrade — Widgets | Product, project, executable or named style/layout. |
| ok | French word, established French loanword or abbreviation; the same spelling is correct. |
| updatems | Product, project, executable or named style/layout. |
| updatems-system | Product, project, executable or named style/layout. |
| macrecovery | Product, project, executable or named style/layout. |
| <none> | Unit, format, technical identifier or unchanged French placeholder label. |
| Photos | French word, established French loanword or abbreviation; the same spelling is correct. |
| GIMP | Product, project, executable or named style/layout. |
| Krita | Product, project, executable or named style/layout. |
| LibreOffice | Product, project, executable or named style/layout. |
| OnlyOffice | Product, project, executable or named style/layout. |
| Sunshine | Product, project, executable or named style/layout. |
| Moonlight | Product, project, executable or named style/layout. |
| Blender | Product, project, executable or named style/layout. |
| 15 fps | Unit, format, technical identifier or unchanged French placeholder label. |
| 30 fps | Unit, format, technical identifier or unchanged French placeholder label. |
| Standard | French word, established French loanword or abbreviation; the same spelling is correct. |
| WiVRn | Product, project, executable or named style/layout. |
| Antigravity: | Product, project, executable or named style/layout. |
| Code | French word, established French loanword or abbreviation; the same spelling is correct. |
| Images | French word, established French loanword or abbreviation; the same spelling is correct. |
| Ollama | Product, project, executable or named style/layout. |
| Plan | French word, established French loanword or abbreviation; the same spelling is correct. |
| UltraCode | Product, project, executable or named style/layout. |
| GIF | Unit, format, technical identifier or unchanged French placeholder label. |
| Photo | French word, established French loanword or abbreviation; the same spelling is correct. |
| Instagram Reel | Product, project, executable or named style/layout. |
| Message | French word, established French loanword or abbreviation; the same spelling is correct. |
| message | French word, established French loanword or abbreviation; the same spelling is correct. |
| %1 B | Unit, format, technical identifier or unchanged French placeholder label. |
| %1 KB | Unit, format, technical identifier or unchanged French placeholder label. |
| %1 MB | Unit, format, technical identifier or unchanged French placeholder label. |
| %1 GB | Unit, format, technical identifier or unchanged French placeholder label. |
| Date | French word, established French loanword or abbreviation; the same spelling is correct. |
| 1 contact | French word, established French loanword or abbreviation; the same spelling is correct. |
| Contacts | French word, established French loanword or abbreviation; the same spelling is correct. |
| Messages | French word, established French loanword or abbreviation; the same spelling is correct. |
| LocalSend | Product, project, executable or named style/layout. |
| Message… | French word, established French loanword or abbreviation; the same spelling is correct. |
| contact | French word, established French loanword or abbreviation; the same spelling is correct. |
| RAM | Unit, format, technical identifier or unchanged French placeholder label. |
| CPU | Unit, format, technical identifier or unchanged French placeholder label. |
| Ethernet | Unit, format, technical identifier or unchanged French placeholder label. |
| Wi-Fi | Unit, format, technical identifier or unchanged French placeholder label. |
| Dynamic Island | Product, project, executable or named style/layout. |
| GIFs | Unit, format, technical identifier or unchanged French placeholder label. |
| Dwindle | Product, project, executable or named style/layout. |

## Shared-key decisions and source issues

- `Play` is the gaming category in `welcome-tutorial.qml:876`, but also the playback action in `PhoneAudioAttachment.qml:48`, `MessageAudioClip.qml:120` and video controls. French requires Jouer for gaming and Lire for playback. Keep the pre-existing Jouer value; separate source keys are needed to translate both faithfully. The MediaWidget artist fallback Play is not a translation call.
- `Interface` labels settings and an assistant-role fallback. The shared French word Interface is retained. Execution Plan is Plan; subscription descriptions use abonnement.
- Conversation Save is Sauvegarder in the existing button and its instruction, as confirmed in SessionSelectionSheet and AiChat. Preserve that sound established wording instead of making the instruction disagree with its button.
- Preserve boot-menu entries `Snapshots` and `linux` as literal UI references; recovery descriptions use instantané.
- Older help says Ctrl+P detaches the sidebar, while newer controls use Ctrl+D to detach and Ctrl+P to pin. Supplied shortcuts remain unchanged; reconcile the source separately.
- The historical API-provider tooltip uses `%2mode PROVIDER`, while current execution-mode help lists `ask|auto|plan`. Preserve supplied command syntax and flag the inconsistency.
- One update-advice lookup key contains literal `\u2014` text. Its French value uses natural punctuation; the key is unchanged.
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

Changes: **38 of 3,221 values**. Source English keys and order are
unchanged. **164 values remain English-identical**; new ones introduced
by this review are explicitly listed below. Other identical entries retain the
individual audit from the original completion notes.

### Review and checks

- Root read the 90 related entries and all changes. Independent fresh-context review read the complete group-1 packet (371 records across four locales), including this locale’s 90 entries. Source context was checked for ambiguous controls.
- The separate 200-key feature sample and all required placeholder/risk reviews from the original locale completion are retained; this follow-up is a focused re-review, not a claim of another full-catalog linguistic review.
- Final structural checks pass for all 3,221 keys: JSON, key order, placeholders, line breaks/joining whitespace, markup/Markdown/code, names, URLs, paths and flags.
- All 47 printf messages pass through the actual sdata/lib/tr.sh formatter with distinct arguments. Expanded name/identifier and slash-command audits pass.
- The reviewer found a preexisting missing-subject defect in the dry-run message. The passive hypothetical correction was applied and independently reread; no further concrete issue remained.
- No native-speaker verification or live language preview was performed. Automated checks and independent review do not replace eventual local-user/UI-fit feedback.

### Updated terminology decisions

| English | Final label |
| --- | --- |
| Material cookie | Material cookie |
| Cookie | Cookie |
| Dotfiles | Dotfiles |
| Superpaste | Superpaste |
| Dynamic Island | Dynamic Island |
| Island position | Position de l'île |
| Island style | Style de l'île |
| Pills | Capsules |
| Hug | Étendu |
| Notch | Notch |
| Earbang protection | Anti-pics de volume |
| Unmuted | Son activé |
| Home | Dossier perso |
| Swap | Swap |
| Tray | Barre système |
| System tray | Barre système |
| Blur | Flou |

All seven named palette presets stay in English: Fruit Salad, Neutral, Tonal Spot, Expressive, Rainbow, Fidelity, Monochrome.
Hyprland scratchpad, submap, fake fullscreen and pseudo-tiling stay literal.
Capitalization such as Material Cookie remains where it is already recognizable
English and correct for the locale; no case-only rewrites were made.

### Exact value changes

| Exact English key | Previous committed value | Reviewed value | Reason |
| --- | --- | --- | --- |
| Material cookie | Cookie Material | Material cookie | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Fruit Salad | Salade de fruits | Fruit Salad | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Pills | Pastilles | Capsules | Use the capsule-shaped UI-container term consistently, without medication wording. |
| Neutral | Neutre | Neutral | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Tonal Spot | Accent tonal | Tonal Spot | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Expressive | Expressif | Expressive | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Hug | Au bord | Étendu | Name the edge-spanning style; the earlier wording meant an embrace or attachment to an edge. |
| Rainbow | Arc-en-ciel | Rainbow | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Fidelity | Fidélité | Fidelity | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Earbang protection | Protection contre les brusques hausses de volume | Anti-pics de volume | Name sudden volume-jump protection concisely; this is neither visual flashing nor headphone hardware protection. |
| Unmuted | Non silencieux | Son activé | Use a natural sound-enabled state instead of an awkward negation. |
| Swap | Échanger | Swap | All three current resource-panel callers mean disk-backed memory, not a window exchange action. |
| Enter submap | Activer le sous-ensemble de raccourcis | Activer submap | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Grab a file and hover the workspace pill in the bar — it lights up and the dots fan out into arrows showing the scroll direction. Slide right to advance workspaces, left to go back, and drop the file into any app on the new workspace without ever opening the overview. | Prenez un fichier et survolez la pastille des espaces de travail dans la barre — elle s'illumine et ses points deviennent des flèches indiquant le sens du défilement. Glissez vers la droite pour avancer, vers la gauche pour revenir, puis déposez le fichier dans une application du nouvel espace sans ouvrir l'aperçu. | Prenez un fichier et survolez la capsule des espaces de travail dans la barre — elle s'illumine et ses points deviennent des flèches indiquant le sens du défilement. Glissez vers la droite pour avancer, vers la gauche pour revenir, puis déposez le fichier dans une application du nouvel espace sans ouvrir l'aperçu. | Use the capsule-shaped UI-container term consistently, without medication wording. |
| Special (scratchpad) | Spécial (réserve) | Spécial (scratchpad) | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle fake fullscreen | Basculer le faux plein écran | Basculer fake fullscreen | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle pseudo-tiling | Basculer la pseudo-mosaïque | Basculer pseudo-tiling | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle scratchpad | Basculer la réserve | Basculer scratchpad | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Drag widgets to reorder them or move them between the left, center, and right sections. Drop one against another to group them into a pill. Tap a widget to hide it. | Faites glisser les widgets pour les réorganiser ou les déplacer entre les sections gauche, centrale et droite. Déposez-en un contre un autre pour les regrouper en pastille. Appuyez sur un widget pour le masquer. | Faites glisser les widgets pour les réorganiser ou les déplacer entre les sections gauche, centrale et droite. Déposez-en un contre un autre pour les regrouper en capsule. Appuyez sur un widget pour le masquer. | Use the capsule-shaped UI-container term consistently, without medication wording. |
| Drag widgets to reorder them or move them between the top, middle, and bottom sections. Drop one against another to group them into a pill. Tap a widget to hide it. | Faites glisser les widgets pour les réorganiser ou les déplacer entre les sections haute, centrale et basse. Déposez-en un contre un autre pour les regrouper en pastille. Appuyez sur un widget pour le masquer. | Faites glisser les widgets pour les réorganiser ou les déplacer entre les sections haute, centrale et basse. Déposez-en un contre un autre pour les regrouper en capsule. Appuyez sur un widget pour le masquer. | Use the capsule-shaped UI-container term consistently, without medication wording. |
| Window title (pill) | Titre de la fenêtre (pastille) | Titre de la fenêtre (capsule) | Use the capsule-shaped UI-container term consistently, without medication wording. |
| How deep the frost goes. Deeper costs more to draw. | Profondeur du dépoli. Un effet plus profond demande plus de travail graphique. | Profondeur du flou. Un effet plus profond demande plus de travail graphique. | Use the chosen blur term consistently for blur and frosted surfaces. |
| no frost | sans dépoli | sans flou | Use the chosen blur term consistently for blur and frosted surfaces. |
| No frost behind it | Pas de dépoli derrière | Pas de flou derrière | Use the chosen blur term consistently for blur and frosted surfaces. |
| Widget pills | Pastilles de widgets | Capsules de widgets | Use the capsule-shaped UI-container term consistently, without medication wording. |
| Notch | Encoche | Notch | Preserve Notch as the named drawn style, not a physical hardware-cutout noun. |
| Toggle the scratchpad workspace | Basculer l'espace de travail de réserve | Basculer l'espace de travail scratchpad | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Exit the keybind submap | Quitter le sous-ensemble de raccourcis | Quitter le submap de raccourcis | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| [DRY-RUN] The dotfiles clone at %s is damaged; would set it aside as %s and clone again. | [DRY-RUN] Le clone des dotfiles dans %s est endommagé ; le déplacerait vers %s et clonerait à nouveau. | [DRY-RUN] Le clone des dotfiles dans %s est endommagé ; il serait déplacé vers %s et cloné à nouveau. | Repair the missing grammatical subject with a passive hypothetical construction; preserve dry-run meaning and printf referent order. |
| Workspace title (pill) | Titre de l'espace de travail (pastille) | Titre de l'espace de travail (capsule) | Use the capsule-shaped UI-container term consistently, without medication wording. |
| Signed in. The plan models are in the picker now: type /model to choose between Gemini 3.8 Flash (High, Medium, Low) and Gemini 3.1 Pro (High, Low). | Connecté. Les modèles du forfait sont désormais disponibles : tapez /model pour choisir entre Gemini 3.8 Flash (High, Medium, Low) et Gemini 3.1 Pro (High, Low). | Connecté. Les modèles du forfait sont désormais disponibles : tapez /model pour choisir entre Gemini 3.8 Flash (Élevé, Moyen, Faible) et Gemini 3.1 Pro (Élevé, Faible). | The parenthesized names are visible effort levels, not literal command arguments. |
| Signed in. Gemini Flash and Gemini Pro are in the picker now. Adjust thinking level with the reasoning pill or /think. | Connecté. Gemini Flash et Gemini Pro sont maintenant disponibles. Ajustez le niveau de réflexion via la pastille de raisonnement ou avec /think. | Connecté. Gemini Flash et Gemini Pro sont maintenant disponibles. Ajustez le niveau de réflexion via la capsule de raisonnement ou avec /think. | Use the capsule-shaped UI-container term consistently, without medication wording. |
| Thinking Level: %1<br>Click to cycle (minimal → low → medium → high → auto) | Niveau de réflexion : %1<br>Cliquez pour changer (minimal → low → medium → high → auto) | Niveau de réflexion : %1<br>Cliquez pour changer (minimal → faible → moyen → élevé → auto) | Translate visible click-cycle effort labels; accepted typed command arguments elsewhere remain literal. |
| Press Super to search apps in the island. | Appuyez sur Super pour rechercher des applications dans l'Island. | Appuyez sur Super pour rechercher des applications dans l'île. | Use the locale’s concise Island term in short compounds; the full feature keeps its name. |
| Island panels | Panneaux de l'Island | Panneaux de l'île | Use the locale’s concise Island term in short compounds; the full feature keeps its name. |
| Island position | Position de l'Island | Position de l'île | Use the locale’s concise Island term in short compounds; the full feature keeps its name. |
| Island style | Style de l'Island | Style de l'île | Use the locale’s concise Island term in short compounds; the full feature keeps its name. |
| Frosted widget backgrounds | Arrière-plans de widgets dépolis | Arrière-plans de widgets floutés | Use the chosen blur term consistently for blur and frosted surfaces. |

### Newly English-identical values

These are restored names/identifiers, not untranslated prose.

- "Material cookie"
- "Fruit Salad"
- "Neutral"
- "Tonal Spot"
- "Expressive"
- "Rainbow"
- "Fidelity"
- "Swap"
- "Notch"

### Source-confirmed exceptions and remaining limits

- Standalone Swap means memory in Resources.qml, ResourcesPanel.qml and ResourcesPopup.qml. Window-action keys use exchange verbs separately. The offline Spanish interpretation did not have source access.
- at in the automatic-suspend row is a battery percentage. Up %1 is uptime. Home in KeybindCaptureItem.qml is an untranslated X11 keysym and does not share the translated personal-folder call.
- Cookie/Material cookie are shape names; Expressive font is a normal descriptive font role and stays translated. No source strings, commands, accepted arguments, runtime names or configuration keys were changed.
- Longer accurate compounds still need eventual visual fit checks. No explanatory label expansions or new manual wrapping line breaks were added.

## Consolidated display-name pass, 2026-10-31

The current policy and approved terms are consolidated in [TERMINOLOGY.md](../../TERMINOLOGY.md). Earlier English-preservation rules and allowlists above are historical. The current pass changes 11 display values, preserving English keys, command syntax, identifiers and all formatting. These are self-reviewed working choices, not native-speaker-verified.

- "Material cookie" → "Biscuit Material"
- "Fruit Salad" → "Salade de fruits"
- "Neutral" → "Neutre"
- "Tonal Spot" → "Accent tonal"
- "Expressive" → "Expressif"
- "Rainbow" → "Arc-en-ciel"
- "Fidelity" → "Fidélité"
- "Cookie clock settings" → "Paramètres de l’horloge Biscuit"
- "Use old sine wave cookie implementation" → "Utiliser l’ancienne implémentation Biscuit à onde sinusoïdale"
- "Cookie" → "Biscuit"
- "Notch" → "Encoche"

Current intentionally English-identical count: 155. Names, units, literal formats and natural shared vocabulary remain valid; the lower count is not the purpose of this pass.
