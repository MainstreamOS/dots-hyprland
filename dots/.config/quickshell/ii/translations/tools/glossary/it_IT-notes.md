# Italian completion notes

Catalog: `it_IT.json`. Source: all 3,221 keys of `en_US.json`, based on mainstream `61761ec5b`.

Translates 2,521 previously English-identical values and corrects 55 existing entries for specific meaning, grammar, count, terminology or protected-syntax defects. Preserves 535 sound existing translations. All 110 remaining English-identical values were individually audited and are listed below. English keys and order are unchanged.

## Validation and review

- Every batch passed structural validation before writing. `tools/catalog-qa.py it_IT` reports zero errors: unique JSON and exact keys, placeholder counts and printf order, actual newlines and joining whitespace, markup/Markdown/backticks, protected names, numeric values, URLs, paths, flags and config filenames.
- All 47 printf-format messages pass through the actual `sdata/lib/tr.sh` with distinct arguments. Exact key order and a separate slash-command audit pass.
- All 13 validator regression tests pass; the nine previously completed languages also pass structural checks.
- A fresh-context review covered all 1,646 initial packet records and consulted source for ambiguous uses. Eleven concrete findings and two additional count corrections were applied; all 13 corrected pairs were independently reread and confirmed resolved. Combined review coverage is 1,647 unique keys. No further concrete errors were found in that review.
- The review packet contains 1,646 unique English/Italian pairs: a 200-key feature sample across 83 source buckets, all 321 actual runtime-placeholder keys, 497 warning/destructive/access/update/recovery candidates, 376 ambiguity candidates, all final 721 AI/phone/Island keys, every old correction and every English-identical value. Sets overlap. The percent-encoded Zerochan URL is also checked exactly.
- Sample selection groups by first candidate source: settings/<first component after modules/settings/>, desktop/<first after modules/ii/>, services/AI for /Ai. or /ai/, otherwise services/other; sdata/ becomes scripts; no source becomes legacy; other paths use apps/<basename>. Sort buckets lexically and keys within each bucket by raw SHA256 of `it_IT-fresh-context-review-v1` + NUL + key, then take round-robin by bucket depth until 200.
- Compact UTF-8 JSON serialization (`ensure_ascii=False`, separators comma and colon) of sample keys hashes to `a1ad8d82f84b1984e8456302211d72fb767bfa37ba2153e3c3838bf06d5857a5`. Packet keys in catalog order hash to `384e6a97b09de080dc2f74cbd5a5c13ec4bc86270d54436c63b200417b4d0d6b`.
- Including the correction reread, review covers 1,647 unique keys. The combined catalog-ordered key list hashes to `1f4fc6d9798b69a4b81d70cd47b9ca7f072300c3ec673d698cb9a407583e8a5e` using the same compact UTF-8 serialization.
- Root compared the entire baseline, audited glossary choices across the catalog, checked every English-identical value, and read source for ambiguous actions and assembled fragments.
- No native-speaker review or live language preview was performed. These are translations with automated validation and a separate review.

## Existing translations replaced

All replacements have concrete reasons; sound earlier translations are retained.

| Exact English key | Previous value | Corrected value | Reason |
| --- | --- | --- | --- |
| Pinned on startup | Fissa sullo schermo | Fissa all'avvio | Restore the startup condition; the source controls the dock startup-pinned state. |
| Depends on workspace | Abilita per spazi di lavoro | Dipende dallo spazio di lavoro | The option makes panning depend on workspace; it does not enable workspaces. |
| No API key<br>Set it with /key YOUR_API_KEY | Nessuna chiave API<br>Usa /key per impostarla | Nessuna chiave API<br>Impostala con /key YOUR_API_KEY | Restore the literal command argument/metavariable required by the source syntax. |
| Critically low battery | Batteria scarica | Batteria a livello critico | Restore the critical battery severity. |
| %1 notifications | %1 notifiche | Notifiche: %1 | Concrete correction found during independent review; see review corrections below. |
| Cannot find a GPS service. Using the fallback method instead. | Servizio GPS non disponibile. Verrà utilizzata la città preimpostata. | Impossibile trovare un servizio GPS. Verrà usato il metodo alternativo. | Do not promise a preset city; English promises only an unspecified fallback method. |
| Keep system awake | Mantieni schermo attivo | Mantieni il sistema attivo | Inhibits system sleep, not just the screen. |
| Finished tasks will go here | Nessun promemoria | I promemoria completati appariranno qui | Completed tasks will appear here; the old value incorrectly said there are no tasks. |
| Shell conflicts killer | Avviso conflitti | Risolvi conflitti della shell | The feature terminates conflicting programs, not merely warns about them. |
| API key is set<br>Change with /key YOUR_API_KEY | Chiave API impostata<br>Usa /key per cambiarla | Chiave API impostata<br>Modificala con /key YOUR_API_KEY | Restore the literal command argument/metavariable required by the source syntax. |
| Always show numbers | Mostra numeri | Mostra sempre i numeri | Restore always in the workspace-number option. |
| Scale (%) | Dimensione (%) | Scala (%) | Keep scale distinct from the separate size control and use the glossary term. |
| Usage | Istruzioni | Utilizzo | Usage denotes use/consumption as well as command usage, not instructions only. |
| EasyEffects \| Right-click to configure | EasyEffects | EasyEffects \| Clic destro per configurare | Restore the missing right-click action. |
| Please charge!<br>Automatic suspend triggers at %1 | Ricarica la batteria!<br>Sospensione automatica in %1 | Ricarica la batteria!<br>La sospensione automatica si attiva al %1 | The placeholder is a battery threshold, not a wait duration. |
| Prevents abrupt increments and restricts volume limit | Impedice aumenti improvvisi del volume e ne imposta un limite. | Impedisce aumenti improvvisi e limita il volume | Correct Impedice to Impedisce. |
| Not visible to model | Non visible al modello | Non visibile al modello | Correct visible to Italian visibile. |
| Hug | Stondato | Aderente | Hug adheres to the edge; it does not just mean rounded. |
| Large language models | Intelligenza artificiale | Grandi modelli linguistici | Large language models are a specific model category, not all artificial intelligence. |
| Policies | Servizi | Regole | Policies are rules, not the services themselves. |
| %1 \| Right-click to configure | %1 | %1 \| Clic destro per configurare | Restore the missing right-click action. |
| Action | Comandi | Azione | Action is singular and broader than commands. |
| ☕ Break: %1 minutes | ☕ Pausa breve: %1 minuti | ☕ Pausa breve: %1 min | Use the count-neutral minute abbreviation. |
| Depends on sidebars | Abilita per barre laterali | Dipende dalle barre laterali | The option makes panning depend on sidebars; it does not enable sidebars. |
| Keybinds | Comandi | Scorciatoie | Keybinds are keyboard shortcuts, not commands. |
| Could be better if you make a ton of typos,<br>but results can be weird and might not work with acronyms<br>(e.g. "GIMP" might not give you the paint program) | Può aiutare in caso di refusi,<br>ma i risultati potrebbero non essere accurati<br>(es. "GIMP" potrebbe non restituire l'omonimo programma) | Può aiutare se fai molti errori di battitura,<br>ma i risultati possono essere strani e non funzionare con gli acronimi<br>(ad es. "GIMP" potrebbe non trovare il programma di grafica) | Restore the missing limitation about acronyms in the fuzzy-search warning. |
| Current tool: %1<br>Set it with %2tool TOOL | Strumento attuale: %1<br>Usa %2tool per cambiarlo | Strumento attuale: %1<br>Impostalo con %2tool TOOL | Restore the literal command argument/metavariable required by the source syntax. |
| That didn't work. Tips:<br>- Check your tags and NSFW settings<br>- If you don't have a tag in mind, type a page number | Nessun risultato. Suggerimenti:<br>- Controlla i tag e le impostazioni NSFW<br>- Se non hai un tag in mente, inserici il numero di pagina | Nessun risultato. Suggerimenti:<br>- Controlla i tag e le impostazioni NSFW<br>- Se non hai un tag in mente, inserisci il numero di pagina | Correct inserici to inserisci. |
| Reload Hyprland & Quickshell | Riavvia Hyprland e Quickshell | Ricarica Hyprland e Quickshell | Reload the configurations; do not instruct a session restart. |
| Current model: %1<br>Set it with %2model MODEL | Modello attuale: %1<br>Usa %2model per cambiarlo | Modello attuale: %1<br>Impostalo con %2model MODEL | Restore the literal command argument/metavariable required by the source syntax. |
| ... and %1 more | ... e altri %1 | ... e ancora %1 | Avoid altri 1 with a count-neutral construction. |
| Cancel | Cancella | Annulla | Cancel means Annulla, not delete/clear. |
| Temperature<br>Change with /temp VALUE | Temperatura<br>Usa /temp per cambiarla | Temperatura<br>Modifica con /temp VALUE | Restore the literal command argument/metavariable required by the source syntax. |
| Night Light \| Right-click to toggle Auto mode | Modalità notte | Modalità notte \| Clic destro per attivare/disattivare Auto | Restore the missing right-click Auto-mode control. |
| For storing API keys and other sensitive information | Gestione credenziali e informazioni sensibili | Per conservare chiavi API e altre informazioni sensibili | Restore the specific API-key storage meaning and required acronym. |
| 🌿 Long break: %1 minutes | 🌿 Pausa lunga: %1 minuti | 🌿 Pausa lunga: %1 min | Use the count-neutral minute abbreviation. |
| Current API endpoint: %1<br>Set it with %2mode PROVIDER | Endpoint API: %1<br>Usa %2mode per cambiarlo | Endpoint API attuale: %1<br>Impostalo con %2mode PROVIDER | Restore the literal command argument/metavariable required by the source syntax. |
| Message the model... "%1" for commands | "%1" per mostrare i comandi | Scrivi al modello... "%1" per i comandi | Restore the message-input instruction that had been omitted. |
| 🔴 Focus: %1 minutes | 🔴 Focus: %1 minuti | 🔴 Concentrazione: %1 min | Use Concentrazione consistently for Pomodoro, distinct from window focus, and a count-neutral unit. |
| %1 characters | %1 caratteri | Caratteri: %1 | Use a count-neutral label instead of 1 caratteri. |
| **Pricing**: free. Data used for training.<br><br>**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key | **Prezzo**: gratuito. I tuoi dati vengono usati per training.<br><br>**Istruzioni**: Accedi al tuo account Google, abilita i permessi richiesti da AI Studio, torna indietro e seleziona "Get API key" | **Prezzo**: gratuito. Dati usati per l'addestramento.<br><br>**Istruzioni**: Accedi al tuo account Google, consenti ad AI Studio di creare un progetto Google Cloud o ciò che richiede, torna indietro e fai clic su Get API key | Restore the specific Google Cloud project creation step, not just unspecified permissions. |
| Commands, edit configs, search.<br>Takes an extra turn to switch to search mode if that's needed | Comanda, modifica la richiesta, cerca.<br>Richiede un turno in più per attivare la modalità ricerca se richiesta | Comandi, modifica configurazioni, ricerca.<br>Richiede un turno in più per passare alla modalità ricerca, se necessario | The tool edits configurations, not the user request. |
| Privacy Policy | Privacy policy | Informativa sulla privacy | Translate the remaining English policy label using the standard localized term. |
| Enter tags, or "%1" for commands | "%1" per mostrare i comandi | Inserisci tag, oppure "%1" per i comandi | Restore the omitted tag-entry instruction. |
| %1 queries pending | %1 ricerche in sospeso | Ricerche in sospeso: %1 | Use a count-neutral pending-query label. |
| Please charge!<br>Automatic suspend triggers at %1% | Ricarica la batteria!<br>Sospensione automatica in %1% | Ricarica la batteria!<br>La sospensione automatica si attiva al %1% | The placeholder is a battery threshold, not a wait duration. |
| **Pricing**: free tier, with data used for training. Web search needs billing turned on.<br><br>**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key | **Prezzo**: piano gratuito, i tuoi dati vengono usati per training. La ricerca web richiede la fatturazione attiva.<br><br>**Istruzioni**: Accedi al tuo account Google, abilita i permessi richiesti da AI Studio, torna indietro e seleziona "Get API key" | **Prezzo**: livello gratuito, con dati usati per l'addestramento. La ricerca web richiede la fatturazione attiva.<br><br>**Istruzioni**: Accedi al tuo account Google, consenti ad AI Studio di creare un progetto Google Cloud o ciò che richiede, torna indietro e fai clic su Get API key | Restore the Google Cloud project creation step from the source. |
| Signed in. The plan models are in the picker now: type /model to choose between Gemini 3.8 Flash (High, Medium, Low) and Gemini 3.1 Pro (High, Low). | Accesso effettuato. I modelli del piano sono ora nel selettore: digita /model per scegliere tra Gemini 3.8 Flash (High, Medium, Low) e Gemini 3.1 Pro (High, Low). | Accesso effettuato. I modelli dell'abbonamento sono nel selettore: digita /model per scegliere tra Gemini 3.8 Flash (High, Medium, Low) e Gemini 3.1 Pro (High, Low). | Distinguish subscription models from execution Piano mode. |
| Set thinking level (reasoning effort). Values: minimal, low, medium, high, auto. Replaces deprecated thinking budget. | Imposta il livello di ragionamento (sforzo logico). Valori: minimal, low, medium, high, auto. Sostituisce il budget di pensiero deprecato. | Imposta il livello di ragionamento (intensità di ragionamento). Valori: minimal, low, medium, high, auto. Sostituisce il precedente budget di ragionamento. | Use the existing intensity-of-reasoning terminology and translate the prose budget concept. |
| Signed in. Gemini Flash and Gemini Pro are in the picker now. Adjust thinking level with the reasoning pill or /think. | Accesso effettuato. Gemini Flash e Gemini Pro sono ora nel selettore. Regola il livello di ragionamento con la pillola o con /think. | Accesso effettuato. Gemini Flash e Gemini Pro sono nel selettore. Regola il livello di ragionamento con la capsula del ragionamento o con /think. | A pill is the reasoning UI capsule, not medicine. |
| Signed in. Gemini Flash and Gemini Pro are in the picker now. Adjust thinking level with /think. | Accesso effettuato. Gemini Flash e Gemini Pro sono ora nel selettore. Regola il livello di pensiero con /think. | Accesso effettuato. Gemini Flash e Gemini Pro sono ora nel selettore. Regola il livello di ragionamento con /think. | Match the existing level-of-reasoning control label. |
| All files in ~ (%1 matches) | Tutti i file in ~ (%1 risultati) | Tutti i file in ~ (risultati: %1) | Use a count-neutral match label for the single-result case. |
| Commands: /model <name> · /mode [ask\|auto\|plan] | Comandi: /model <nome> · /mode [ask\|auto\|plan] | Comandi: /model <name> · /mode [ask\|auto\|plan] | Restore the literal command argument/metavariable required by the source syntax. |
| Signed in. The plan models are in the picker now: type /model to choose one. | Accesso effettuato. I modelli del piano ora sono nel selettore: digita /model per sceglierne uno. | Accesso effettuato. I modelli dell'abbonamento ora sono nel selettore: digita /model per sceglierne uno. | Distinguish subscription models from execution Piano mode. |
| Only local models are allowed right now. To use online models, set AI to Yes in Settings > Interface > Left Sidebar. | Al momento sono consentiti solo i modelli locali. Per usare i modelli online, imposta AI su Sì in Impostazioni > Interfaccia > Left Sidebar. | Al momento sono consentiti solo i modelli locali. Per usare i modelli online, imposta AI su Sì in Impostazioni > Interfaccia > Barra laterale sinistra. | Translate the Left Sidebar breadcrumb to match the settings label. |

## Corrections from independent review

| Exact English key | Correction |
| --- | --- |
| Cannot find a GPS service. Using the fallback method instead. | Preserve the unspecified fallback method, without promising a preset city. |
| Always show numbers | Restore always in the workspace-number setting. |
| ... and %1 more | Use count-neutral ancora rather than altri 1. |
| %1 queries pending | Use a count-neutral pending-query label. |
| Waiting for your location, using %1 to %2 meanwhile | Describe the interval the system uses while waiting, not an instruction to the user. |
| Locked + repeats while held | Repeat while the key is held, not just once at key press. |
| found | Use the count-neutral suffix in elenco after the discovered-drive count. |
| images | Use invariant file immagine after an export-image count, including one. |
| %1 is saved for one account only, so sharing is not offered on it. To share on it, forget this network on the Wi-Fi page, then connect to it again. | Enable folder sharing on the network; do not describe sharing the network itself. |
| All files in ~ (%1 matches) | Use a count-neutral match label. |
| Drop files anywhere to send to %1 | Say explicitly that dropping sends the files, preserving the destination fallback. |
| contact | Include un so the fallback composes as a un contatto. |
| Break time · %1 min remaining | The break-time message also appears during long breaks, so do not narrow it to Pausa breve. |

## Intentionally English-identical values

Each entry was checked individually. These are names, literal formats, identifiers or normal Italian technical loanwords, not untranslated English prose.

| Exact English key | Reason |
| --- | --- |
| Password | Password is the normal Italian credential term. |
| Audio | Audio is Italian technical vocabulary. |
| Volume | Volume is the Italian audio-level noun. |
| Gamma | Gamma is the conventional color control. |
| OK | Conventional OK confirmation. |
| Auto | Auto is the chosen compact automatic-mode label. |
| illogical-impulse | Preserved product, project, named layout, protocol or command label. |
| No | No is also the Italian negative. |
| Anime | Anime is the established genre name. |
| Dock | Dock is the established desktop loanword. |
| Timer | Timer is the chosen Italian control term. |
| Superpaste | Superpaste is the named feature matching the typed command. |
| GitHub | Preserved product, project, named layout, protocol or command label. |
| App | App is an invariant Italian loanword. |
| Cloudflare WARP (1.1.1.1) | Preserved product, project, named layout, protocol or command label. |
| Bluetooth | Preserved product, project, named layout, protocol or command label. |
| Pomodoro | Preserved product, project, named layout, protocol or command label. |
| AI | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| Cloudflare WARP | Preserved product, project, named layout, protocol or command label. |
| Timeout (ms) | Timeout is a standard Italian technical loanword; ms is the unit. |
| Android | Preserved product, project, named layout, protocol or command label. |
| Internet | Internet is standard Italian terminology. |
| EasyEffects | Preserved product, project, named layout, protocol or command label. |
| Google Lens | Preserved product, project, named layout, protocol or command label. |
| Auto, | Compact Auto-mode fragment with its original comma. |
| %1 nits | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| %1s | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| %1s… | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| %1… | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| 0° | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| 50 % APL  ·  %1 nits | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| dd/MM | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| dd.MM | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| Emoji | Emoji is an invariant Italian loanword. |
| Freq: | Conventional frequency abbreviation. |
| LCD HDR 1000 | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| LCD HDR 600 | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| MM/dd | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| Mouse | Mouse is the Italian device term. |
| OLED / QD-OLED | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| Swap | Swap is the established memory term. |
| Temp: | Conventional temperature abbreviation. |
| Touchpad | Touchpad is the Italian device term. |
| VRAM: | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| Web | Web is standard Italian terminology. |
| DaVinci Resolve | Preserved product, project, named layout, protocol or command label. |
| DaVinci Resolve Studio | Preserved product, project, named layout, protocol or command label. |
| File | File is an invariant Italian loanword. |
| Celsius | Named temperature scale. |
| Fahrenheit | Named temperature scale. |
| Master | Preserved product, project, named layout, protocol or command label. |
| Monocle | Preserved product, project, named layout, protocol or command label. |
| OBS Studio | Preserved product, project, named layout, protocol or command label. |
| Per app | Per app is already grammatical Italian, with invariant app. |
| Server | Server is an invariant Italian loanword. |
| %1 (%2) | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
|  min | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| tearing | Tearing is the established graphics term. |
| Discord | Preserved product, project, named layout, protocol or command label. |
| min | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| GitHub Sponsors | Preserved product, project, named layout, protocol or command label. |
| Ko-fi | Preserved product, project, named layout, protocol or command label. |
| Patreon | Preserved product, project, named layout, protocol or command label. |
| CRT | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| Zoom | Zoom is the conventional UI/motion term. |
| Pixel | Pixel is the conventional invariant Italian unit. |
| ok | Conventional lowercase ok status. |
| updatems | Preserved product, project, named layout, protocol or command label. |
| updatems-system | Preserved product, project, named layout, protocol or command label. |
| macrecovery | Preserved product, project, named layout, protocol or command label. |
| AUR (yay/paru): | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| Flatpak: | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| Snap: | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| <none> | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| GIMP | Preserved product, project, named layout, protocol or command label. |
| Krita | Preserved product, project, named layout, protocol or command label. |
| LibreOffice | Preserved product, project, named layout, protocol or command label. |
| OnlyOffice | Preserved product, project, named layout, protocol or command label. |
| Sunshine | Preserved product, project, named layout, protocol or command label. |
| Moonlight | Preserved product, project, named layout, protocol or command label. |
| Blender | Preserved product, project, named layout, protocol or command label. |
| 15 fps | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| 30 fps | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| Standard | Standard is also the Italian adjective. |
| Tour | Tour is standard Italian UI vocabulary. |
| Download: | Download is a standard Italian transfer label. |
| Upload: | Upload is a standard Italian transfer label. |
| WiVRn | Preserved product, project, named layout, protocol or command label. |
| Antigravity CLI — agy update | Preserved product, project, named layout, protocol or command label. |
| Antigravity: | Preserved product, project, named layout, protocol or command label. |
| Extra | Extra is an Italian adjective. |
| Home | Home is the conventional file-manager location label. |
| Max | Max is the existing compact effort label. |
| Ollama | Preserved product, project, named layout, protocol or command label. |
| UltraCode | Preserved product, project, named layout, protocol or command label. |
| GIF | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| Video | Video is an invariant Italian media term. |
| Instagram Reel | Preserved product, project, named layout, protocol or command label. |
| %1 B | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| %1 KB | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| %1 MB | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| %1 GB | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| LocalSend | Preserved product, project, named layout, protocol or command label. |
| Computer | Computer is an invariant Italian noun. |
| RAM | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| CPU | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| Ethernet | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| Wi-Fi | Unit, number/date format, acronym, placeholder-only label or updater sentinel. |
| Dynamic Island | Preserved product, project, named layout, protocol or command label. |
| Dwindle | Preserved product, project, named layout, protocol or command label. |

## Shared keys and source issues

- `Play` is shared by a gaming heading and playback controls. Riproduci prioritizes actionable playback; the heading needs a separate key for Gioca/Giochi.
- Shared `From` Da and `To` A work for gradient endpoints and the recipient label; no context markers were invented.
- Provider subscription Plan is Abbonamento; execution Plan is Piano. Window focus uses Focus while Pomodoro uses Concentrazione. Existing task terminology Promemoria is preserved and count invariant. Power-profile Balanced preserves Equilibrato; AI response/reasoning Balanced preserves Bilanciato.
- `Locked` is both a screen state and a shortcut flag. Shortcut descriptions specify working with the screen locked. `Launch on startup` actually controls screen locking, not autostart apps. Hug is the edge-adhering style; Junction is the GPU hotspot; Swap is memory swap.
- Contact privacy hides Island alerts/personal details, not communication on the phone. The streaming setting currently suppresses alerts when selected Discord/OBS windows or processes exist, without verifying active streaming; source behavior needs separate attention.
- Sharing-password validation accepts printable ASCII only, while English mentions only accented letters and emoji. Translation preserves the supplied warning; source should state the full restriction. Clearing a firewall zone refers to the connection assignment, not deleting the zone.
- The old git stash list recovery instruction lists stashes rather than restoring them; the newer message supplies git stash show --include-untracked stash@{0} and git stash pop. Preserve supplied literal commands and resolve the older source separately.
- Older help uses Ctrl+P to detach; newer help uses Ctrl+D to detach and Ctrl+P to pin. Older API help uses %2mode PROVIDER, while newer execution help uses ask|auto|plan. Supplied commands remain unchanged.
- One update-advice key contains literal \u2014 text. Its value uses natural Italian punctuation without modifying the key. Literal Snapshots/linux boot entries, commands, identifiers, service names, URLs, paths and flags are preserved.
- The old account-deletion dialog concatenates an opening question, the account name and a closing quote/question with an irreversible-action warning. Italian preserves a grammatical combined question.
- The images suffix after a theme export count uses file immagine, invariant for one or many; it also remains suitable as a category label. Existing plural line-scroll text is only used for previewLineCount > 1; its preceding character count is shown only when the preview scrolls.
- Country names come directly from the English iso3166.tab labels, with a few explicit English renamings in the source. This is a source localization limitation; the translation does not invent localized country identifiers.
- Names, model descriptions and pricing are translated as supplied, not externally verified as current claims.

## Historical reasoning review

Historical review record. Current rules and display names are consolidated in
[TERMINOLOGY.md](../../TERMINOLOGY.md); the English-preservation decisions in this
old report are superseded where the current guide specifies localized labels.

This is the focused follow-up requested after Ukrainian completion. It applies
the owner’s updated terminology, HANDOFF.md, and corrected es_MX example from
`/home/itsjustdroid/Downloads/updated-reasoning`. It supplements the initial
glossary and completion notes; the decisions below supersede older decisions
on these terms. Good existing values outside concrete findings are preserved.

Changes: **43 of 3,221 values**. Source English keys and order are
unchanged. **123 values remain English-identical**; new ones introduced
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
| Island position | Posizione isola |
| Island style | Stile isola |
| Pills | Capsule |
| Hug | Esteso |
| Notch | Notch |
| Earbang protection | Protezione dai picchi |
| Unmuted | Audio attivo |
| Home | Home |
| Swap | Swap |
| Tray | Area di notifica |
| System tray | Area di notifica |
| Blur | Sfocatura |

All seven named palette presets stay in English: Fruit Salad, Neutral, Tonal Spot, Expressive, Rainbow, Fidelity, Monochrome.
Hyprland scratchpad, submap, fake fullscreen and pseudo-tiling stay literal.
Capitalization such as Material Cookie remains where it is already recognizable
English and correct for the locale; no case-only rewrites were made.

Home and Area di notifica remain: these are conventional Italian file-manager
and tray labels, not a start-page mistranslation or an explanatory gloss.

### Exact value changes

| Exact English key | Previous committed value | Reviewed value | Reason |
| --- | --- | --- | --- |
| Material cookie | Biscotto Material | Material cookie | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Fruit Salad | Macedonia | Fruit Salad | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Dotfiles | File di configurazione | Dotfiles | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Neutral | Neutro | Neutral | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Tonal Spot | Accento tonale | Tonal Spot | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Expressive | Espressivo | Expressive | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Hug | Aderente | Esteso | Name the edge-spanning style; the earlier wording meant an embrace or attachment to an edge. |
| Rainbow | Arcobaleno | Rainbow | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Fidelity | Fedeltà | Fidelity | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Earbang protection | Protezione udito | Protezione dai picchi | Name sudden volume-jump protection concisely; this is neither visual flashing nor headphone hardware protection. |
| Cookie clock settings | Impostazioni orologio biscotto | Impostazioni orologio Cookie | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Monochrome | Monocromatico | Monochrome | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Use old sine wave cookie implementation | Usa la vecchia implementazione del biscotto con onda sinusoidale | Usa la vecchia implementazione di Cookie con onda sinusoidale | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Cookie | Biscotto | Cookie | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Enter submap | Entra nella mappa secondaria | Entra in submap | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Skip dotfiles | Salta file di configurazione | Salta dotfiles | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Skip the Mainstream dotfiles refresh step (updatems). Dotfiles update only when a new release tag is published upstream; turn this on to manage them manually. | Salta il rinnovo dei file di configurazione Mainstream (updatems). Questi file si aggiornano solo quando viene pubblicato un nuovo tag di rilascio nel progetto originale; attiva per gestirli manualmente. | Salta il rinnovo dei dotfiles Mainstream (updatems). I dotfiles si aggiornano solo quando viene pubblicato un nuovo tag di rilascio nel progetto originale; attiva per gestirli manualmente. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Special (scratchpad) | Speciale (area temporanea) | Speciale (scratchpad) | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle fake fullscreen | Attiva/disattiva schermo intero simulato | Attiva/disattiva fake fullscreen | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle pseudo-tiling | Attiva/disattiva pseudo-affiancamento | Attiva/disattiva pseudo-tiling | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle scratchpad | Attiva/disattiva area temporanea | Attiva/disattiva scratchpad | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| end-4 — Dotfiles | end-4 — File di configurazione | end-4 — Dotfiles | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| How deep the frost goes. Deeper costs more to draw. | La profondità dell'effetto satinato. Più è profondo, più costa disegnarlo. | La profondità della sfocatura. Più è profonda, più costa disegnarla. | Use the chosen blur term consistently for blur and frosted surfaces. |
| no frost | senza effetto satinato | senza sfocatura | Use the chosen blur term consistently for blur and frosted surfaces. |
| No frost behind it | Nessun effetto satinato dietro | Nessuna sfocatura dietro | Use the chosen blur term consistently for blur and frosted surfaces. |
| Notch | Tacca | Notch | Preserve Notch as the named drawn style, not a physical hardware-cutout noun. |
| Toggle the scratchpad workspace | Attiva/disattiva spazio di lavoro temporaneo | Attiva/disattiva spazio di lavoro scratchpad | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Exit the keybind submap | Esci dalla mappa secondaria delle scorciatoie | Esci dal submap delle scorciatoie | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Dotfiles: deferred — the system package update failed, and dotfile releases can depend on packages it would have installed. Re-run the update once the package step succeeds. | File di configurazione: rinviati, l'aggiornamento pacchetti di sistema non è riuscito e le nuove configurazioni possono dipendere dai pacchetti che avrebbe installato. Ripeti l'aggiornamento quando il passaggio pacchetti riesce. | Dotfiles: rinviati, l'aggiornamento pacchetti di sistema non è riuscito e i nuovi dotfiles possono dipendere dai pacchetti che avrebbe installato. Ripeti l'aggiornamento quando il passaggio pacchetti riesce. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Mainstream dotfiles — updatems | File di configurazione Mainstream — updatems | Dotfiles Mainstream — updatems | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles: skipped (per --skip-dotfiles) | File di configurazione: saltati (per --skip-dotfiles) | Dotfiles: saltati (per --skip-dotfiles) | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| No dotfiles clone at %s — bootstrapping from %s | Nessun clone delle configurazioni in %s, inizializzazione da %s | Nessun clone dei dotfiles in %s, inizializzazione da %s | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Cloned dotfiles to %s | Configurazioni clonate in %s | Dotfiles clonati in %s | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles (updatems): | File di configurazione (updatems): | Dotfiles (updatems): | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| The dotfiles clone at %s is damaged. Setting it aside as %s and cloning again. | Il clone delle configurazioni in %s è danneggiato. Lo sposto in %s e clono di nuovo. | Il clone dei dotfiles in %s è danneggiato. Lo sposto in %s e clono di nuovo. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Update finished, but the Mainstream dotfiles did not update. See the Dotfiles line in the summary above. | Aggiornamento terminato, ma i file di configurazione Mainstream non sono stati aggiornati. Vedi la riga File di configurazione nel riepilogo sopra. | Aggiornamento terminato, ma i dotfiles Mainstream non sono stati aggiornati. Vedi la riga Dotfiles nel riepilogo sopra. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| [DRY-RUN] The dotfiles clone at %s is damaged; would set it aside as %s and clone again. | [DRY-RUN] Il clone delle configurazioni in %s è danneggiato; lo sposterei in %s e clonerei di nuovo. | [DRY-RUN] Il clone dei dotfiles in %s è danneggiato; lo sposterei in %s e clonerei di nuovo. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Refreshing /etc/skel from the dotfiles... | Rinnovo di /etc/skel dai file di configurazione... | Rinnovo di /etc/skel dai dotfiles... | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles: waiting for the desktop update that matches the new Qt. | File di configurazione: attendo l'aggiornamento della scrivania compatibile con il nuovo Qt. | Dotfiles: attendo l'aggiornamento della scrivania compatibile con il nuovo Qt. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles: waiting for the system packages, which were held back. | File di configurazione: attendo i pacchetti di sistema trattenuti. | Dotfiles: attendo i pacchetti di sistema trattenuti. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Signed in. The plan models are in the picker now: type /model to choose between Gemini 3.8 Flash (High, Medium, Low) and Gemini 3.1 Pro (High, Low). | Accesso effettuato. I modelli dell'abbonamento sono nel selettore: digita /model per scegliere tra Gemini 3.8 Flash (High, Medium, Low) e Gemini 3.1 Pro (High, Low). | Accesso effettuato. I modelli dell'abbonamento sono nel selettore: digita /model per scegliere tra Gemini 3.8 Flash (alto, medio, basso) e Gemini 3.1 Pro (alto, basso). | The parenthesized names are visible effort levels, not literal command arguments. |
| Thinking Level: %1<br>Click to cycle (minimal → low → medium → high → auto) | Livello di ragionamento: %1<br>Fai clic per cambiare (minimal → low → medium → high → auto) | Livello di ragionamento: %1<br>Fai clic per cambiare (minimo → basso → medio → alto → automatico) | Translate visible click-cycle effort labels; accepted typed command arguments elsewhere remain literal. |
| Frosted widget backgrounds | Sfondi widget satinati | Sfondi widget sfocati | Use the chosen blur term consistently for blur and frosted surfaces. |

### Newly English-identical values

These are restored names/identifiers, not untranslated prose.

- "Material cookie"
- "Fruit Salad"
- "Dotfiles"
- "Neutral"
- "Tonal Spot"
- "Expressive"
- "Rainbow"
- "Fidelity"
- "Monochrome"
- "Cookie"
- "end-4 — Dotfiles"
- "Notch"
- "Dotfiles (updatems):"

### Source-confirmed exceptions and remaining limits

- Standalone Swap means memory in Resources.qml, ResourcesPanel.qml and ResourcesPopup.qml. Window-action keys use exchange verbs separately. The offline Spanish interpretation did not have source access.
- at in the automatic-suspend row is a battery percentage. Up %1 is uptime. Home in KeybindCaptureItem.qml is an untranslated X11 keysym and does not share the translated personal-folder call.
- Cookie/Material cookie are shape names; Expressive font is a normal descriptive font role and stays translated. No source strings, commands, accepted arguments, runtime names or configuration keys were changed.
- Longer accurate compounds still need eventual visual fit checks. No explanatory label expansions or new manual wrapping line breaks were added.

## Consolidated display-name pass, 2026-10-31

The current policy and approved terms are consolidated in [TERMINOLOGY.md](../../TERMINOLOGY.md). Earlier English-preservation rules and allowlists above are historical. The current pass changes 12 display values, preserving English keys, command syntax, identifiers and all formatting. These are self-reviewed working choices, not native-speaker-verified.

- "Material cookie" → "Biscotto Material"
- "Fruit Salad" → "Macedonia"
- "Neutral" → "Neutro"
- "Tonal Spot" → "Accento tonale"
- "Expressive" → "Espressivo"
- "Rainbow" → "Arcobaleno"
- "Fidelity" → "Fedeltà"
- "Cookie clock settings" → "Impostazioni orologio Biscotto"
- "Monochrome" → "Monocromatico"
- "Use old sine wave cookie implementation" → "Usa la vecchia implementazione di Biscotto con onda sinusoidale"
- "Cookie" → "Biscotto"
- "Notch" → "Tacca"

Current intentionally English-identical count: 114. Names, units, literal formats and natural shared vocabulary remain valid; the lower count is not the purpose of this pass.
