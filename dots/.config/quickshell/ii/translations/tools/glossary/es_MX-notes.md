# Mexican Spanish completion notes

Catalog: `es_MX.json`. Source: all 3,221 keys of `en_US.json`, based on mainstream `eccc8110c`.

Completed 2,204 previously English-identical values. Corrected 31 existing translations for concrete defects; the other 881 existing translations are preserved. There are 105 intentional English-identical values, listed individually below. Keys and their order remain unchanged.

## Validation and review

- Each translation batch passed structural validation before it was written.
- Full catalog passes `python3 tools/catalog-qa.py es_MX`: keys, JSON duplication, placeholders, printf order, newline counts, joining whitespace, markup and Markdown, protected names, numeric values, URLs, paths, command flags and config filenames.
- Nine regression tests cover checker failures and valid reordered arguments, URL punctuation and CJK-adjacent protected names.
- All 47 printf-format messages were exercised through the actual `sdata/lib/tr.sh` translator with distinct substitution arguments. The catalog's key order also matches English exactly.
- A separate fresh-context review examined a deterministic sample of 200 keys (`random.Random(20261026)`), all 322 placeholder keys, and warning, destructive-action, permission and recovery candidates: 1,076 distinct entries in total. Concrete corrections were applied.
- A glossary consistency scan covered workspaces, sidebars, dock, Night Light, launcher, snapshots, keyring, app drawer, wallpaper, pinning and windows. Command/config references were distinguished from displayed labels.
- No native-speaker review or live desktop language preview has been performed. These are translations with automated checks and independent review.

## Existing translations corrected

Every existing non-English value changed is listed here. These are limited corrections, not a general rewrite.

| English key | Reason |
| --- | --- |
| Depends on workspace | Remove a line break absent from the English key. |
| No API key<br>Set it with /key YOUR_API_KEY | Restore literal command metavariables or syntax that had been translated. |
| %1 notifications | Use count-neutral phrasing that works for 1 as well as larger counts. |
| Max allowed increase | Remove a line break absent from the English key. |
| Usage: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt><br>Supply <tt>i</tt> when you want images<br>Examples:<br><tt>%1superpaste 4i</tt> for the last 4 images<br><tt>%1superpaste 7</tt> for the last 7 entries | Restore literal command metavariables or syntax that had been translated. |
| API key is set<br>Change with /key YOUR_API_KEY | Restore literal command metavariables or syntax that had been translated. |
| Usage: %1tool TOOL_NAME | Restore literal command metavariables or syntax that had been translated. |
| ☕ Break: %1 minutes | Use a count-neutral minute abbreviation, including a duration of 1. |
| Depends on sidebars | Remove a line break absent from the English key. |
| Low warning | Identify the low battery-charge threshold, rather than describing the warning as low. |
| Current tool: %1<br>Set it with %2tool TOOL | Restore literal command metavariables or syntax that had been translated. |
| Config file | Remove a line break absent from the English key. |
| Current model: %1<br>Set it with %2model MODEL | Restore literal command metavariables or syntax that had been translated. |
| %1   •   %2 tasks | Use count-neutral phrasing that works for 1 as well as larger counts. |
| Temperature<br>Change with /temp VALUE | Restore literal command metavariables or syntax that had been translated. |
| 🌿 Long break: %1 minutes | Use a count-neutral minute abbreviation, including a duration of 1. |
| Current API endpoint: %1<br>Set it with %2mode PROVIDER | Restore literal command metavariables or syntax that had been translated. |
| 🔴 Focus: %1 minutes | Use the Pomodoro glossary term Concentración and a count-neutral minute abbreviation. |
| %1 characters | Use count-neutral phrasing that works for 1 as well as larger counts. |
| Usage: %1save CHAT_NAME | Restore literal command metavariables or syntax that had been translated. |
| Usage: %1load CHAT_NAME | Restore literal command metavariables or syntax that had been translated. |
| Language not listed or incomplete translations?<br>You can choose to generate translations for it with Gemini.<br>1. Open the left sidebar with Super+A, set model to Gemini (if it isn't already)<br>2. Type /key, hit Enter and follow the instructions<br>3. Type /key YOUR_API_KEY<br>4. Type the locale of your language below and press Generate | Restore literal command metavariables or syntax that had been translated. |
| Set thinking level (reasoning effort). Values: minimal, low, medium, high, auto. Replaces deprecated thinking budget. | Use glossary term esfuerzo de razonamiento for reasoning effort. |
| All files in ~ (%1 matches) | Use count-neutral phrasing that works for 1 as well as larger counts. |
| Command execution skipped: Plan mode is active. | Use Planificar consistently for the execution mode, retaining literal plan command arguments. |
| Commands: /model <name> · /mode [ask\|auto\|plan] | Restore literal command metavariables or syntax that had been translated. |
| Config change skipped: Plan mode is active. | Use Planificar consistently for the execution mode, retaining literal plan command arguments. |
| Controls how AI models and agent CLIs handle permissions and tools.<br>• Ask: Asks for confirmation before executing commands.<br>• Auto: Automatically approves tool execution, commands, and web fetching.<br>• Plan: Focuses strictly on planning and architecture without running commands or edits. | Use Planificar consistently for the execution mode, retaining literal plan command arguments. |
| Plan mode is on, so this was not run: %1 | Use Planificar consistently for the execution mode, retaining literal plan command arguments. |
| Toggle Plan mode (architectural planning without executing edits) | Use Planificar consistently for the execution mode, retaining literal plan command arguments. |
| Only local models are allowed right now. To use online models, set AI to Yes in Settings > Interface > Left Sidebar. | Translate the embedded Left Sidebar settings breadcrumb consistently. |

## Intentional English-identical values

These are names or identifiers, units and formats, or conventional Spanish words also used in English. None is being counted as an untranslated prose message.

| Exact value | Reason |
| --- | --- |
| Audio | Conventional Spanish term or accepted software loanword. |
| Gamma | Conventional Spanish term or accepted software loanword. |
| 12h am/pm | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Auto | Conventional Spanish term or accepted software loanword. |
| illogical-impulse | Product, project, preset/layout or executable name. |
| No | Conventional Spanish term or accepted software loanword. |
| 12h AM/PM | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Anime | Conventional Spanish term or accepted software loanword. |
| Dock | Conventional Spanish term or accepted software loanword. |
| GitHub | Product, project, preset/layout or executable name. |
| Terminal | Conventional Spanish term or accepted software loanword. |
| Cloudflare WARP (1.1.1.1) | Unit, numeric/format token, technical identifier or placeholder-only text. |
| 24h | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Total: | Conventional Spanish term or accepted software loanword. |
| Emojis | Conventional Spanish term or accepted software loanword. |
| Distro | Conventional Spanish term or accepted software loanword. |
| Bluetooth | Product, project, preset/layout or executable name. |
| Pomodoro | Product, project, preset/layout or executable name. |
| Vertical | Conventional Spanish term or accepted software loanword. |
| General | Conventional Spanish term or accepted software loanword. |
| Cloudflare WARP | Product, project, preset/layout or executable name. |
| Android | Product, project, preset/layout or executable name. |
| Internet | Conventional Spanish term or accepted software loanword. |
| EasyEffects | Product, project, preset/layout or executable name. |
| Google Lens | Product, project, preset/layout or executable name. |
| Auto, | Conventional Spanish term or accepted software loanword. |
| Normal | Conventional Spanish term or accepted software loanword. |
| %1 nits | Unit, numeric/format token, technical identifier or placeholder-only text. |
| %1s | Unit, numeric/format token, technical identifier or placeholder-only text. |
| %1s… | Unit, numeric/format token, technical identifier or placeholder-only text. |
| %1… | Unit, numeric/format token, technical identifier or placeholder-only text. |
| 0° | Unit, numeric/format token, technical identifier or placeholder-only text. |
| 50 % APL  ·  %1 nits | Unit, numeric/format token, technical identifier or placeholder-only text. |
| dd/MM | Unit, numeric/format token, technical identifier or placeholder-only text. |
| dd.MM | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Digital | Conventional Spanish term or accepted software loanword. |
| Emoji | Conventional Spanish term or accepted software loanword. |
| Error | Conventional Spanish term or accepted software loanword. |
| LCD HDR 1000 | Unit, numeric/format token, technical identifier or placeholder-only text. |
| LCD HDR 600 | Unit, numeric/format token, technical identifier or placeholder-only text. |
| MM/dd | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Mouse | Conventional Spanish term or accepted software loanword. |
| Natural | Conventional Spanish term or accepted software loanword. |
| OLED / QD-OLED | Product, project, preset/layout or executable name. |
| Temp: | Conventional Spanish term or accepted software loanword. |
| VRAM: | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Web | Conventional Spanish term or accepted software loanword. |
| Widgets | Conventional Spanish term or accepted software loanword. |
| DaVinci Resolve | Product, project, preset/layout or executable name. |
| DaVinci Resolve Studio | Product, project, preset/layout or executable name. |
| Celsius | Conventional Spanish term or accepted software loanword. |
| Fahrenheit | Conventional Spanish term or accepted software loanword. |
| Horizontal | Conventional Spanish term or accepted software loanword. |
| Local | Conventional Spanish term or accepted software loanword. |
| Master | Product, project, preset/layout or executable name. |
| Monocle | Product, project, preset/layout or executable name. |
| OBS Studio | Product, project, preset/layout or executable name. |
| %1 (%2) | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Cursor | Conventional Spanish term or accepted software loanword. |
|  min | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Color | Conventional Spanish term or accepted software loanword. |
| Discord | Product, project, preset/layout or executable name. |
| min | Unit, numeric/format token, technical identifier or placeholder-only text. |
| GitHub Sponsors | Product, project, preset/layout or executable name. |
| Ko-fi | Product, project, preset/layout or executable name. |
| Patreon | Product, project, preset/layout or executable name. |
| CRT | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Zoom | Conventional Spanish term or accepted software loanword. |
| pctrade — Widgets | Product, project, preset/layout or executable name. |
| updatems | Product, project, preset/layout or executable name. |
| updatems-system | Product, project, preset/layout or executable name. |
| macrecovery | Product, project, preset/layout or executable name. |
| AUR (yay/paru): | Product, project, preset/layout or executable name. |
| Flatpak: | Product, project, preset/layout or executable name. |
| Snap: | Product, project, preset/layout or executable name. |
| <none> | Technical sentinel, preserved literally. |
| Videos | Conventional Spanish term or accepted software loanword. |
| GIMP | Product, project, preset/layout or executable name. |
| Krita | Product, project, preset/layout or executable name. |
| LibreOffice | Product, project, preset/layout or executable name. |
| OnlyOffice | Product, project, preset/layout or executable name. |
| Sunshine | Product, project, preset/layout or executable name. |
| Moonlight | Product, project, preset/layout or executable name. |
| Blender | Product, project, preset/layout or executable name. |
| 15 fps | Unit, numeric/format token, technical identifier or placeholder-only text. |
| 30 fps | Unit, numeric/format token, technical identifier or placeholder-only text. |
| WiVRn | Product, project, preset/layout or executable name. |
| Antigravity: | Product, project, preset/layout or executable name. |
| Extra | Conventional Spanish term or accepted software loanword. |
| Ollama | Product, project, preset/layout or executable name. |
| UltraCode | Product, project, preset/layout or executable name. |
| GIF | Conventional Spanish term or accepted software loanword. |
| Video | Conventional Spanish term or accepted software loanword. |
| Instagram Reel | Product, project, preset/layout or executable name. |
| %1 B | Unit, numeric/format token, technical identifier or placeholder-only text. |
| %1 KB | Unit, numeric/format token, technical identifier or placeholder-only text. |
| %1 MB | Unit, numeric/format token, technical identifier or placeholder-only text. |
| %1 GB | Unit, numeric/format token, technical identifier or placeholder-only text. |
| LocalSend | Product, project, preset/layout or executable name. |
| RAM | Unit, numeric/format token, technical identifier or placeholder-only text. |
| CPU | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Ethernet | Product, project, preset/layout or executable name. |
| Wi-Fi | Product, project, preset/layout or executable name. |
| GIFs | Conventional Spanish term or accepted software loanword. |
| Dwindle | Product, project, preset/layout or executable name. |

## Shared keys and source observations

- `Key` is the keyboard key label in the keybind editor, translated Tecla; `Key input` in the screen translator is service-account credential input, translated Entrada de clave.
- `Plan` is the execution-mode action Planificar. Provider descriptions beginning `Plan |` refer to a subscription plan and retain Spanish Plan. Literal `plan` arguments are unchanged.
- `Light`, `Focus`, `Float`, `Pin`, `Share` and `Format` were checked against feature context. The standalone `Share` key is a network-share noun in disk-mounter.qml, translated Recurso compartido; sharing actions use their own keys.
- Recovery instructions preserve the literal boot-menu labels `Snapshots` and `linux`; ordinary snapshot references are Instantánea. The installed `/etc/limine-entry-tool.conf` names `Snapshots` in BOOT_ORDER. The boot-menu implementation is outside this translation change.
- The source has two copies of the long before/after-update advice, one containing literal `\u2014` text. Both values render the same natural Spanish advice; the English keys were left unchanged.
- Historical AI help still contains model-specific assumptions and `Current API endpoint...%2mode PROVIDER`. These statements and command tokens were preserved as supplied rather than correcting source behavior in a locale file.
- `%1 notifications`, task counts, characters and matches use count-neutral label forms because the lookup has no plural support.

## Follow-up from the German review

Four source-backed corrections were propagated across completed languages:

- The firewall warning refers to clearing the connection's zone assignment, not deleting a firewall zone.
- Streaming suppression hides island calls, messages and phone notifications; it does not disable receiving calls on the phone.
- The login-image size uses count-neutral px because the source permits a value of 1.
- The developer-extras timeout uses count-neutral min because the elapsed count may be 1.

All key and formatting checks still pass. The printf timeout message retains its argument order.

## Historical reasoning review

Historical review record. Current rules and display names are consolidated in
[TERMINOLOGY.md](../../TERMINOLOGY.md); the English-preservation decisions in this
old report are superseded where the current guide specifies localized labels.

This is the focused follow-up requested after Ukrainian completion. It applies
the owner’s updated terminology, HANDOFF.md, and corrected es_MX example from
`/home/itsjustdroid/Downloads/updated-reasoning`. It supplements the initial
glossary and completion notes; the decisions below supersede older decisions
on these terms. Good existing values outside concrete findings are preserved.

Changes: **65 of 3,221 values**. Source English keys and order are
unchanged. **119 values remain English-identical**; new ones introduced
by this review are explicitly listed below. Other identical entries retain the
individual audit from the original completion notes.

### Review and checks

- Root read the 101 related entries and all changes. Independent fresh-context review read the complete group-1 packet (371 records across four locales), including this locale’s 101 entries. Source context was checked for ambiguous controls.
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
| Island position | Posición de la isla |
| Island style | Estilo de la isla |
| Pills | Cápsulas |
| Hug | Extendido |
| Notch | Notch |
| Earbang protection | Protección contra picos de volumen |
| Unmuted | Sonido activado |
| Home | Carpeta personal |
| Swap | Memoria de intercambio |
| Tray | Bandeja |
| System tray | Bandeja del sistema |
| Blur | Desenfoque |

All seven named palette presets stay in English: Fruit Salad, Neutral, Tonal Spot, Expressive, Rainbow, Fidelity, Monochrome.
Hyprland scratchpad, submap, fake fullscreen and pseudo-tiling stay literal.
Capitalization such as Material Cookie remains where it is already recognizable
English and correct for the locale; no case-only rewrites were made.

The owner’s 62-value example is included. Four source-based follow-up changes
were made relative to that example: battery-threshold at, memory Swap, and the
two visible effort-label lists. One revises the example’s Swap change, yielding
65 differences from the previous committed catalog. The supplied file has 119
actual English-identical values, despite the offline note reporting 105.

### Exact value changes

| Exact English key | Previous committed value | Reviewed value | Reason |
| --- | --- | --- | --- |
| Material cookie | Galleta Material | Material cookie | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Style: Blurred | Estilo: Difuminado | Estilo: Desenfocado | Use the chosen blur term consistently for blur and frosted surfaces. |
| at | a las | al | The actual caller is a battery-percentage threshold (PowerConfig.qml:434), not a clock time or physical location. |
| Fruit Salad | Ensalada de frutas | Fruit Salad | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Dotfiles | Archivos de configuración | Dotfiles | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Pills | Píldoras | Cápsulas | Use the capsule-shaped UI-container term consistently, without medication wording. |
| Neutral | Neutro | Neutral | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Tonal Spot | Tono puntual | Tonal Spot | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Expressive | Expresivo | Expressive | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Hug | Abrazo | Extendido | Name the edge-spanning style; the earlier wording meant an embrace or attachment to an edge. |
| Superpaste | Superpegar | Superpaste | Preserve the Superpaste command/feature name. |
| Rainbow | Arcoíris | Rainbow | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Fidelity | Fidelidad | Fidelity | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Earbang protection | Protección contra destellos de audio | Protección contra picos de volumen | Name sudden volume-jump protection concisely; this is neither visual flashing nor headphone hardware protection. |
| Monochrome | Monocromático | Monochrome | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Unmuted | Sin silencio | Sonido activado | Use a natural sound-enabled state instead of an awkward negation. |
| A theme is a snapshot of your current look — wallpaper, colors, UI changes, and window decorations. Tap "Save current as theme" to capture what's on screen, then switch between saved themes any time with one tap. Use "Update" on the active theme to overwrite it with your latest tweaks. | Un tema es una instantánea de tu apariencia actual: fondo de pantalla, colores, cambios de interfaz y decoraciones de ventanas. Pulsa "Guardar apariencia actual como tema" para capturar lo que se ve en pantalla; después podrás cambiar de tema guardado con un toque. Usa "Actualizar" en el tema activo para sobrescribirlo con tus últimos ajustes. | Un tema es una instantánea de tu apariencia actual: fondo de pantalla, colores, cambios de interfaz y decoraciones de ventanas. Toca "Guardar apariencia actual como tema" para capturar lo que se ve en pantalla; después podrás cambiar de tema guardado con un toque. Usa "Actualizar" en el tema activo para sobrescribirlo con tus últimos ajustes. | Owner-supplied Mexican-Spanish wording: touch uses toca, key actions use presiona, and mouse uses the local computing loanword. |
| Anti-flashbang | Anti-destello | Antidestello | Use the same visual-flash-protection term as the other levels of this control. |
| Cookie | Galleta | Cookie | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Swap | Intercambio | Memoria de intercambio | All three current resource-panel callers mean disk-backed memory, not a window exchange action. |
| Tap to connect | Pulsa para conectar | Toca para conectar | Owner-supplied Mexican-Spanish wording: touch uses toca, key actions use presiona, and mouse uses the local computing loanword. |
| Tap to disconnect | Pulsa para desconectar | Toca para desconectar | Owner-supplied Mexican-Spanish wording: touch uses toca, key actions use presiona, and mouse uses the local computing loanword. |
| Tap to pair | Pulsa para vincular | Toca para vincular | Owner-supplied Mexican-Spanish wording: touch uses toca, key actions use presiona, and mouse uses the local computing loanword. |
| Ignores the touchpad for a moment after each key press, so a resting palm can't move the pointer | Ignora el panel táctil un momento después de cada pulsación para que la palma apoyada no mueva el puntero | Ignora el panel táctil un momento después de cada tecla presionada para que la palma apoyada no mueva el puntero | Owner-supplied Mexican-Spanish wording: touch uses toca, key actions use presiona, and mouse uses the local computing loanword. |
| Use symbols for mouse | Usar símbolos para el ratón | Usar símbolos para el mouse | Owner-supplied Mexican-Spanish wording: touch uses toca, key actions use presiona, and mouse uses the local computing loanword. |
| Enter submap | Entrar al submapa | Entrar al submap | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Grab a file and hover the workspace pill in the bar — it lights up and the dots fan out into arrows showing the scroll direction. Slide right to advance workspaces, left to go back, and drop the file into any app on the new workspace without ever opening the overview. | Toma un archivo y pasa el cursor sobre la píldora del espacio de trabajo en la barra: se ilumina y los puntos se despliegan como flechas que indican la dirección de desplazamiento. Desliza a la derecha para avanzar o a la izquierda para retroceder y suelta el archivo en cualquier aplicación del nuevo espacio sin abrir la vista general. | Toma un archivo y pasa el cursor sobre la cápsula del espacio de trabajo en la barra: se ilumina y los puntos se despliegan como flechas que indican la dirección de desplazamiento. Desliza a la derecha para avanzar o a la izquierda para retroceder y suelta el archivo en cualquier aplicación del nuevo espacio sin abrir la vista general. | Use the capsule-shaped UI-container term consistently, without medication wording. |
| Key event passes through to windows | La pulsación de la tecla también llega a las ventanas | La tecla presionada también llega a las ventanas | Owner-supplied Mexican-Spanish wording: touch uses toca, key actions use presiona, and mouse uses the local computing loanword. |
| Repeats while held (volume, resize) | Se repite al mantener pulsado (volumen, tamaño) | Se repite al mantener presionado (volumen, tamaño) | Owner-supplied Mexican-Spanish wording: touch uses toca, key actions use presiona, and mouse uses the local computing loanword. |
| Skip dotfiles | Omitir archivos de configuración | Omitir dotfiles | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Skip the Mainstream dotfiles refresh step (updatems). Dotfiles update only when a new release tag is published upstream; turn this on to manage them manually. | Omite la actualización de los archivos de configuración de Mainstream (updatems). Estos archivos solo se actualizan cuando se publica una nueva etiqueta de versión en el proyecto original; activa esta opción para administrarlos manualmente. | Omite la actualización de los dotfiles de Mainstream (updatems). Los dotfiles solo se actualizan cuando se publica una nueva etiqueta de versión en el proyecto original; activa esta opción para administrarlos manualmente. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Special (scratchpad) | Especial (ventanas apartadas) | Especial (scratchpad) | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle fake fullscreen | Alternar pantalla completa simulada | Alternar fake fullscreen | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle pseudo-tiling | Alternar pseudomosaico | Alternar pseudo-tiling | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle scratchpad | Alternar espacio de ventanas apartadas | Alternar scratchpad | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| end-4 — Dotfiles | end-4: Archivos de configuración | end-4: Dotfiles | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| A theme is a snapshot of your current look — wallpaper, colors, UI changes, and window decorations. Tap "Save current as theme" to capture what's on screen, then switch between saved themes any time with one tap. Use "Update" on the active theme to overwrite it with your latest tweaks. You can also export a theme to a file and import it again later or on another computer. The wallpaper is included. | Un tema es una instantánea de tu apariencia actual: fondo de pantalla, colores, cambios de interfaz y decoraciones de ventanas. Pulsa "Guardar apariencia actual como tema" para capturar lo que se ve en pantalla; después podrás cambiar de tema guardado con un toque. Usa "Actualizar" en el tema activo para sobrescribirlo con tus últimos ajustes. También puedes exportar un tema a un archivo e importarlo después o en otra computadora. Se incluye el fondo de pantalla. | Un tema es una instantánea de tu apariencia actual: fondo de pantalla, colores, cambios de interfaz y decoraciones de ventanas. Toca "Guardar apariencia actual como tema" para capturar lo que se ve en pantalla; después podrás cambiar de tema guardado con un toque. Usa "Actualizar" en el tema activo para sobrescribirlo con tus últimos ajustes. También puedes exportar un tema a un archivo e importarlo después o en otra computadora. Se incluye el fondo de pantalla. | Owner-supplied Mexican-Spanish wording: touch uses toca, key actions use presiona, and mouse uses the local computing loanword. |
| Drag widgets to reorder them or move them between the left, center, and right sections. Drop one against another to group them into a pill. Tap a widget to hide it. | Arrastra los widgets para reordenarlos o moverlos entre las secciones izquierda, central y derecha. Suelta uno sobre otro para agruparlos en una píldora. Pulsa un widget para ocultarlo. | Arrastra los widgets para reordenarlos o moverlos entre las secciones izquierda, central y derecha. Suelta uno sobre otro para agruparlos en una cápsula. Toca un widget para ocultarlo. | Use the capsule-shaped UI-container term consistently, without medication wording. |
| Drag widgets to reorder them or move them between the top, middle, and bottom sections. Drop one against another to group them into a pill. Tap a widget to hide it. | Arrastra los widgets para reordenarlos o moverlos entre las secciones superior, central e inferior. Suelta uno sobre otro para agruparlos en una píldora. Pulsa un widget para ocultarlo. | Arrastra los widgets para reordenarlos o moverlos entre las secciones superior, central e inferior. Suelta uno sobre otro para agruparlos en una cápsula. Toca un widget para ocultarlo. | Use the capsule-shaped UI-container term consistently, without medication wording. |
| Window title (pill) | Título de ventana (píldora) | Título de ventana (cápsula) | Use the capsule-shaped UI-container term consistently, without medication wording. |
| Widget pills | Píldoras de widgets | Cápsulas de widgets | Use the capsule-shaped UI-container term consistently, without medication wording. |
| Notch | Muesca | Notch | Preserve Notch as the named drawn style, not a physical hardware-cutout noun. |
| Toggle the scratchpad workspace | Alternar el espacio de ventanas apartadas | Alternar el espacio de trabajo scratchpad | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Exit the keybind submap | Salir del submapa de atajos | Salir del submap de atajos | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Dotfiles: deferred — the system package update failed, and dotfile releases can depend on packages it would have installed. Re-run the update once the package step succeeds. | Archivos de configuración: aplazados; falló la actualización de paquetes del sistema y las versiones de configuración pueden depender de los paquetes que se habrían instalado. Vuelve a actualizar cuando el paso de paquetes termine correctamente. | Dotfiles: aplazados; falló la actualización de paquetes del sistema y las versiones de los dotfiles pueden depender de los paquetes que se habrían instalado. Vuelve a actualizar cuando el paso de paquetes termine correctamente. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Mainstream dotfiles — updatems | Archivos de configuración de Mainstream: updatems | Dotfiles de Mainstream: updatems | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles: skipped (per --skip-dotfiles) | Archivos de configuración: omitidos (según --skip-dotfiles) | Dotfiles: omitidos (según --skip-dotfiles) | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| No dotfiles clone at %s — bootstrapping from %s | No hay copia de los archivos de configuración en %s; creando una desde %s | No hay copia de los dotfiles en %s; creando una desde %s | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Cloned dotfiles to %s | Archivos de configuración clonados en %s | Dotfiles clonados en %s | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles (updatems): | Archivos de configuración (updatems): | Dotfiles (updatems): | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| The dotfiles clone at %s is damaged. Setting it aside as %s and cloning again. | La copia de los archivos de configuración en %s está dañada. Se apartará en %s y se clonará de nuevo. | La copia de los dotfiles en %s está dañada. Se apartará en %s y se clonará de nuevo. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Update finished, but the Mainstream dotfiles did not update. See the Dotfiles line in the summary above. | La actualización terminó, pero no se actualizaron los archivos de configuración de Mainstream. Consulta la línea Archivos de configuración en el resumen de arriba. | La actualización terminó, pero no se actualizaron los dotfiles de Mainstream. Consulta la línea Dotfiles en el resumen de arriba. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| [DRY-RUN] The dotfiles clone at %s is damaged; would set it aside as %s and clone again. | [DRY-RUN] La copia de los archivos de configuración en %s está dañada; se apartaría en %s y se clonaría de nuevo. | [DRY-RUN] La copia de los dotfiles en %s está dañada; se apartaría en %s y se clonaría de nuevo. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Refreshing /etc/skel from the dotfiles... | Actualizando /etc/skel desde los archivos de configuración... | Actualizando /etc/skel desde los dotfiles... | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles: waiting for the desktop update that matches the new Qt. | Archivos de configuración: esperando la actualización del escritorio compatible con la nueva versión de Qt. | Dotfiles: esperando la actualización del escritorio compatible con la nueva versión de Qt. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Workspace title (pill) | Título del espacio de trabajo (píldora) | Título del espacio de trabajo (cápsula) | Use the capsule-shaped UI-container term consistently, without medication wording. |
| Dotfiles: waiting for the system packages, which were held back. | Archivos de configuración: esperando los paquetes del sistema que se retuvieron. | Dotfiles: esperando los paquetes del sistema que se retuvieron. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Signed in. The plan models are in the picker now: type /model to choose between Gemini 3.8 Flash (High, Medium, Low) and Gemini 3.1 Pro (High, Low). | Sesión iniciada. Los modelos del plan ya están en el selector: escribe /model para elegir entre Gemini 3.8 Flash (High, Medium, Low) y Gemini 3.1 Pro (High, Low). | Sesión iniciada. Los modelos del plan ya están en el selector: escribe /model para elegir entre Gemini 3.8 Flash (alto, medio, bajo) y Gemini 3.1 Pro (alto, bajo). | The parenthesized names are visible effort levels, not literal command arguments. |
| Signed in. Gemini Flash and Gemini Pro are in the picker now. Adjust thinking level with the reasoning pill or /think. | Sesión iniciada. Gemini Flash y Gemini Pro ya están en el selector. Ajusta el nivel de razonamiento con la píldora o /think. | Sesión iniciada. Gemini Flash y Gemini Pro ya están en el selector. Ajusta el nivel de razonamiento con la cápsula o /think. | Use the capsule-shaped UI-container term consistently, without medication wording. |
| Thinking Level: %1<br>Click to cycle (minimal → low → medium → high → auto) | Nivel de razonamiento: %1<br>Haz clic para cambiar (minimal → low → medium → high → auto) | Nivel de razonamiento: %1<br>Haz clic para cambiar (mínimo → bajo → medio → alto → auto) | Translate visible click-cycle effort labels; accepted typed command arguments elsewhere remain literal. |
| Home | Inicio | Carpeta personal | Name the personal filesystem folder, rather than a start page or generic main folder. |
| Tap Lap while running to save splits | Pulsa Vuelta durante la ejecución para guardar tiempos parciales | Toca Vuelta durante la ejecución para guardar tiempos parciales | Owner-supplied Mexican-Spanish wording: touch uses toca, key actions use presiona, and mouse uses the local computing loanword. |
| Dynamic Island | Isla dinámica | Dynamic Island | Preserve the named Dynamic Island feature. |
| Use Dynamic Island as your App Drawer | Usar la Isla dinámica como cajón de aplicaciones | Usar la Dynamic Island como cajón de aplicaciones | Preserve the full named Dynamic Island feature in its app-drawer setting. |
| 1. Install the free KDE Connect app on your phone. On Android, get it from the Google Play Store or F-Droid. On iPhone, get it from the App Store.<br>2. Connect the phone to the same Wi-Fi network as this computer.<br>3. Open KDE Connect on the phone, tap this computer in its list, then tap the button to pair with it. Pairing connects the two over Wi-Fi. It does not use Bluetooth or a cable.<br>4. A request then appears at the top of this tab. Check that its code matches the one on your phone, then click Accept. | 1. Instala la aplicación gratuita KDE Connect en tu teléfono. En Android, consíguela en Google Play Store o F-Droid. En iPhone, consíguela en App Store.<br>2. Conecta el teléfono a la misma red Wi-Fi que esta computadora.<br>3. Abre KDE Connect en el teléfono, pulsa esta computadora en su lista y luego el botón para vincularla. La vinculación conecta ambos equipos por Wi-Fi. No usa Bluetooth ni cable.<br>4. Aparecerá una solicitud en la parte superior de esta pestaña. Comprueba que el código coincida con el de tu teléfono y haz clic en Aceptar. | 1. Instala la aplicación gratuita KDE Connect en tu teléfono. En Android, consíguela en Google Play Store o F-Droid. En iPhone, consíguela en App Store.<br>2. Conecta el teléfono a la misma red Wi-Fi que esta computadora.<br>3. Abre KDE Connect en el teléfono, toca esta computadora en su lista y luego el botón para vincularla. La vinculación conecta ambos equipos por Wi-Fi. No usa Bluetooth ni cable.<br>4. Aparecerá una solicitud en la parte superior de esta pestaña. Comprueba que el código coincida con el de tu teléfono y haz clic en Aceptar. | Owner-supplied Mexican-Spanish wording: touch uses toca, key actions use presiona, and mouse uses the local computing loanword. |

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
- "Dotfiles (updatems):"
- "Dynamic Island"

### Source-confirmed exceptions and remaining limits

- Standalone Swap means memory in Resources.qml, ResourcesPanel.qml and ResourcesPopup.qml. Window-action keys use exchange verbs separately. The offline Spanish interpretation did not have source access.
- at in the automatic-suspend row is a battery percentage. Up %1 is uptime. Home in KeybindCaptureItem.qml is an untranslated X11 keysym and does not share the translated personal-folder call.
- Cookie/Material cookie are shape names; Expressive font is a normal descriptive font role and stays translated. No source strings, commands, accepted arguments, runtime names or configuration keys were changed.
- Longer accurate compounds still need eventual visual fit checks. No explanatory label expansions or new manual wrapping line breaks were added.

## Consolidated display-name pass, 2026-10-31

The current policy and approved terms are consolidated in [TERMINOLOGY.md](../../TERMINOLOGY.md). Earlier English-preservation rules and allowlists above are historical. The current pass changes 12 display values, preserving English keys, command syntax, identifiers and all formatting. These are self-reviewed working choices, not native-speaker-verified.

- "Material cookie" → "Galleta Material"
- "Fruit Salad" → "Ensalada de frutas"
- "Neutral" → "Neutro"
- "Tonal Spot" → "Acento tonal"
- "Expressive" → "Expresivo"
- "Rainbow" → "Arcoíris"
- "Fidelity" → "Fidelidad"
- "Cookie clock settings" → "Configuración del reloj Galleta"
- "Monochrome" → "Monocromático"
- "Use old sine wave cookie implementation" → "Usar la implementación antigua de Galleta con onda sinusoidal"
- "Cookie" → "Galleta"
- "Notch" → "Muesca"

Current intentionally English-identical count: 110. Names, units, literal formats and natural shared vocabulary remain valid; the lower count is not the purpose of this pass.
