# Brazilian Portuguese completion notes

Catalog: `pt_BR.json`. Source: all 3,221 keys of `en_US.json`, based on mainstream `c60e771ab`.

Completed 1,995 previously English-identical values. Corrected 35 existing translations for concrete defects; the other 1,081 existing translations are preserved. There are 110 intentional English-identical values, listed individually below. Keys and their order remain unchanged.

## Validation and review

- Each batch passed structural validation before it was written. Existing command-example errors were tracked and corrected at the start of the translation pass.
- Full catalog passes `python3 tools/catalog-qa.py pt_BR`: keys, JSON duplication, placeholders, printf order, line breaks, joining whitespace, markup and Markdown, protected names, numeric values, URLs, paths, command flags and config filenames.
- Ten regression tests cover checker failures, valid reordered arguments, localized decimal/grouping punctuation, URL punctuation and CJK-adjacent names.
- All 47 printf-format messages were exercised through the actual `sdata/lib/tr.sh` translator with distinct arguments. Key order matches English.
- A separate fresh-context review covered 1,271 unique English/Portuguese pairs: a deterministic 200-key sample (ascending SHA-256 of English keys), all 322 placeholder-bearing keys, and broad warning, destructive-action, permission, recovery and restriction coverage. Concrete findings were corrected.
- A terminology scan covered workspaces, sidebars, dock, Night Light, launcher, snapshots, keyring, app drawer, wallpaper, pinning and windows. Existing theme descriptions use retrato for the appearance metaphor; recovery uses instantâneo.
- No native-speaker review or live desktop language preview has been performed. These are translations with automated checks and independent review.

## Existing translations corrected

| English key | Reason |
| --- | --- |
| Change any time later with /dark, /light, /wallpaper in the launcher<br>If the shell's colors aren't changing:<br>    1. Open the right sidebar with Super+N<br>    2. Click "Reload Hyprland & Quickshell" in the top-right corner | Translate the remaining launcher loanword to the chosen UI term Lançador. |
| Depends on workspace | Localize the remaining workspace term and preserve the window reference. |
| Workspaces shown | Localize the remaining workspace term and preserve the window reference. |
| No API key<br>Set it with /key YOUR_API_KEY | Restore literal command metavariables or syntax that had been translated; restore the omitted model-selection condition where applicable. |
| %1 notifications | Use count-neutral phrasing that also works for 1. |
| Usage: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt><br>Supply <tt>i</tt> when you want images<br>Examples:<br><tt>%1superpaste 4i</tt> for the last 4 images<br><tt>%1superpaste 7</tt> for the last 7 entries | Restore literal command metavariables or syntax that had been translated; restore the omitted model-selection condition where applicable. |
| Online \| %1's 1T parameter flagship. Strong at coding, agentic workflows, and structured tool use. Disadvantages: higher initial latency and tends to be verbose | Correct the spelling of Desvantagens. |
| This is usually safe and needed for your browser and AI sidebar anyway<br>Mostly useful for those who use lock on startup instead of a display manager that does it (GDM, SDDM, etc.) | Restore the omitted reference to the AI sidebar. |
| Uses Gemini to categorize the wallpaper then picks a preset based on it.<br>You'll need to set Gemini API key on the left sidebar first.<br>Images are downscaled for performance, but just to be safe,<br>do not select wallpapers with sensitive information. | Use the complete Barra lateral esquerda navigation term. |
| Pick wallpaper image on your system | Restore the omitted wallpaper qualifier. |
| API key is set<br>Change with /key YOUR_API_KEY | Restore literal command metavariables or syntax that had been translated; restore the omitted model-selection condition where applicable. |
| Usage: %1tool TOOL_NAME | Restore literal command metavariables or syntax that had been translated; restore the omitted model-selection condition where applicable. |
| Hug | Describe the edge-hugging style rather than rounded corners. |
| Temperature must be between 0 and 2 | Correct the Portuguese grammar for a numeric interval. |
| ☕ Break: %1 minutes | Use a count-neutral minute abbreviation; preserve the existing Foco label. |
| Current tool: %1<br>Set it with %2tool TOOL | Restore literal command metavariables or syntax that had been translated; restore the omitted model-selection condition where applicable. |
| Current model: %1<br>Set it with %2model MODEL | Restore literal command metavariables or syntax that had been translated; restore the omitted model-selection condition where applicable. |
| Cookie clock settings | Use Biscoito consistently with the style name. |
| %1   •   %2 tasks | Use count-neutral phrasing that also works for 1. |
| Temperature<br>Change with /temp VALUE | Restore literal command metavariables or syntax that had been translated; restore the omitted model-selection condition where applicable. |
| 🌿 Long break: %1 minutes | Use a count-neutral minute abbreviation; preserve the existing Foco label. |
| Current API endpoint: %1<br>Set it with %2mode PROVIDER | Restore literal command metavariables or syntax that had been translated; restore the omitted model-selection condition where applicable. |
| 🔴 Focus: %1 minutes | Use a count-neutral minute abbreviation; preserve the existing Foco label. |
| %1 characters | Use count-neutral phrasing that also works for 1. |
| Usage: %1save CHAT_NAME | Restore literal command metavariables or syntax that had been translated; restore the omitted model-selection condition where applicable. |
| Usage: %1load CHAT_NAME | Restore literal command metavariables or syntax that had been translated; restore the omitted model-selection condition where applicable. |
| Language not listed or incomplete translations?<br>You can choose to generate translations for it with Gemini.<br>1. Open the left sidebar with Super+A, set model to Gemini (if it isn't already)<br>2. Type /key, hit Enter and follow the instructions<br>3. Type /key YOUR_API_KEY<br>4. Type the locale of your language below and press Generate | Restore literal command metavariables or syntax that had been translated; restore the omitted model-selection condition where applicable. |
| Example use case: eroge on one workspace, dark Discord window on another | Localize the remaining workspace term and preserve the window reference. |
| Use old sine wave cookie implementation | Use Biscoito consistently with the style name. |
| **Pricing**: free tier and pay-as-you-go.<br><br>**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project, go to Get API key | Do not introduce advance payment; source only says payment by usage. |
| Signed in. Gemini Flash and Gemini Pro are in the picker now. Adjust thinking level with the reasoning pill or /think. | Use the glossary capsule term and identify the reasoning control. |
| Thinking Level: %1<br>Click to choose reasoning depth | Restore the accent in Nível. |
| All files in ~ (%1 matches) | Use count-neutral phrasing that also works for 1. |
| Commands: /model <name> · /mode [ask\|auto\|plan] | Restore literal command metavariables or syntax that had been translated; restore the omitted model-selection condition where applicable. |
| Only local models are allowed right now. To use online models, set AI to Yes in Settings > Interface > Left Sidebar. | Translate the embedded Left Sidebar settings breadcrumb. |

## Intentional English-identical values

These are product/preset/executable names, units and formats, or conventional Portuguese words and software loanwords. None is an untranslated prose message.

| Exact value | Reason |
| --- | --- |
| Interface | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Volume | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| 12h am/pm | Unit, numeric/format token, technical identifier or placeholder-only text. |
| OK | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| illogical-impulse | Product, project, preset/layout or executable name. |
| 12h AM/PM | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Anime | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Dock | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| GitHub | Product, project, preset/layout or executable name. |
| Terminal | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Cloudflare WARP (1.1.1.1) | Unit, numeric/format token, technical identifier or placeholder-only text. |
| 24h | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Total: | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Emojis | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Distro | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Bluetooth | Product, project, preset/layout or executable name. |
| Pomodoro | Product, project, preset/layout or executable name. |
| Vertical | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Cloudflare WARP | Product, project, preset/layout or executable name. |
| Android | Product, project, preset/layout or executable name. |
| Internet | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| EasyEffects | Product, project, preset/layout or executable name. |
| Google Lens | Product, project, preset/layout or executable name. |
| Normal | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| %1 nits | Unit, numeric/format token, technical identifier or placeholder-only text. |
| %1s | Unit, numeric/format token, technical identifier or placeholder-only text. |
| %1s… | Unit, numeric/format token, technical identifier or placeholder-only text. |
| %1… | Unit, numeric/format token, technical identifier or placeholder-only text. |
| 0° | Unit, numeric/format token, technical identifier or placeholder-only text. |
| 50 % APL  ·  %1 nits | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Apps | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| dd/MM | Unit, numeric/format token, technical identifier or placeholder-only text. |
| dd.MM | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Digital | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Emoji | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Freq: | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| LCD HDR 1000 | Unit, numeric/format token, technical identifier or placeholder-only text. |
| LCD HDR 600 | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Layout | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Layouts | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| MM/dd | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Mouse | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Natural | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| OLED / QD-OLED | Product, project, preset/layout or executable name. |
| Temp: | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Touchpad | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| VRAM: | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Web | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Widgets | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| DaVinci Resolve | Product, project, preset/layout or executable name. |
| DaVinci Resolve Studio | Product, project, preset/layout or executable name. |
| Desktop + Big Picture | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Celsius | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Fahrenheit | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Horizontal | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Local | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Master | Product, project, preset/layout or executable name. |
| Monocle | Product, project, preset/layout or executable name. |
| OBS Studio | Product, project, preset/layout or executable name. |
| %1 (%2) | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Cursor | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
|  min | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Discord | Product, project, preset/layout or executable name. |
| min | Unit, numeric/format token, technical identifier or placeholder-only text. |
| GitHub Sponsors | Product, project, preset/layout or executable name. |
| Ko-fi | Product, project, preset/layout or executable name. |
| Patreon | Product, project, preset/layout or executable name. |
| CRT | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Zoom | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Pixel | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| pctrade — Widgets | Product, project, preset/layout or executable name. |
| ok | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| updatems | Product, project, preset/layout or executable name. |
| updatems-system | Product, project, preset/layout or executable name. |
| macrecovery | Product, project, preset/layout or executable name. |
| AUR (yay/paru): | Product, project, preset/layout or executable name. |
| Flatpak: | Product, project, preset/layout or executable name. |
| Snap: | Product, project, preset/layout or executable name. |
| <none> | Technical sentinel, preserved literally. |
| GIMP | Product, project, preset/layout or executable name. |
| Krita | Product, project, preset/layout or executable name. |
| LibreOffice | Product, project, preset/layout or executable name. |
| OnlyOffice | Product, project, preset/layout or executable name. |
| Sunshine | Product, project, preset/layout or executable name. |
| Moonlight | Product, project, preset/layout or executable name. |
| Blender | Product, project, preset/layout or executable name. |
| 15 fps | Unit, numeric/format token, technical identifier or placeholder-only text. |
| 30 fps | Unit, numeric/format token, technical identifier or placeholder-only text. |
| Tour | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Download: | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Upload: | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| WiVRn | Product, project, preset/layout or executable name. |
| Antigravity: | Product, project, preset/layout or executable name. |
| Downloads | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Extra | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Ollama | Product, project, preset/layout or executable name. |
| UltraCode | Product, project, preset/layout or executable name. |
| GIF | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
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
| GIFs | Conventional Portuguese term or accepted software loanword (product names also preserved where present). |
| Dwindle | Product, project, preset/layout or executable name. |

## Shared keys and source observations

- Workspace uses Área de trabalho, including existing partially English workspace labels. Desktop can mean the environment or the physical surface; Desktop is also an accepted loanword in the gaming-session choices. The containing feature distinguishes them.
- Preserve the existing valid execution-mode option Plano and its descriptions. Provider subscription plans also use Plano; literal command argument plan is unchanged.
- Preserve the existing short Pomodoro label Foco. New duration fields and notifications match it; window focus also uses Foco where appropriate.
- Pill uses Cápsula; Cookie style uses Biscoito. Names in executable commands and configuration paths remain unchanged.
- Key is Tecla in the keybind editor; Key input is credential entry in the screen translator.
- Theme explanations use the existing retrato metaphor for snapshot, while recovery uses instantâneo. These refer to different objects.
- Recovery instructions retain literal boot-menu labels Snapshots and linux. The installed boot-menu configuration names Snapshots in BOOT_ORDER; the boot implementation is outside this change.
- Source copies of the before/after-update advice include one with literal \u2014 text. Both translations express the same advice naturally; neither English key was changed.
- Historical AI help includes model-specific assumptions and Current API endpoint...%2mode PROVIDER. The stated behavior and command tokens were preserved; source fixes are outside this catalog change.
- Plural text in the overflowing multi-line file preview is preserved where source conditions require multiple lines; counts that can equal 1 use neutral labels instead.

## Follow-up from the German review

Four source-backed corrections were propagated across completed languages:

- The firewall warning refers to clearing the connection's zone assignment, not deleting a firewall zone.
- Streaming suppression hides island calls, messages and phone notifications; it does not disable receiving calls on the phone.
- The login-image size uses count-neutral px because the source permits a value of 1.
- The developer-extras timeout uses count-neutral min because the elapsed count may be 1.

All key and formatting checks still pass. The printf timeout message retains its argument order.

## Follow-up source clarification

- `Open on all apps when off` controls `overview.showAllAppsWhenOff`: show the complete app list when workspace overview is disabled, rather than applying to every application window. Clarified the label after checking InterfaceConfig.qml:612–632 and Overview.qml:110; a separate focused review confirmed the value.

## Historical reasoning review

Historical review record. Current rules and display names are consolidated in
[TERMINOLOGY.md](../../TERMINOLOGY.md); the English-preservation decisions in this
old report are superseded where the current guide specifies localized labels.

This is the focused follow-up requested after Ukrainian completion. It applies
the owner’s updated terminology, HANDOFF.md, and corrected es_MX example from
`/home/itsjustdroid/Downloads/updated-reasoning`. It supplements the initial
glossary and completion notes; the decisions below supersede older decisions
on these terms. Good existing values outside concrete findings are preserved.

Changes: **46 of 3,221 values**. Source English keys and order are
unchanged. **124 values remain English-identical**; new ones introduced
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
| Material cookie | Material cookie |
| Cookie | Cookie |
| Dotfiles | Dotfiles |
| Superpaste | Superpaste |
| Dynamic Island | Dynamic Island |
| Island position | Posição da ilha |
| Island style | Estilo da ilha |
| Pills | Cápsulas |
| Hug | Expandido |
| Notch | Notch |
| Earbang protection | Proteção contra picos |
| Unmuted | Com som |
| Home | Pasta pessoal |
| Swap | Memória de troca |
| Tray | Bandeja |
| System tray | Bandeja do sistema |
| Blur | Desfoque |

All seven named palette presets stay in English: Fruit Salad, Neutral, Tonal Spot, Expressive, Rainbow, Fidelity, Monochrome.
Hyprland scratchpad, submap, fake fullscreen and pseudo-tiling stay literal.
Capitalization such as Material Cookie remains where it is already recognizable
English and correct for the locale; no case-only rewrites were made.

### Exact value changes

| Exact English key | Previous committed value | Reviewed value | Reason |
| --- | --- | --- | --- |
| Material cookie | Biscoito Material | Material cookie | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Enable blur | Ativar desfoque (blur) | Ativar desfoque | Use the single chosen blur term without an unnecessary English gloss. |
| Fruit Salad | Salada de frutas | Fruit Salad | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Dotfiles | Arquivos de configuração | Dotfiles | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Neutral | Neutro | Neutral | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Tonal Spot | Ponto tonal | Tonal Spot | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Expressive | Expressivo | Expressive | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Hug | Rente | Expandido | Name the edge-spanning style; the earlier wording meant an embrace or attachment to an edge. |
| Superpaste | Supercolar | Superpaste | Preserve the Superpaste command/feature name. |
| Rainbow | Arco-íris | Rainbow | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Fidelity | Fidelidade | Fidelity | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Earbang protection | Proteção auditiva | Proteção contra picos | Name sudden volume-jump protection concisely; this is neither visual flashing nor headphone hardware protection. |
| Cookie clock settings | Configurações do relógio Biscoito | Configurações do relógio Cookie | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Monochrome | Monocromático | Monochrome | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Tray | Bandeja (Tray) | Bandeja | Keep the short tray label concise without a parenthetical English duplicate. |
| Use old sine wave cookie implementation | Usar implementação antiga de onda senoidal Biscoito | Usar implementação antiga de onda senoidal Cookie | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Anti-flashbang | Proteção de brilho | Antiflash | Use the same visual-flash-protection term as the other levels of this control. |
| Cookie | Biscoito | Cookie | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Swap | Trocar | Memória de troca | All three current resource-panel callers mean disk-backed memory, not a window exchange action. |
| Enter submap | Entrar no submapa | Entrar no submap | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Skip dotfiles | Ignorar arquivos de configuração | Ignorar dotfiles | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Skip the Mainstream dotfiles refresh step (updatems). Dotfiles update only when a new release tag is published upstream; turn this on to manage them manually. | Ignora a atualização dos arquivos de configuração do Mainstream (updatems). Esses arquivos só são atualizados quando uma nova versão é publicada pelo projeto original; ative esta opção para gerenciá-los manualmente. | Ignora a atualização dos dotfiles do Mainstream (updatems). Os dotfiles só são atualizados quando uma nova versão é publicada pelo projeto original; ative esta opção para gerenciá-los manualmente. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Special (scratchpad) | Especial (janelas reservadas) | Especial (scratchpad) | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle fake fullscreen | Alternar tela cheia simulada | Alternar fake fullscreen | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle pseudo-tiling | Alternar pseudoladrilhamento | Alternar pseudo-tiling | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle scratchpad | Alternar área de janelas reservadas | Alternar scratchpad | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| end-4 — Dotfiles | end-4: Arquivos de configuração | end-4: Dotfiles | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Notch | Recorte | Notch | Preserve Notch as the named drawn style, not a physical hardware-cutout noun. |
| Exit the keybind submap | Sair do submapa de atalhos | Sair do submap de atalhos | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Dotfiles: deferred — the system package update failed, and dotfile releases can depend on packages it would have installed. Re-run the update once the package step succeeds. | Arquivos de configuração: adiados; a atualização dos pacotes do sistema falhou, e as versões dos arquivos podem depender dos pacotes que seriam instalados. Atualize novamente quando a etapa de pacotes terminar com sucesso. | Dotfiles: adiados; a atualização dos pacotes do sistema falhou, e as versões dos dotfiles podem depender dos pacotes que seriam instalados. Atualize novamente quando a etapa de pacotes terminar com sucesso. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Mainstream dotfiles — updatems | Arquivos de configuração do Mainstream: updatems | Dotfiles do Mainstream: updatems | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles: skipped (per --skip-dotfiles) | Arquivos de configuração: ignorados (por --skip-dotfiles) | Dotfiles: ignorados (por --skip-dotfiles) | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| No dotfiles clone at %s — bootstrapping from %s | Nenhum clone dos arquivos de configuração em %s; preparando a partir de %s | Nenhum clone dos dotfiles em %s; preparando a partir de %s | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Cloned dotfiles to %s | Arquivos de configuração clonados em %s | Dotfiles clonados em %s | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles (updatems): | Arquivos de configuração (updatems): | Dotfiles (updatems): | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| The dotfiles clone at %s is damaged. Setting it aside as %s and cloning again. | O clone dos arquivos de configuração em %s está danificado. Separando-o em %s e clonando novamente. | O clone dos dotfiles em %s está danificado. Separando-o em %s e clonando novamente. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Update finished, but the Mainstream dotfiles did not update. See the Dotfiles line in the summary above. | A atualização terminou, mas os arquivos de configuração do Mainstream não foram atualizados. Veja a linha Arquivos de configuração no resumo acima. | A atualização terminou, mas os dotfiles do Mainstream não foram atualizados. Veja a linha Dotfiles no resumo acima. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| [DRY-RUN] The dotfiles clone at %s is damaged; would set it aside as %s and clone again. | [DRY-RUN] O clone dos arquivos de configuração em %s está danificado; seria separado em %s e clonado novamente. | [DRY-RUN] O clone dos dotfiles em %s está danificado; seria separado em %s e clonado novamente. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Refreshing /etc/skel from the dotfiles... | Atualizando /etc/skel a partir dos arquivos de configuração... | Atualizando /etc/skel a partir dos dotfiles... | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles: waiting for the desktop update that matches the new Qt. | Arquivos de configuração: aguardando a atualização do desktop compatível com o novo Qt. | Dotfiles: aguardando a atualização do desktop compatível com o novo Qt. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles: waiting for the system packages, which were held back. | Arquivos de configuração: aguardando os pacotes do sistema que foram retidos. | Dotfiles: aguardando os pacotes do sistema que foram retidos. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Signed in. The plan models are in the picker now: type /model to choose between Gemini 3.8 Flash (High, Medium, Low) and Gemini 3.1 Pro (High, Low). | Conectado. Os modelos do plano estão no seletor agora: digite /model para escolher entre Gemini 3.8 Flash (High, Medium, Low) e Gemini 3.1 Pro (High, Low). | Conectado. Os modelos do plano estão no seletor agora: digite /model para escolher entre Gemini 3.8 Flash (alto, médio, baixo) e Gemini 3.1 Pro (alto, baixo). | The parenthesized names are visible effort levels, not literal command arguments. |
| Thinking Level: %1<br>Click to cycle (minimal → low → medium → high → auto) | Nível de pensamento: %1<br>Clique para alternar (minimal → low → medium → high → auto) | Nível de pensamento: %1<br>Clique para alternar (mínimo → baixo → médio → alto → automático) | Translate visible click-cycle effort labels; accepted typed command arguments elsewhere remain literal. |
| Home | Início | Pasta pessoal | Name the personal filesystem folder, rather than a start page or generic main folder. |
| Dynamic Island | Ilha dinâmica | Dynamic Island | Preserve the named Dynamic Island feature. |
| Use Dynamic Island as your App Drawer | Usar a Ilha dinâmica como gaveta de aplicativos | Usar a Dynamic Island como gaveta de aplicativos | Preserve the full named Dynamic Island feature in its app-drawer setting. |

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

- "Material cookie" → "Biscoito Material"
- "Fruit Salad" → "Salada de frutas"
- "Neutral" → "Neutro"
- "Tonal Spot" → "Destaque tonal"
- "Expressive" → "Expressivo"
- "Rainbow" → "Arco-íris"
- "Fidelity" → "Fidelidade"
- "Cookie clock settings" → "Configurações do relógio Biscoito"
- "Monochrome" → "Monocromático"
- "Use old sine wave cookie implementation" → "Usar a implementação antiga de Biscoito com onda senoidal"
- "Cookie" → "Biscoito"
- "Notch" → "Recorte"

Current intentionally English-identical count: 115. Names, units, literal formats and natural shared vocabulary remain valid; the lower count is not the purpose of this pass.
