# Mainstream OS translation reasoning and terminology

This is the **single current source of translation guidance**, consolidated on
2026-10-31 from the original glossary, the updated terminology and handoff, and
the owner's approved UI-localization decisions. It supersedes earlier reasoning.
Historical per-locale reviews are preserved in each corresponding
`tools/glossary/<locale>-notes.md` file; they are records, not additional rules
to apply alongside this file.

The source is `en_US.json`; the 2026-10-31 translation pass covers 3,256 keys
and 19 non-English locales. Counts can change: re-scan the actual UI, Files
extension and updater scripts at the end of each pass.
This document and the catalogs are self-reviewed, not native-speaker-verified.

Use this glossary when translating or reviewing the locale catalogs. It defines
the English meaning of the project's terms; it does not claim that any target
language has been reviewed. It covers the desktop, settings, phone integration,
AI sidebar, file sharing, and update messages in `en_US.json`.

Some terms below occur inside longer strings rather than as standalone keys.
The exact keys in `en_US.json` remain authoritative.

## How to use it

1. Choose a target locale, including its regional spelling and conventions.
2. Give the translator this document, the strings for one feature, and relevant
   source context. Short labels alone often leave the meaning unclear.
3. Agree on a target-language equivalent for the recurring terms in that batch.
   Reuse it across buttons, headings, tooltips, and instructions, with grammatical
   inflection where needed. Save those decisions for subsequent batches by recording them in the Current display-name
   decisions section at the end of this file.
4. Preserve existing good translations. An English-identical value is a candidate
   for translation, including the intentional English placeholders, but product
   names may have established localized forms; executable syntax and identifiers
   must remain exact. Apply the decision process below instead of treating every
   name as protected English display text.
5. Have reviewers identify concrete meaning, terminology, grammar, or UI-fit
   problems. A different wording alone is not a reason to replace a translation.

Use familiar desktop vocabulary and concise action labels. Translate explanatory
text naturally while preserving the scope, conditions, and consequences of the
English. Keep instructions about saving, deleting, permissions, and recovery
explicit. A short label should not become a paragraph to explain a feature.

The Meaning column explains each term in plain English; it is not label wording.
Do not copy phrases from it into a translation (for example, “putting windows
aside” is not the name of a scratchpad).

## Localize display names; preserve executable text

For UI labels, headings, descriptions and tooltips:

1. Prefer an established localized name or spelling. Use official local product
   wording when it exists and suits the feature. Local convention may retain
   Latin characters: that alone is neither an untranslated error nor poor UX.
2. Otherwise choose a concise, natural translation of a descriptive feature or
   shape name, or a conventional transliteration when its identity is better
   conveyed that way. Decide per locale, not by applying a Latin-to-native-script
   converter. Native-script languages are not all handled alike.
3. Keep a recognizable English brand when that is the normal local spelling.
   Do not coin a long phonetic name solely to eliminate Latin text. For example,
   Material remains recognizable as a design-system name in Chinese display
   labels while the descriptive cookie shape is 饼干 / 餅乾.
4. Apply the chosen word throughout the feature: short and full labels, compound
   names, settings titles, tooltips and help. Inflect it naturally. Preserve the
   English source's specificity; a short Island compound need not repeat a long
   full feature name. Chinese uses its compact established island names.
5. Leave JSON keys, stored values, commands, paths, URLs, shortcuts, API names,
   package/executable names, model IDs, versions and typed argument values exact.
   The label `Neutral` can be localized; `scheme-neutral` cannot. The clock label
   `Cookie` can be localized; its stored `cookie` value cannot.
6. Familiar abbreviations such as API, CPU, GPU, RAM, JSON and Wi-Fi can remain
   Latin. Retain actual commands such as `/think`, `superpaste`, `updatems` and
   `--skip-dotfiles` even where the surrounding sentence is translated.

### Applying this to the current display labels

- **Material cookie / Cookie:** these name a rounded, scalloped visual shape.
  They are not browser storage and do not form an untouchable API identifier.
  A familiar food/shape metaphor is valid. Korean uses 머티리얼 쿠키 / 쿠키,
  Japanese マテリアルクッキー / クッキー and Hindi मटीरियल कुकी / कुकी.
  German Keks and Spanish Galleta are appropriate descriptive shape names.
- **Palette presets:** localize the whole set consistently as UI labels,
  including Tonal Spot, Neutral, Expressive, Fidelity, Monochrome, Fruit Salad
  and Rainbow. Use a clear color/design sense: Fidelity concerns faithfulness
  to the source colors. Avoid literal mistranslations such as a punctual tone.
  Stored scheme identifiers remain unchanged. French Monochrome and German
  Neutral happen to match English; that is valid local vocabulary.
- **Notch:** use a familiar local style name, such as Korean 노치, French Encoche
  or Turkish Çentik. The surrounding style description explains the drawn shape;
  using the local notch term does not promise a hardware cutout. German retains
  the familiar Notch loan. Do not alter the stored `hug` compatibility value.
- **Dynamic Island:** use the established full name for each locale. Simplified
  Chinese uses 灵动岛 and Traditional Chinese (Taiwan) uses 動態島. Other current
  catalogs retain Dynamic Island where that is an established recognizable name;
  their short Island compounds already use local words or transliterations.
- **Hyprland layout/dispatcher vocabulary and project names:** Dwindle, Master,
  Monocle, scratchpad, submap, fake fullscreen, pseudo-tiling, Dotfiles and
  Superpaste remain recognizable here. Keep the exact spelling when showing a
  command/configuration identifier. An English upstream keyword alone is not a
  blanket reason to forbid a suitable localized *display label* in future.

### Evidence and scope

The following sources establish the examples, not a universal rule for every
language or brand:

- [Google's Korean Material article](https://developers-kr.googleblog.com/2021/01/mad-skills-material-design-components-wrap-up.html)
  uses 머티리얼 디자인. Its [Korean Compose documentation](https://developer.android.com/develop/ui/compose/designsystems/material3?hl=ko)
  also retains Material Design in Latin characters. Both conventions exist.
- [Google's shape definitions](https://developer.android.com/reference/kotlin/androidx/compose/material3/MaterialShapes)
  describe Cookie4Sided and related visual shapes; those code names stay exact.
- [Apple Taiwan](https://support.apple.com/zh-tw/guide/iphone/iph28f50d10d/ios)
  uses 動態島. [Apple Korea](https://support.apple.com/ko-kr/guide/iphone/iph28f50d10d/ios)
  retains Dynamic Island, as does [Apple's Hindi guide](https://support.apple.com/hi-in/guide/iphone/iph28f50d10d/ios).

Project-specific label choices below are approved working decisions, not claims
that every translation is an official vendor term or has native-speaker review.

## Length and UI fit

These are UI strings, so shorter is better. Where two wordings are both accurate,
choose the shorter one.

- Keep a label close to the length of its English source. A label that is much
  longer than the English is a candidate for shortening; if it cannot be
  shortened, flag it for a check in the running UI.
- Options that sit side by side (button groups, tabs, dropdowns) get one short word
  each, in the same grammatical form.
- Do not repeat context that the control's heading or page already supplies.
- Put nuance in descriptions and tooltips, not in the label.
- Prefer a shorter established term over a longer self-explanatory phrase.
- When a shorter choice would collide with another term, choose a different short
  word rather than a longer phrase.
- Mirror the English's level of specificity. If the source uses a short form
  (“Island position”, “Tray”), use the short form; if it uses the full term
  (“System tray”), use the full term. Do not add words the English does not have.
- The exception is a shorter word that is the wrong sense in that control. Then use
  the longer accurate one (Spanish “Carpeta personal” for Home, because “Inicio”
  reads as “start”).

Examples (es_MX):

- Hug is an option beside Float, Notch, and Rect. “De borde a borde” is accurate but
  three words in a one-word button group, so es_MX uses “Extendido”. “Pegado” was
  avoided because Notch's description already uses “pegado al borde”.
- Island position: “Posición de la isla”, not “Posición de la Dynamic Island”. The
  English says only “Island”.
- Tray: “Bandeja”, not “Bandeja del sistema”. The page already says system tray, and
  the separate “System tray” label keeps the long form.

## Desktop surfaces and navigation

| English term or label | Meaning and translation guidance |
| --- | --- |
| Desktop | The graphical working environment, or the area behind windows. Use the conventional computer term. |
| Shell | The desktop interface built with Quickshell: bar, dock, sidebars, launchers, and related surfaces. In “shell command,” it instead means a command interpreter. |
| Bar / Desktop bar | The configurable status and control strip. Keep its name distinct from the dock and a window's title bar. |
| Traditional bar | The normal widget-based desktop bar, contrasted with Dynamic Island. “Traditional” describes this interface option. |
| Dynamic Island | The named compact status surface that expands into panels. Use the established localized name where available, including 灵动岛 (zh_CN) and 動態島 (zh_TW); retain recognizable English where local convention does. See the display-name decisions below. It is not a physical display cutout. |
| Island position / Island style | Placement and visual shape of Dynamic Island. Mirror the English: where the source says only “Island” (Island panels, Island position, Island style), use the locale's short word for island (Spanish: “isla”) instead of repeating the full name. The full name stays for the feature title and for sentences that use it. |
| Island panels | The pages of content within the expanded island, such as messages, weather, and system controls. |
| Panel | A contained UI surface or content page. It does not necessarily mean the whole desktop bar. |
| Dock | The strip of application shortcuts and running-app controls. Use the established desktop term, not a hardware docking station. |
| Launcher / App launcher | The interface used to search for and open applications, with workspace previews when enabled. |
| App drawer / Application drawer | The application grid inside the launcher, or the island's app-search function. Choose one equivalent for “app drawer” throughout. |
| App / Apps / Application / Applications | Installed software. These are short and long forms of the same concept; avoid changing the underlying noun between nearby controls. |
| Overview / Launcher Overview | The desktop/workspace preview interface. It is not an introductory summary of documentation. |
| Scroll Overview / Scrolling Overview | The scrolling workspace overview. When naming the external plugin itself, preserve `hyprland-scroll-overview`. |
| Alt+Tab / Window switcher | The window-selection interface opened with Alt+Tab. Preserve the shortcut notation. |
| Workspace | A virtual desktop containing windows. It is not a directory, project workspace, or physical office. |
| Current / Active workspace | The workspace currently selected on the relevant monitor. |
| Named workspaces / Workspace title | Workspaces with a user-defined display name. Translate the label, never the name supplied by the user. |
| Workspace title (pill) | A workspace-name widget with a capsule-shaped background. “Pill” describes the UI shape. |
| Window title (pill) | The focused window's title in a capsule-shaped widget. Keep this distinct from the workspace title. |
| Visible workspaces / Workspaces shown | The configured number of workspace previews or indicators shown. It is not a maximum number of workspaces the system can contain. |
| New workspace / Empty workspace | A newly added virtual desktop / one containing no app windows. Empty does not mean unavailable or broken. |
| Special workspace / Special (scratchpad) | Hyprland's separately toggled workspace used for temporarily putting windows aside. Keep “scratchpad” in English; it is the name used in Hyprland and i3/Sway documentation. Do not turn the explanation “putting windows aside” into the label. “Special workspace” may use the locale's ordinary word for “special”. |
| Minimized apps | Windows put aside by minimization. This concept is distinct from recently used apps, even when older source or discussion uses this label. |
| Recently used apps / Recently Used | Applications used recently. This is activity history, not a list of minimized windows. |
| Workspace navigation | Switching between workspaces or navigating the window columns within a workspace; read the containing control's explanation. |
| Column / Columns | In the scrolling layout, a vertical group of windows in a horizontal sequence. In an app drawer, a column of app tiles. |
| Row / Rows | A horizontal group of workspace previews or app tiles. Keep distinct from a window column. |
| Sidebar / Sidebars | The panels at the sides of the desktop. Keep one common noun in “Left Sidebar,” “Right Sidebar,” and sidebar actions. |
| Tab | A selectable page within a sidebar or picker. It is not the keyboard's Tab key unless named as a shortcut. |
| Detach / Reattach sidebar | Move a sidebar into a separate window / return it to its attached desktop position. |
| Expand / Collapse | Show more / less of a surface or group. Distinguish from maximizing or minimizing an app window. |
| Quick settings / Quick toggles | Frequently used controls, often switches. They are not keyboard shortcuts. |
| System tray / Tray | Small status icons registered by background apps. It is distinct from the dock's application list. Mirror the English: “Tray” alone gets a one-word label (Spanish: “Bandeja”), because the page already says system tray; “System tray” gets the full term (“Bandeja del sistema”). |
| Widget | An individual configurable UI component, such as clock, weather, or resources. |
| Widget layout / Group | Arrangement of widgets / widgets placed together. A window group is a separate concept. |
| Pill / Widget pills | Capsule-shaped UI container, not a medication. Use the locale's word for a capsule-shaped container (Spanish: “cápsula”), never its word for a medication pill. This applies to “Pills”, “Widget pills”, “(pill)” in widget titles, and running text such as “the reasoning pill”. |
| Hot corner | A screen corner that triggers an action when the pointer reaches or hovers over it. |
| Overlay | A surface drawn over other desktop content, such as a crosshair or floating image. |
| On-screen display | A brief status display, such as the volume or brightness indicator. Often abbreviated OSD in technical discussion. |
| Preview / Thumbnail | A visual representation of an app window, wallpaper, or other item before selecting it. |
| Search | Find an app, file, setting, or other item. Preserve the object being searched when the string names it. |
| No results / No matching windows | The search found no matches. Do not imply that no apps are installed or that the workspace is empty. |

Source context: [launcher](../modules/ii/overview/),
[bar settings](../modules/settings/BarConfig.qml),
[interface settings](../modules/settings/InterfaceConfig.qml).

## Window layouts and actions

| English term or label | Meaning and translation guidance |
| --- | --- |
| Layout / Window Layout / Workspace Layouts | How app windows are arranged. A keyboard layout is a separate meaning. |
| Dwindle / Dwindle (default) | The named layout where new windows successively split available space. Retain the recognizable name unless the locale has an established equivalent; translate “default.” |
| Master | The named layout with a main window and a stack of other windows. Do not translate it as a person's rank or ownership. |
| Scrolling | The layout with horizontally scrollable window columns. Use the established descriptive term consistently. |
| Monocle | The named layout showing one focused window at a time. Retain the name unless there is an established desktop equivalent. |
| Float / Floating | Freely positioned windows outside automatic tiling. In bar/dock style controls, Float instead describes a surface visually separated from the screen edge. |
| Tiling / Pseudo-tiling | Automatic allocation of window space / the named Hyprland pseudo-tiling behavior. Keep this distinct from display mirroring or grouping apps in a folder. Keep “pseudo-tiling” (Hyprland's `pseudo` behavior) in English, or give the English name in parentheses, so users can find it in Hyprland documentation. |
| Focus / Focused window | The selected window that receives input. This is separate from the Pomodoro focus interval. |
| Unfocused / Inactive window | A window that is not currently focused. An inactive device or disabled setting has a different meaning. |
| Move focus | Select another window without moving the window itself. |
| Move window / Move to workspace | Change a window's position or workspace. This does not mean launching another instance of the app. |
| Move window silently / Without following it there | Move the window without switching the user's current view to its destination. “Silently” does not refer to audio. |
| Swap | The standalone Swap key is swap memory in the current resource panels. Keys such as Swap window and Swap with next are window-exchange actions. Translate each actual caller context correctly; never change the memory label into a window-action verb based on an offline example. |
| Resize | Change a window's dimensions. Keep distinct from interface scale and icon size. |
| Maximize / Maximized | Expand a window to the available workspace area. Keep distinct from fullscreen. |
| Fullscreen / Full screen | The full-screen window or media-viewing state. Localize both spellings consistently for the same concept. |
| Fullscreen (no gaps) | The fullscreen option without the normal layout gaps. Preserve the qualification. |
| Fake fullscreen | The named compatibility behavior for fullscreen state. It is distinct from ordinary fullscreen and maximize. Keep “fake fullscreen” in English, or give the English name in parentheses, for the same reason. |
| Minimize / Restore | Put a window aside / return it to its prior visible state. “Restore Snapshot” restores the system instead. |
| Close window / Close all windows | Close one or all windows of the selected app. This is not uninstalling the app. |
| Force kill window | Forcibly terminate a window/app that may not respond. Preserve the stronger consequence compared with ordinary Close. |
| Window Grouping / Move into group | Group app windows using Hyprland's window-group behavior. This is not an application folder or widget group. |
| Window rules | Saved matching conditions and effects controlling how particular windows open or behave. |
| Submap / Enter submap | Hyprland's named keybind mode: a separate set of binds that stays active until exited. Keep “submap” in English; it matches the Hyprland configuration keyword. |
| App class / Window title (regex) | Window matching identifiers / title pattern. Translate the surrounding label, not a user's pattern or app identifier. |
| Pin window / Pin above everything | Labels for the window pin action/effect. Preserve that this affects a window; it is not a favorite app or tray-icon visibility setting. |
| Keep aspect ratio | Preserve the ratio of width to height when resizing. |
| Allow tearing (games) | Permit screen tearing as a graphics behavior. Do not translate as physically damaging the display. |
| Screen sleep / Keeps screen awake | Whether the display may turn off while a window is in use. It does not automatically mean suspending the whole computer. |
| Title bar / Window buttons | The strip on an app window / its close, maximize, and minimize controls. |
| Decorations / Window decorations | Window appearance features such as borders, corners, shadows, and animations. |
| Pin to dock / Unpin from dock | Keep / remove a persistent app shortcut. Unpinning does not close or uninstall the app. |
| Pinned on startup | For the dock: start with it kept visible and reserving screen space. This does not mean starting every pinned app. |
| Pinned by default | For the left sidebar: reserve screen space for the open sidebar. This is distinct from detaching it into a window. |
| Make icons pinned by default | For the system tray: make icons belong to the normally visible set. It does not add app shortcuts to the dock. |
| Hide tray icons / Show hidden tray icons | Collapse / reveal tray icons. Their background apps continue running. |

Source context: [window rules](../modules/settings/windowrules/WindowRulesSection.qml),
[keybind dispatchers](../modules/settings/keybinds/Dispatchers.qml),
[dock settings](../modules/settings/DockConfig.qml),
[tray service](../services/TrayService.qml),
[left sidebar](../modules/ii/sidebarLeft/SidebarLeft.qml).

## Appearance, shapes, and visual effects

| English term or label | Meaning and translation guidance |
| --- | --- |
| Theme | A saved appearance configuration covering wallpaper, colors, fonts, and other styling. It is broader than wallpaper alone. |
| App style / System look | Visual styling of applications / the desktop. “Style” does not mean AI response style in these controls. |
| Wallpaper / Background | The desktop image or video / the surface behind content. A panel background may instead be a color or translucent material. |
| Live wallpaper | A moving/video wallpaper, not a live broadcast. |
| Slideshow / Shuffle | Automatic wallpaper rotation / choosing its order randomly. |
| Main wallpaper / This screen only | The wallpaper controlling the main color palette / a change limited to one display. Preserve that scope. |
| Palette / Recolor | The generated set of UI colors / update colors from a wallpaper. |
| Dark / Light / Dark Mode | Appearance modes. Light here means a light-colored theme, not lower font weight or less reasoning effort. |
| Accent / Tint / Tint app icons | Emphasis color / color treatment applied to a surface or icon. Avoid implying that the original icon is replaced. |
| Transparency | How much of what is behind a surface can be seen. Keep distinct from blur. |
| Opacity | How solid a surface is. Greater opacity means less transparency. Do not reverse slider meaning. |
| Blur / Frost / Frosted | The softened translucent-background effect. “Frost” is a visual metaphor for blur, not ice or temperature. Use one word for blur across all strings, including “Blurred”, “Blur amount”, and “Frosted …”; do not mix two terms. |
| Blur through to the wallpaper | Sample the desktop wallpaper rather than intervening windows for the blur. |
| Dim / Dim amount | Darken content, usually unfocused windows. This is distinct from blur and transparency. |
| Border / Border thickness | The visible outline around a surface / its width. |
| Strength | Depends on the containing control: border solidity, blur/effect strength, or a connection's signal. |
| Shadow / Drop shadow | The shaded area behind a window or surface, used to give depth. |
| Falloff | How an effect fades away toward its edge. |
| Noise / Grain | Fine visual texture used with blur. It is not audio noise. |
| Vibrancy / Saturation | Color retention or richness in a visual effect. Use the established image/color terms. |
| Corner roundness / Radius / Rounded Corners | Curvature at the corners of UI surfaces or windows. |
| Gap / Workspace gap | Empty spacing between windows or workspace previews; inspect the containing setting. |
| Padding / Screen-edge padding | Internal spacing / distance from a screen edge. Keep distinct from border thickness. |
| Offset X / Offset Y | Horizontal / vertical positional displacement. Preserve the axis letters. |
| Scale / Size / Icon size | Overall proportional scaling / dimensions / app or UI icon dimensions. Keep each control's scope. |
| Launcher icon size | Size of the app-drawer button's icon in the dock. It does not resize the whole launcher. |
| Launcher dot spacing | Spacing between the dots making up the app-drawer button. It does not change workspace indicators. |
| Float (style) | A bar, dock, or island visually separated from the screen edge. Keep distinct from the floating window layout. |
| Notch | The rendered shape attached to an edge with curved transitions at its ends. Use the familiar local notch term or loanword; its description concerns a UI style, not a hardware modification. |
| Hug | The edge-spanning bar/dock style. Use a short shape/style name conveying the edge-hugging behavior rather than a literal embrace. Do not use the locale's word for hugging. Use one short word (Spanish: “Extendido”). |
| Rect / Rectangle | Rectangular shape or selection. Use the locale's appropriate short label for Rect; do not alter the stored `rect` value. |
| Corner style options: Float / Notch / Hug / Rect | Side-by-side shape buttons for bar, dock and island settings. Use short, parallel style labels in the local language. The descriptions carry the detailed geometry. Keep stored identifiers such as float, hug, span and rect exact. |
| Split into three | Divide the traditional bar into three separate sections. It does not create three workspaces. |
| Material cookie / Cookie / Cookie clock | The rounded, scalloped clock shape/style from Material 3 Expressive. Use a natural local shape name or conventional transliteration. Preserve the design-system identity of Material without requiring Latin text in every locale. Keep the same term across the four Cookie strings; stored identifiers stay exact. |
| Tonal Spot / Neutral / Expressive / Fidelity / Monochrome / Fruit Salad / Rainbow | User-facing Material You palette variants. Translate or conventionally transliterate their display names as one consistent set; their scheme-* identifiers never change. Fidelity describes faithfulness to source colors. Expressive font is a separate font-role label and also uses natural local wording. |
| Magnify / Magnify amount | Enlarge icons on hover / the extent of that enlargement. |
| Glow | A halo around an icon, not a notification badge. |
| Bubble | The named dock hover animation. Keep its localized name distinct from a message bubble. |
| Bounce / Pop / Pulse / Wobble / Ripple | Named motion effects. Use concise labels consistent with the corresponding motion. |
| Crossfade / Slide / Zoom / Wipe | Wallpaper transition effects: blending, moving, scaling, or revealing the next image. |
| Dashes / Dots | Shapes of window indicators. They do not describe punctuation in text. |
| Minimal (window indicators) | One small running-window mark, regardless of window count. This is separate from Minimal animation or AI reasoning settings. |
| Count badge / Badge | A small numeric indicator. In dock settings it counts app windows, not unread notifications. |
| Minimal and badges / Dashes and badges / Dots and badges | Combine a running-window indicator with a count badge. Keep both parts of the label. |
| Icon separators | Dividers between groups of dock icons, not spacing between the launcher's dots. |
| Reset / Reset to default | Return the affected setting or section to its default. Preserve the stated scope; do not imply a whole-system reset. |

Source context: [style choices](../modules/settings/services/),
[decorations settings](../modules/settings/DecorationsConfig.qml),
[dock app indicators](../modules/ii/dock/DockAppButton.qml),
[themes](../modules/settings/ThemesConfig.qml).
The dock's user-facing Notch style is stored as `hug`, and Hug as `span` for
compatibility. Translate the displayed label, never the stored identifier.

## Input and common actions

| English term or label | Meaning and translation guidance |
| --- | --- |
| Keybind / Keyboard shortcut | A key or key combination mapped to an action. Use the locale's familiar shortcut terminology. |
| Modifier / Mods | Modifier keys such as Super, Ctrl, Alt, and Shift. “Mods” here is not game modifications. |
| Super | The modifier key usually carrying a Windows or command-style logo. Preserve `Super` in executable/keybinding examples. |
| Keycap | The visual representation of a keyboard key, not a keyboard layout. |
| Keyboard layout | The arrangement/mapping of keys for a language or typing system. |
| Input Sources / Input method | Keyboard and composition options / the system for composing characters, such as an IME. These are distinct from audio input devices. |
| Pointer / Cursor | Usually the mouse pointer in mouse settings; a text cursor in an input field. Preserve that distinction in descriptions. |
| Natural (scroll direction) | The scrolling-direction option where the gesture follows content movement. It is not an animation smoothness setting. |
| Primary Button | The mouse button assigned to the primary action. Do not automatically replace this with “left button.” |
| Gesture / Swipe / Pinch | Touchpad actions. Preserve finger counts and direction. |
| Hover / Hover to reveal | Move or leave the pointer over a target without clicking / expose a hidden surface that way. |
| Drag / Drop / Drop target | Pick up an item and move it / release it / the receiving area. Preserve which item goes to which destination. |
| Toggle | Switch an option between states. Do not imply that it only turns the option on. |
| Enable / Disable | Make a feature available / unavailable. Distinguish from connecting a device or opening a panel. |
| Show / Hide | Change visibility. Hiding an app control does not uninstall or stop the app. |
| Apply / Save | Activate the chosen configuration / store data or choices. Preserve any statement that Apply also saves or reloads immediately. |
| Cancel / Discard | Stop an action / abandon unsaved changes. Do not conflate either with deleting saved data. |
| Remove / Delete / Uninstall | Remove a list item or configuration / delete the named data / remove installed software. Read and preserve the stated consequences. |
| Clear | Clear the named field, list, history, or selection. Keep the object explicit where supplied. |
| Cut / Copy / Paste | Standard clipboard actions. Cutting text differs from deleting it. |
| Clipboard / Clipboard history | The copied-data buffer / a list of previous copied items. |
| Screen snip / Screenshot / Region | Capture screen content / a captured image / the selected part of a screen. |
| Recognize text | Extract text from an image or screen selection (OCR). It does not mean translating that text. |
| Identify Music / Recognize music | Identify a playing song. Keep distinct from voice input or recording audio. |
| Picker / Selector | A UI for choosing an item, such as an emoji, color, or file. Use the conventional target-language control name. |

## Audio, displays, resources, and power

| English term or label | Meaning and translation guidance |
| --- | --- |
| Audio input / Input device | Microphone or other capture source in audio controls. |
| Audio output / Output device | Speakers, headphones, or another playback destination in audio controls. |
| Volume mixer | Individual audio levels for devices or apps. |
| Mute / Unmute / Muted | Silence / restore audio / the resulting state. This does not disconnect the device. “Unmuted” is the restored state: use a phrase meaning sound on, not a negation of silence. |
| Media / Media player | Audio/video content / the app or control playing it. |
| Track / Album art / Lyrics | A song/item of audio / its cover image / the song's words. |
| Visualizer | A visual animation responding to audio, not a video player. |
| Resources / System resources / Resource usage | CPU, memory, and similar machine statistics. It is not help documentation or downloadable assets. |
| Load | Resource load in system statistics; the verb “load” elsewhere means opening saved content. |
| Memory / RAM / VRAM | System working memory / graphics memory. Keep distinct from disk storage and model context capacity. |
| Battery health / Battery drain | Battery condition/capacity retention / the rate at which it is being used. |
| Charging / Discharging / On battery | Receiving power into the battery / using stored charge / running from the battery. |
| Time to full / Time to empty | Estimated remaining charging time / remaining battery runtime. Preserve the direction. |
| Power Profile / Power Mode | A performance-versus-power preference, not a user account or color profile. |
| Performance / Balanced / Power Saver | Power-profile options. Balanced also appears in unrelated AI controls. |
| Keep awake / Keep system awake | Inhibit the stated idle sleep behavior. Preserve whether it affects the screen or the whole system. |
| Automatic Screen Blank / Darken screen | Turn off or blank the display / reduce its brightness. Neither necessarily suspends the computer. |
| Lock / Lock screen | Require authentication to resume access while keeping the session. A package database lock is a different meaning. |
| Logout / Sign out | End the desktop session, or sign out of the named online account. Preserve which one the string means. |
| Sleep / Suspend | The system's low-power sleep state. Use a consistent conventional term where the UI uses these as equivalents. |
| Hibernate | Save the running state to disk and power down. Keep distinct from suspend and ordinary shutdown. |
| Reboot / Restart | Start the computer again, or restart a specifically named component. Preserve the object. |
| Shut Down / Shutdown / Power off | Turn off the computer. Localize these forms consistently. |
| Reboot to firmware settings | Restart into the computer's firmware setup screen. It does not reset the firmware. |
| Display / Monitor | A connected physical screen in display settings. A UI “panel” can mean something different. |
| Default monitor / Duplicate screen | The selected default display / mirror the same output onto another display. |
| Resolution / Refresh rate / FPS | Pixel dimensions / display updates per second / frames per second. Do not interchange them. |
| Landscape / Portrait / Flipped | Display orientation. Flipped is the corresponding rotated orientation, not swapping monitors. |
| HDR / SDR | High/standard dynamic range. Preserve the identifiers; translate surrounding explanations. |
| Luminance / Brightness / nits | Measured light output / perceived or configured brightness / the luminance unit. Preserve numeric values and units. |
| Peak / Sustained Brightness | Brief maximum luminance / brightness the display can maintain for longer. |
| Paper White / Reference white | The SDR white reference level used within HDR output. It is not wallpaper color. |
| Black Floor / Shadow Detail | Minimum luminance / visibility of near-black tones. “Shadow” here is image detail, not a window's drop shadow. |
| Color Management / ICC Profile | Display color handling / an imported color profile. Keep distinct from a desktop theme or wallpaper palette. |
| EDID / VRR / ABL / APL / DDC | Display-related technical identifiers. Keep them intact and translate the explanatory wording. |
| Temperature | Weather or hardware temperature, display color warmth, or AI sampling randomness. Determine the meaning from the full string and control. |
| Night Light / Intensity | The screen-warming feature / the strength of that effect. It does not mean dark mode or monitor brightness. |
| Anti-flashbang / Anti-flash | Game-derived name for limiting sudden bright flashes on screen; Strong and Weak are its levels. Use one spelling in every label (Spanish: “Antidestello”). Check the setting's source before translating. |
| Earbang protection | Limits sudden volume increases (see Volume limit and Max allowed increase). It is about loudness, not visual flashes. |

## Phone, notifications, and communication

| English term or label | Meaning and translation guidance |
| --- | --- |
| Phone / Computer / Device | The paired phone / this PC / a device in the relevant connection context. Preserve who performs the action. |
| Pair / Paired / Forget | Establish a remembered device relationship / that relationship exists / remove it. Pairing does not guarantee a current connection. |
| Connected / Disconnected / Not connected | Whether the relevant connection is currently established. Keep distinct from pairing. |
| Reachable / Not reachable | Whether the phone service can currently communicate with the device. A paired or Bluetooth-connected phone can still be unreachable through another service. |
| Connect phone services | Enable the island's phone integration. It is not itself a promise that pairing or network connectivity has succeeded. |
| Phone notifications / Automatic alerts | Notices originating from the phone / automatically showing them in Dynamic Island. |
| Disable calls, messages, and phone notifications while streaming | Suppress their island presentation when the configured streaming condition applies. Do not imply that the phone stops receiving calls or messages. |
| Contact privacy / Private contact | Controls hiding personal contact details / a concealed contact label. It does not change the contact on the phone. |
| Show message contents / Message contents hidden | Reveal or conceal the body of a message in the UI. Keep distinct from deleting it. |
| Notification / Message | A system/app alert / a communication in a conversation. Do not treat them as interchangeable. |
| Dismiss notification | Remove the notification from view/history as the UI action specifies. It does not mean declining a call or deleting a text message. |
| Unread indicator / Unread count | A mark or count of items not yet read. A dock count badge counts windows instead. |
| Conversation / Thread | A sequence of messages exchanged with a person or group. “Thread” here is not a CPU thread. |
| Compose / New message / Reply | Start writing / begin a conversation message / respond to an existing message. |
| Draft / Not sent / Message not sent | Unsent composed content / unsuccessful sending state. Preserve any statement that the draft was kept. |
| Send / Receive / Sent | Transfer to the other device/person / accept incoming data / completed sending. Preserve direction and tense. |
| Attachment / Attach | A file or media item added to a message / add one. Attaching is not sending yet. |
| GIF / GIFs / Emojis and GIFs | Animated-image media / the combined picker. Keep the file-format identifier GIF intact. |
| Frequently used / Recently used | Usage-frequency order / recency order. They describe different lists. |
| Audio clip / Voice note | An audio attachment / a recorded spoken message. Reuse terms consistently in playback and recording controls. |
| Voice input | Speech used as input to the AI sidebar, not necessarily a phone voice note. |
| Media message / Photo message / Video | A message containing media / an image message / a video attachment. |
| Link preview | A card or thumbnail for a URL. This is distinct from the URL text and the attachment itself. |
| Open externally / Open in browser | Open content in another app / the web browser. It does not mean sending the content to another person. |
| Incoming / Outgoing / Missed call | A call received / placed / not answered. Preserve direction. |
| Dialing / Ringing / In call / On hold | Distinct call states. Do not collapse them into a generic connected state. |
| Answer / Accept / Decline / Call back | Take the incoming call / accept the named action / reject the call or action / place a return call. |
| Recent calls / Clear call history | The call log / remove its stored history. Preserve the difference between clearing history and ending a current call. |

Source context: [phone sidebar](../modules/ii/sidebarLeft/PhoneTab.qml),
[conversation view](../modules/ii/sidebarLeft/PhoneThreadView.qml),
[island state](../services/IslandState.qml),
[phone settings](../modules/settings/BarConfig.qml).

## Networking, files, drives, and sharing

| English term or label | Meaning and translation guidance |
| --- | --- |
| Network / Networking / Internet | A connection or local network / networking controls / access beyond the local network. Local connectivity does not guarantee internet access. |
| Wi-Fi / Ethernet / Bluetooth | Connection technologies. Preserve their recognizable technology names. |
| Saved network / Hidden Network / Forget Network | Remembered Wi-Fi configuration / one whose name is not advertised / remove a saved connection. |
| Discoverable / Pairable | Visible to nearby devices / willing to establish a pairing relationship. These are separate Bluetooth states. |
| Network portal | A captive-portal sign-in page, not the network settings app. |
| SSID / IP address / Host / Server | A Wi-Fi network name / numerical address / computer offering a service / service endpoint. Do not translate actual values. |
| Wi-Fi Country | The regulatory country used for wireless-channel rules. It is separate from interface language or keyboard layout. |
| Download / Upload | Transfer toward / away from this computer. Preserve direction in speed and progress labels. |
| Files / File Manager / File Explorer | A generic file-management role, or a named app in context. In “on Windows, in File Explorer,” use that product's recognized localized name. |
| Home / Home folder / Parent folder | The user's home directory / the containing directory one level above. Preserve literal filesystem paths in examples. Use the same term as the file manager's home folder; avoid a word that reads as “start” or “home page” (Spanish: “Carpeta personal”). |
| Folder / Directory | A filesystem container. In an app drawer, a folder instead groups application shortcuts. |
| Hidden files / Hidden folders | Files or folders normally omitted from listing, including dot-prefixed ones. Hidden does not mean encrypted. |
| Storage / Internal Storage / Root filesystem | Persistent file storage / the phone's internal storage / the filesystem rooted at `/`. Keep distinct from RAM. |
| Drive / Disk / Partition | Storage hardware / a storage disk / a subdivision of a disk. Avoid conflating a partition with the whole drive. |
| Mount / Mounted / Mount at | Make a filesystem or network share accessible / resulting state / its mount location. Use the established computing term. |
| Auto-mounted drives / Auto Drive Mount | Drives configured to become accessible automatically, including after login/startup as stated. |
| Unmount | Stop exposing a mounted filesystem. It does not erase or format the drive. |
| Format & Mount / Unformatted | Create a filesystem and mount it / no usable filesystem is set up. Formatting is a destructive storage operation. |
| Encrypted / Passphrase / Unlock & Mount | Protected by encryption / its unlocking secret / unlock and expose the filesystem. Keep distinct from the user's login password. |
| Read-only / View only | Access permitting reading without changes. View only is the user-facing network-share permission label. |
| Sharing / Share folders | Make selected local folders accessible to other computers on enabled networks. This is not uploading a public link. |
| Share / Send via LocalSend | Configure access to a resource / transfer a copy to another device. LocalSend transfer is distinct from persistent folder sharing. |
| Share name / Share path / Network address | The share's exported name / location / address other computers use. Actual identifiers must stay unchanged. |
| Shared Folders / Mounted shares | Local folders offered to other computers / remote shares accessible through this computer's filesystem. |
| Can make changes | Share permission allowing modifications. Preserve its stronger access compared with View only. |
| Stop sharing | Remove network access while keeping the local folder and its files. Preserve that distinction. |
| Sharing password | A password used by other computers to access shares. The UI explicitly distinguishes it from the login password. |
| Keyring / Safe Storage | Secure storage for secrets such as passwords or API keys. In package updates, “keyring” can instead mean trusted signing keys. |
| Firewall / Firewall zone | Network access controls / the group of rules applied to a connection. Preserve warnings about access on other networks. |
| Computer Name / Hostname | The name used to identify this PC on the network. Preserve restrictions on characters and length. |
| Bookmark | A saved shortcut to a folder/location. It does not copy the folder. |
| Ascending / Descending / Sort by | File-list ordering controls. Preserve whether the sort key is date, name, or another field. |

Source context: [Files extension](../../../../.local/share/nautilus-python/extensions/mainstream-share.py)
and the Sharing, drive-mount, and phone-file strings in `en_US.json`.

## AI sidebar

| English term or label | Meaning and translation guidance |
| --- | --- |
| AI Assistant / Model | The sidebar assistant / the selected language model. Preserve the actual model name and version. |
| Local AI / Online | Runs on this computer / uses a remote service. Preserve statements about whether data leaves the machine. |
| Provider / API endpoint / Base URL | The service supplying a model / its API address / base service address. Actual URLs remain unchanged. |
| API key / Service account key | Service credentials. Keep distinct from a keyboard key, a signing key, or a subscription sign-in. |
| Subscription / Plan (provider listing) | Account-based access to a provider's models. A `Plan` prefix in a provider description is not execution Plan mode. |
| Session / Saved Sessions | A saved AI conversation. In “Session (5h)” it instead refers to a provider usage window; in power controls it means the desktop login session. |
| Chat / Conversation / Chat history | The AI exchange and its saved messages. Phone conversations use the same broad concept with a different participant. |
| System prompt / Prompt | Instructions governing the assistant / input requesting a response. A system prompt is not a password prompt. |
| Context | Information available to a model for a request. It is not a right-click context menu. |
| Token / Token count | Units of model text processing and usage. Preserve numeric placeholders and input/output distinctions. |
| Temperature / Sampling | The randomness control for applicable AI models / choosing output tokens. This is unrelated to heat or display warmth. |
| Thinking / Reasoning / Reasoning Effort / Thinking Level | The model's reasoning activity or configured depth. Keep effort levels in a consistent progression. |
| Reasoning budget / Thinking budget | The amount of reasoning a model may spend before answering. It is a processing allowance, not money or a spending limit. |
| Minimal / Low / Medium / High / Max / Extra | Effort levels when used in reasoning controls. They have separate meanings in animation, warning, and window-indicator settings. Translate these UI labels; only the literal accepted values inside command examples (see Protected text) stay in English. |
| Response style / Precise / Balanced / Creative | The preferred response/sampling style. It is separate from desktop appearance and execution permissions. |
| Tool / Function call | A capability the model invokes, such as a command or search. A tool is not necessarily an app being installed. |
| Execution Mode | How the AI assistant handles commands, edits, and approvals. Preserve differences between Ask, Auto, and Plan. |
| Ask | Execution mode requesting permission before actions. This is not simply the instruction to ask a chat question. |
| Auto | Execution mode automatically allowing the described commands and edits. In other controls Auto means system-, model-, or schedule-chosen behavior. |
| Plan | Execution mode for planning without executing commands or edits. It is distinct from a paid subscription plan. |
| Approve / Approve & Run / Reject / Declined | Permit or reject the named action. Keep the scope and duration of any approval exactly as described. |
| Permission Required / Extra access | A requested permission or broader access. Do not soften it into an informational success message. |
| Stop generating | End the current AI response. It does not delete the conversation or uninstall a model. |
| Attach a file / Voice input | Supply a file or spoken input to the AI request. Keep distinct from sending files or voice notes through the phone. |
| Download / Pull a model | Retrieve a local AI model. Keep the executable subcommand `pull` unchanged in examples. |
| Usage / Rate limited / Remaining | Provider consumption, throttling, and allowance. Do not equate usage with the number of available models. |
| User / You / Earlier conversation | Participants and context in the chat. Preserve who said or approved something. |

Source context: [AI sidebar](../modules/ii/sidebarLeft/),
[AI modes](../modules/common/AiModes.qml),
[services settings](../modules/settings/ServicesConfig.qml).

## Tasks, time, and weather

| English term or label | Meaning and translation guidance |
| --- | --- |
| To Do / To do / Tasks | The user's task list. Localize these variants consistently. A system task/process in Task Manager is separate. |
| Task description / Complete task / Unfinished | A to-do item's text / mark it done / it is still pending. |
| Due date / Deadline | When a task is expected to be complete. Preserve all-day versus timed distinctions. |
| Calendar & tasks | The combined date and to-do panel. Use the same terms as their individual widgets. |
| Timer / Stopwatch | Counts down to a target / measures elapsed time. |
| Lap / Split | A recorded stopwatch interval / an intermediate timing comparison. It is not a map location or visual split-pane. |
| Pomodoro / Focus / Break / Long break | A named work/rest timer method and its intervals. Focus here means concentration time, not window input focus. |
| Cycle / Cycles before long break | A work/rest iteration / count determining when the longer rest occurs. |
| Pause / Resume / Reset | Temporarily stop timing or playback / continue / return the named timer/control to its initial state. |
| Target duration / Ends at / Remaining | Intended interval / calculated end time / time still to run. |
| Time Format / Date Format | How times/dates are displayed. Keep format-code examples separate from ordinary explanatory text. |
| World clock / Time zone | Clocks for selected cities / regional time rules. Do not change actual time-zone identifiers. |
| Feels like | Apparent temperature in weather. This is not the measured air temperature. |
| Precipitation / Humidity / Pressure / Wind | Distinct weather measurements. Retain the supplied units. |
| Sunrise / Sunset / UV Index | Solar-event times / ultraviolet exposure index. Night Light can follow the sunrise/sunset schedule. |
| Clear sky / Mostly clear / Partly cloudy / Overcast | Distinct forecast categories. Preserve the differences in cloud cover. |
| Fog / Drizzle / Rain / Freezing rain / Snow / Showers / Thunderstorms | Distinct weather conditions. Avoid collapsing all precipitation into rain. |
| Forecast unavailable / Updating weather | Missing forecast data / a refresh in progress. Preserve the distinction from a no-rain forecast. |

## Accounts, apps, installation, and recovery

| English term or label | Meaning and translation guidance |
| --- | --- |
| Login name / Username / User name | The identifier used to sign in. In account settings it is distinct from the display/full name. |
| Full name / Login image | The name/photo shown on the login screen. Updating them does not necessarily change the login identifier. |
| Administrator / Standard account / Guest | Different account roles. Preserve the scope of administration and account restrictions. |
| Authentication / Authorization | Proving identity / permission to perform an action. Keep failed, canceled, and not-authorized outcomes distinct. |
| Repair Account | Reapply the desktop/account setup for the selected user. It does not mean deleting that account. |
| Default Apps | Apps selected to open particular file types or actions. It is not the list installed by default. |
| Auto Start Apps / Launch on startup | Apps opened automatically after login/startup. Disabling startup does not uninstall an app. |
| App Store / Install / Uninstall Apps | Software browser / add software / remove installed software. Preserve named app products when used. |
| Native packages / Flatpak / Snap | Different software packaging/install mechanisms. Preserve Flatpak and Snap as technology names. |
| Package / Repository / Repo | An installable software unit / a software source. Keep distinct from an AI package of credits or a local project folder. |
| System packages / Developer extras | OS-managed packages / the additional developer-tool update pass. Preserve which steps are skipped. |
| AUR | Arch User Repository. Preserve the acronym and helper names `yay` and `paru`. |
| Update / Release updates / Edge updates | Install changes / follow published releases / follow newer unreleased work. Edge is an update channel here, not a browser or screen boundary. |
| Skip / Deferred / Held back | Intentionally omit a step / postpone it / prevent it until a stated condition is resolved. None means successfully updated. |
| Running / Stopped / Failed / Finished | Distinct process outcomes. A finished process can still have a failure exit code. |
| Dry run / `[DRY-RUN]` | Report what would happen without applying it. Preserve the literal marker in log strings. |
| Snapshot | A system restore point in recovery, a saved appearance state in theme explanations, or captured windows in session restore. Read the full sentence. |
| Restore Snapshot / Roll back / Recovery | Return system state to a saved snapshot / undo a system update's state / the recovery workflow. It is not restoring a minimized window. |
| Repair Install | Re-run the system's desktop/setup repair. Keep distinct from restoring a snapshot or reinstalling a single app. |
| Repair Package Keys / Signing key / Package keyring | Repair package trust / a key verifying software / the trusted set of such keys. This keyring differs from saved personal passwords. |
| Boot menu / Boot image / Kernel / Firmware | Startup menu / files used to boot / operating-system core / hardware-level software. Keep these objects distinct in recovery instructions. |
| EFI partition | The boot-related disk partition. Preserve the acronym and warnings about available space. |
| Read-only snapshot / Read-only filesystem | A snapshot intentionally opened without writes / a filesystem not accepting writes, possibly after an error. Preserve the stated cause. |
| Reboot required / Do not restart yet | Opposite instructions. Preserve conditions, urgency, and which action must happen first. |
| Dotfiles / System bits | The desktop configuration repository/update step versus system-level update components. Dotfiles remains a recognizable project label in this pass; all commands and flags stay exact. Do not mistake it for a file extension. Translate System bits naturally. A display label is not executable merely because it is next to a flag. |
| Local edits stashed | Existing local changes were saved aside using Git. Preserve the restore commands exactly. |
| Gaming Mode / Desktop Gaming | The console-style Steam session / gaming in the normal desktop. These are different setup choices. |
| Big Picture / Return to Desktop | Steam's named interface / its action to return to the desktop. Prefer recognized localized Steam UI wording where established. |
| Game Streaming / Stream this PC's games | Send interactive game output to another device. This is distinct from watching a video stream or suppressing phone alerts during streaming. |
| Game mode | Performance-related gaming behavior in context. Do not automatically equate every occurrence with the separate Gaming Mode session. |

## Protected text and formatting

These are translation constraints, not terms to turn into natural-language prose.

| Item | Required handling |
| --- | --- |
| JSON keys | Preserve every English key exactly, including capitalization, punctuation, whitespace, and literal escape text. Edit values only. Do not merge similarly worded keys. |
| JSON representation | Output valid UTF-8 JSON. Escape quotes, backslashes, and control characters correctly. A decoded newline and the literal characters `\n` are different data. |
| Qt placeholders `%1`, `%2`, `%3`, `%4` | Preserve each placeholder and its occurrence count. They may move to suit grammar; preserve which argument means which object, sender, number, or destination. |
| Shell placeholders `%s` | Preserve the count and argument order. The shell formatter supports `%s` here; do not introduce `%1`, `%1$s`, `%d`, or additional percent signs. Rephrase so the supplied arguments remain in order. |
| Numbers, measurements, and limits | Preserve actual values, signs, ranges, percentages, and units. Do not convert measurements or “correct” a model's documented limit while translating. |
| Code and command examples | Preserve executable commands, subcommands, flags, identifiers, and their quoting exactly. Translate the prose around them. |
| Slash commands | Preserve command tokens such as `/key`, `/model`, `/mode`, `/think`, `/temp`, `/tool`, `/save`, `/load`, `/ollama`, `/dark`, `/light`, and `/wallpaper`. |
| Accepted argument values | Keep literal values such as `ask`, `auto`, `plan`, `minimal`, `low`, `medium`, `high`, `precise`, `balanced`, and `creative` in command examples. Their ordinary UI labels may be translated. |
| Example metavariables | Keep every all-caps placeholder in command syntax unchanged, such as `YOUR_API_KEY`, `MODEL_NAME`, `CHAT_NAME`, `TOOL_NAME`, `NUM_OF_ENTRIES`, `MODEL`, `PROVIDER`, `VALUE`, and `TOOL`. |
| Paths and configuration keys | Preserve examples such as `~/.config/illogical-impulse/config.json`, `/etc/fstab`, `language.ui`, `sidebar.booru.zerochan.username`, and package filenames. Translate displayed folder names only when they are ordinary UI labels. |
| URLs and addresses | Preserve link destinations, hostnames, network addresses, email addresses, and paths embedded in them. Translate a Markdown link's human-readable text where appropriate. |
| Markup | Preserve HTML/Qt tags, attributes, font-family strings, nesting, and closing tags. Translate visible prose within tags. Preserve Markdown emphasis, links, code spans, fences, and code-language identifiers. |
| Keyboard shortcuts | Preserve actual combinations such as `Super+W`, `Ctrl+X`, and `Alt+Tab`. Use conventional localized key names only in explanatory prose, without changing the action's physical keys. |
| Glyphs and icons | Preserve functional Nerd Font glyphs, emoji, arrows, and symbols used in shortcut or status examples. Do not replace an icon with an invented word. |
| User-supplied content | Never translate names, workspace names, session names, message bodies, file paths, or app identifiers substituted at runtime. Translate only the surrounding UI text. |
| Leading/trailing spaces and fragments | Preserve necessary separators and joining whitespace. Inspect concatenated strings before translating fragments such as `You: ` or `of %1`. |
| Line breaks | Keep the same number of line breaks as the source. Do not add wrap breaks to fit a layout width; flag a width problem instead. |
| Counts and plural forms | Preserve separate singular/plural keys already present. The current lookup does not interpret ICU messages or add grammatical plural forms automatically; do not invent that syntax in values. Flag counts that require a source change, or use natural count-neutral wording where possible. |
| Date/time format examples | Preserve format tokens and their order in examples such as `dd/MM`, `MM/dd`, and `dd.MM`. Translate the surrounding explanation, without silently changing the option's date order. |
| Right-to-left locales | Keep embedded paths, commands, addresses, and identifiers readable without changing their contents. Check the rendered interface for direction and clipping; do not add direction-control characters to keys or executable examples. |
| `/*keep*/` | A suffix the loader recognizes and removes from final display. Preserve an existing marker at the end; do not add it to English placeholders to mark them as translated. |

The lookup and placeholder behavior is defined in
[Translation.qml](../services/Translation.qml) and `sdata/lib/tr.sh` at the
repository root. Both shipped and generated translations use the English text as
the key. A nonempty shipped English placeholder takes precedence over a generated
translation; its presence is not proof of completed localization.

### Recognizable names and exact identifiers

Keep these names recognizable. This is not a requirement that every UI occurrence
use English characters: approved localized display forms follow the decision
process above. Code, commands, paths and model identifiers remain exact. Examples:

- Mainstream OS, Mainstream, illogical-impulse, end-4, Hyprland, Quickshell,
  Hyprlock, Wayland, X11, Arch Linux, Calamares, Limine, Snapper, Plymouth, SDDM,
  GDM, Qt, GTK, Material You, Nerd Font, and named font families.
- KDE Connect, LocalSend, Bluetooth, Wi-Fi, Ethernet, Samba, SMB, SSH, SSHFS,
  MPRIS, CUPS, NetworkManager, firewalld, polkit, and GNOME Keyring.
- OpenAI, ChatGPT, Codex, Anthropic, Claude, Google, Gemini, Antigravity, Ollama,
  Mistral, OpenRouter, and exact model IDs, versions, and tier suffixes.
- Steam, SteamVR, Big Picture, Proton, gamescope, GameMode, WiVRn, Discord,
  OBS Studio, DaVinci Resolve, Flatpak, Flathub, Snap, GitHub, Ko-fi, and Patreon.
- Unsplash, Tenor, YouTube, Instagram, Google Lens, Cloudflare WARP,
  EasyEffects, LRCLIB, osu!, and named wallpaper/image sources.
- Commands and packages such as `pacman`, `yay`, `paru`, `topgrade`, `updatems`,
  `updatems-system`, `sshfs`, `brightnessctl`, `ffmpeg`, `songrec`, `agy`, and
  `mainstream-system`; identifiers such as `[mainstream]`, `Ext4`, `Btrfs`,
  `HDR`, `SDR`, `ICC`, `EDID`, `VRR`, `CPU`, `GPU`, `RAM`, `VRAM`, and `API`.
- Hyprland and Material You vocabulary: Dwindle, Master, Monocle, scratchpad,
  submap, fake fullscreen, pseudo-tiling, Material 3 Expressive, Material Symbols,
  Material Color Utilities and matugen. Cookie and the palette presets have
  localized display forms recorded below; their underlying identifiers stay exact.
- Distribution and community names: Dotfiles, Superpaste (and its command
  `superpaste`), Dynamic Island, and booru site names.
- Other product and command names that appear in strings: Claude Code, UltraCode,
  Antigravity CLI, and `warp-cli`.

Recognized localized product names, such as a vendor's established local name for
File Explorer, may be used in prose. Do not translate executable names, URLs, or
identifiers to match those localized names. Treat this list as examples, not an
exhaustive allowlist.

## Ambiguities reviewers must check

| Term | Meanings that must stay distinct |
| --- | --- |
| Pin | Persistent dock shortcut; dock kept visible; sidebar reserving space; visible tray icon; window pin behavior. |
| Plan | Provider subscription access versus AI execution mode that does not run edits/commands. |
| Session | Desktop login session; saved AI conversation; provider usage time window. |
| Temperature | Weather; hardware sensor; display color warmth; AI sampling randomness. |
| Focus | Input focus of a window versus concentration time in Pomodoro. |
| Float | Floating windows versus the detached-from-edge visual style of a bar/dock/island. |
| Light / Minimal / Balanced | Appearance, animation, indicators, power settings, or AI effort/style depending on the control. |
| Key / Keyring | Keyboard key; API secret; encryption secret; personal secret storage; trusted package signing keys. |
| Source / Input / Output | Audio device; AI request/response tokens; image provider; source code; file-transfer direction. |
| Share | Persistent network-folder access versus sending a copy through LocalSend or a message. |
| Format | A display pattern versus erasing/recreating a filesystem. |
| Snapshot / Restore | System recovery; theme description; session restoration; restoring a window. |
| Group / Folder / Column | Window group; grouped widgets; filesystem folder; app-shortcut folder; scrolling-layout column. |
| Local / Online / Reachable | Where processing runs, internet connectivity, or whether a particular device/service can be contacted. |
| Clear | Clear a field/list/history versus a clear-sky forecast category. |
| Edge | Screen boundary versus the prerelease update channel. |

`Translation.tr()` currently uses a single English string as its lookup key; it
has no per-occurrence context parameter. Consequently, the exact same key cannot
have different translations for different callers in one locale. Use surrounding
source to resolve meaning, but flag a genuinely conflicting shared key for a
source change rather than silently choosing incompatible translations in
different batches. Do not change the English keys during a translation batch.

Also flag source instructions that appear stale or contradictory. Translating a
message is not permission to change the stated feature behavior, fix a shortcut,
invent a promise of successful delivery, or weaken an access/recovery warning.

## Reusable batch instruction

```text
Translate the supplied Mainstream OS locale values into TARGET_LOCALE.
Use TERMINOLOGY.md and the supplied source context for meaning. Follow the
approved target-language terminology from earlier batches.

Preserve all English JSON keys exactly. Change values only. Preserve placeholders,
command syntax, paths, URLs, markup, identifiers, meaningful joining whitespace,
and all conditions or consequences of an action. Keep short UI labels concise: shorter is better, and where two wordings are both
accurate, choose the shorter.
Preserve existing good translations. Use one consistent term for each concept.

Return only the requested entries as valid JSON, without Markdown fences or new
metadata keys. Report unresolved ambiguities separately from the catalog output.
Use the approved local display-name decisions, natural translations and conventional
transliterations. Retain recognizable English where local convention calls for it;
keep commands, identifiers and literal syntax exact.
Do not describe translations as native-speaker-verified without evidence.
```

For review, supply the English source, candidate values, glossary decisions, and
source context together. Request specific errors and corrections, then validate
JSON structure and placeholders and inspect the affected UI before accepting the
batch. Treat this glossary as input to the process, not as proof that the resulting
translations are correct.

## Current display-name decisions

These tables are the single current record for this terminology pass. Reuse the
catalog's inflected compound forms in clock settings and tooltips; do not replace
words across the entire JSON mechanically. Locale glossaries describe the other
recurring desktop terms, and historical notes do not override these decisions.

| Locale | Material cookie | Cookie | Notch | Dynamic Island |
| --- | --- | --- | --- | --- |
| `es_MX` | Galleta Material | Galleta | Muesca | Dynamic Island |
| `pt_BR` | Biscoito Material | Biscoito | Recorte | Dynamic Island |
| `de_DE` | Material-Keks | Keks | Notch | Dynamic Island |
| `fr_FR` | Biscuit Material | Biscuit | Encoche | Dynamic Island |
| `ru_RU` | Печенье Material | Печенье | Вырез | Dynamic Island |
| `zh_CN` | Material 饼干 | 饼干 | 刘海 | 灵动岛 |
| `ja_JP` | マテリアルクッキー | クッキー | ノッチ | Dynamic Island |
| `ko_KR` | 머티리얼 쿠키 | 쿠키 | 노치 | Dynamic Island |
| `tr_TR` | Material kurabiyesi | Kurabiye | Çentik | Dynamic Island |
| `pl_PL` | Ciastko Material | Ciastko | Wcięcie | Dynamic Island |
| `it_IT` | Biscotto Material | Biscotto | Tacca | Dynamic Island |
| `id_ID` | Kukis Material | Kukis | Takik | Dynamic Island |
| `uk_UA` | Печиво Material | Печиво | Виріз | Dynamic Island |
| `vi_VN` | Bánh quy Material | Bánh quy | Tai thỏ | Dynamic Island |
| `zh_TW` | Material 餅乾 | 餅乾 | 瀏海 | 動態島 |
| `hi_IN` | मटीरियल कुकी | कुकी | नॉच | Dynamic Island |
| `ar_SA` | كوكي ماتيريال | كوكي | نوتش | Dynamic Island |
| `fa_IR` | کوکی متریال | کوکی | ناچ | Dynamic Island |
| `he_IL` | עוגיית מטריאל | עוגייה | מגרעת | Dynamic Island |

| Locale | Tonal Spot | Neutral | Expressive | Fidelity | Monochrome | Fruit Salad | Rainbow |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `es_MX` | Acento tonal | Neutro | Expresivo | Fidelidad | Monocromático | Ensalada de frutas | Arcoíris |
| `pt_BR` | Destaque tonal | Neutro | Expressivo | Fidelidade | Monocromático | Salada de frutas | Arco-íris |
| `de_DE` | Tonaler Akzent | Neutral | Ausdrucksstark | Farbtreue | Monochrom | Obstsalat | Regenbogen |
| `fr_FR` | Accent tonal | Neutre | Expressif | Fidélité | Monochrome | Salade de fruits | Arc-en-ciel |
| `ru_RU` | Тональный акцент | Нейтральная | Выразительная | Точность цвета | Монохромная | Фруктовый салат | Радуга |
| `zh_CN` | 色调点缀 | 中性 | 表现力 | 保真 | 单色 | 水果沙拉 | 彩虹 |
| `ja_JP` | トーナルスポット | ニュートラル | エクスプレッシブ | 忠実度 | モノクロ | フルーツサラダ | 虹 |
| `ko_KR` | 토널 스폿 | 중립 | 표현형 | 충실도 | 단색 | 과일 샐러드 | 무지개 |
| `tr_TR` | Ton vurgusu | Nötr | İfadeli | Aslına sadık | Tek renk | Meyve salatası | Gökkuşağı |
| `pl_PL` | Akcent tonalny | Neutralny | Ekspresyjny | Wierność | Monochromatyczny | Sałatka owocowa | Tęcza |
| `it_IT` | Accento tonale | Neutro | Espressivo | Fedeltà | Monocromatico | Macedonia | Arcobaleno |
| `id_ID` | Aksen tonal | Netral | Ekspresif | Ketepatan warna | Monokrom | Salad buah | Pelangi |
| `uk_UA` | Тональний акцент | Нейтральна | Виразна | Точність кольору | Монохромна | Фруктовий салат | Веселка |
| `vi_VN` | Nhấn tông | Trung tính | Biểu cảm | Trung thực | Đơn sắc | Salad trái cây | Cầu vồng |
| `zh_TW` | 色調點綴 | 中性 | 表現力 | 忠實 | 單色 | 水果沙拉 | 彩虹 |
| `hi_IN` | टोनल स्पॉट | तटस्थ | भावपूर्ण | सटीक रंग | एकरंगी | फ़्रूट सलाद | इंद्रधनुष |
| `ar_SA` | لمسة لونية | محايد | تعبيري | دقة الألوان | أحادي اللون | سلطة فواكه | قوس قزح |
| `fa_IR` | تأکید رنگی | خنثی | بیانگر | وفاداری رنگ | تک‌رنگ | سالاد میوه | رنگین‌کمان |
| `he_IL` | הדגשת גוון | ניטרלי | הבעתי | נאמנות צבע | חד־גוני | סלט פירות | קשת |

## Regional and context decisions to retain

- es_MX: cápsula for a pill-shaped container; Extendido for Hug; espacio de
  trabajo, vista general, atajo de teclado and mouse. Use toca for touch and
  presiona for key presses; avoid mixing Peninsular vocabulary. Home is Carpeta
  personal. Standalone Swap is memory, while Intercambiar is a window action.
- Keep one term for blur, sidebar, workspace and settings throughout each
  catalog. A shape label does not require the exact spelling of its config key.
- A short Island label need not repeat the full Dynamic Island name. Distinguish
  System tray from the short Tray label, and full feature names from compounds.
- Treat every shared key by its callers: Visibility is weather visibility; Load:
  is resource load; Free: is available memory; Up %1 is system uptime; at is a
  battery threshold; Release is a key-release flag; Locked serves lock screen
  and keybind contexts; Closet is the hidden anime-tab mode.
- Thinking/reasoning budget is a processing allowance, not money. Plan may mean
  a subscription or the execution mode that never runs edits or commands.
- File, phone and recovery warnings must preserve their exact scope. Pairing is
  not connecting; Bluetooth pairing alone does not provide message/file access.
  Hiding conversations affects this desktop only. Root-owned files are not the
  same as the root filesystem. Do not promise recovery is automatic when the
  source only offers guidance.

## Workflow and review

1. Read this file and the current English catalog. Locate actual QML/JS, Files
   extension and script callers for ambiguous terms. Existing good translations
   are preserved unless a concrete meaning, grammar, syntax or consistency error
   warrants a change. Write new translations directly from English; do not use
   the rejected archived drafts or their build scripts. Never derive zh_TW by
   converting zh_CN.
2. Use everyday UI language and the locale's regional conventions. German uses
   du; French vous; es_MX tú; pt_BR você; Italian informal instructions; Polish
   impersonal or polite forms; Russian/Ukrainian polite plural; Turkish siz;
   Indonesian Anda; Vietnamese neutral wording; Hindi आप; Arabic MSA; Persian
   formal شما; Hebrew neutral infinitives or impersonal instructions; Japanese
   です/ます; Korean 합니다/하세요. Use proper Persian ZWNJ spelling. Do not add
   RTL controls unless an actual rendered problem requires a targeted fix.
3. Work in manageable feature batches. Preserve exact keys and their existing
   relative order, UTF-8 JSON with two-space indentation and a final newline.
   Preserve every placeholder, number, command, identifier, markup tag, code
   span, URL, path, shortcut, line break and meaningful joining space.
4. Validate every batch with `tools/catalog-qa.py`. Compare approved display-name
   decisions separately: a literal English-name check is not authority to reject
   an approved localized UI label. Never loosen checks on executable syntax.
5. Review a varied sample and every changed warning, destructive/access action,
   placeholder and ambiguous term against English and source. Check related
   labels and tooltips together. Self-review is not independent or native review;
   never claim either without evidence. Record unresolved fit/RTL limitations.
6. Audit every value left equal to English. Names, exact syntax, units and words
   shared naturally with the target language may be correct. Translate remaining
   ordinary prose. Do not change a correct loanword solely to reduce the count.
7. Re-scan current UI and updater scripts at the end, since source strings can be
   added during translation. Use the read-only coverage and QA commands in
   `tools/README.md`.
   `clean` only reports unobserved keys; it never deletes them. Sync is add-only
   and requires `--apply` to write. Do not prune legacy keys: even a scan covering
   QML, extensions and updater scripts can miss dynamic strings.
8. Until release, amend further translation JSON updates into the owner's single
   consolidated translation commit instead of adding separate locale commits.
   Keep the guidance, maintenance-tool and consolidated translation commits
   adjacent, in that order, after feature commits. During preparation the
   translation commit stays at HEAD; the final release-notes commit goes after
   this language block for release. Keep only catalog JSONs in the translation
   commit. Preserve feature changes and other contributors' staged and unstaged
   work when reorganizing history. Do not push or change the running desktop
   language without instruction.

### Read-only checks

From the repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python dots/.config/quickshell/ii/translations/tools/catalog-qa.py
python dots/.config/quickshell/ii/translations/tools/translation-manager.py --check-extensions
python sdata/lib/tr-keys.py sdata/update/updatems sdata/update/updatems-system sdata/update/mainstream-update-helper
```

Also validate the 47 formatted updater messages through the actual `sdata/lib/tr.sh`
formatter for every locale, without invoking the update commands themselves.
The language picker reads locale JSON filenames directly; no registration change
is needed. Add a new language only after its complete catalog is ready.
