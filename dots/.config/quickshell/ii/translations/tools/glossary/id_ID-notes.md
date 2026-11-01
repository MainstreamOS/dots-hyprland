# Indonesian completion notes

Catalog: `id_ID.json`. Source: all 3,221 English keys, SHA256
`d222d7ae70507e91f555e6bd621ed7b574f7c7f722ff73a8a4826260be17617b`.
Based on mainstream `f408399ec` and the owner’s updated 2026-10-28 guidance.

Translates 2,380 previously English-identical values and corrects 47 existing
entries for concrete syntax, meaning, terminology or UI-fit reasons. Preserves
669 sound existing translations. All 135 remaining English-identical values
are individually audited below. English keys and order are unchanged.

## Validation and review

- Every applied batch passed structural validation. `catalog-qa.py id_ID` reports zero errors: unique JSON, exact keys, placeholders and printf argument order, real newlines/joining whitespace, markup/Markdown/backticks, protected names, values, URLs, paths and flags.
- All 47 printf messages pass through the actual `sdata/lib/tr.sh` with distinct arguments. Exact key order and a separate slash-command audit pass.
- All 13 validator regression tests pass; the eleven completed catalogs also pass structural checks.
- Independent fresh-context review read all 1,662 packet records, including all 45 original before/after corrections, and reported three concrete issues. All three were fixed. A follow-up reread confirmed all three corrected pairs against the final catalog, with no further concrete problem (1,665 pair reviews total).
- Review packet: 1,662 unique pairs, including the 200-key feature sample across 83 source buckets, all 321 runtime-placeholder keys, 497 risk candidates, 376 ambiguity candidates, all final 721 entries, every old correction and all 135 intentional English-identical values. Sets overlap.
- Sample buckets: settings/<first component after modules/settings/>, desktop/<first after modules/ii/>, services/AI for /Ai. or /ai/ and services/other otherwise; sdata/ becomes scripts; absent source becomes legacy; other sources use apps/<basename>. Sort buckets lexically, sort keys by raw SHA256 of `id_ID-fresh-context-review-v1` + NUL + key, then take round-robin by bucket depth until 200.
- Compact UTF-8 JSON (`ensure_ascii=False`, comma/colon separators) of sample keys hashes to `17dc8d74df0f3dbcb6cbc742498ed37d8e81fdf502223f3e758bb5f13e23becb`; packet keys in catalog order hash to `f840247f5e97d547288c77ae73777a305041c868214c7de916699f8704e68b4f`.
- Root inspected terminology, count forms, assembled fragments, all identical entries and current source for ambiguous controls.
- No native-speaker review or live language preview was performed. These are translations with automated checks and a separate review.

## Existing translations replaced

| Exact English key | Previous value | Corrected value | Reason |
| --- | --- | --- | --- |
| No API key<br>Set it with /key YOUR_API_KEY | Tidak ada kunci API<br>Atur dengan /key KUNCI_API_ANDA | Tidak ada kunci API<br>Atur dengan /key YOUR_API_KEY | Preserve the literal command metavariable/syntax instead of translating it. |
| Usage: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt><br>Supply <tt>i</tt> when you want images<br>Examples:<br><tt>%1superpaste 4i</tt> for the last 4 images<br><tt>%1superpaste 7</tt> for the last 7 entries | Penggunaan: <tt>%1superpaste JUMLAH_ENTRI[i]</tt><br>Gunakan <tt>i</tt> jika Anda menginginkan gambar<br>Contoh:<br><tt>%1superpaste 4i</tt> untuk 4 gambar terakhir<br><tt>%1superpaste 7</tt> untuk 7 entri terakhir | Penggunaan: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt><br>Gunakan <tt>i</tt> jika Anda menginginkan gambar<br>Contoh:<br><tt>%1superpaste 4i</tt> untuk 4 gambar terakhir<br><tt>%1superpaste 7</tt> untuk 7 entri terakhir | Preserve the literal command metavariable/syntax instead of translating it. |
| Rect | Persegi | Persegi panjang | Rect is a rectangle, not a square. |
| 12h am/pm | 12j am/pm | 12h am/pm | Preserve the displayed literal time-format example and unit. |
| Enable blur | Aktifkan blur | Aktifkan efek buram | Use buram consistently for the blur/frost effect. |
| Discharging: | Menguras: | Menggunakan baterai: | Describe the battery discharging state rather than the bare verb draining. |
| Up %1 | Naik %1 | Aktif %1 | Concrete correction found during independent review; see the correction list. |
| Fruit Salad | Salad Buah | Fruit Salad | Preserve the exact named Material You palette preset under the owner’s updated guidance. |
| Also unlock keyring | Juga buka kunci keyring | Buka kunci ring kunci juga | Use the established personal-secret-storage term ring kunci. |
| Pills | Pil | Kapsul | Use kapsul for the shaped UI container, not medication pil. |
| Shell conflicts killer | Pemecah konflik shell | Penghenti konflik shell | Preserve that the feature stops conflicting programs. |
| API key is set<br>Change with /key YOUR_API_KEY | Kunci API sudah diatur<br>Ubah dengan /key KUNCI_API_ANDA | Kunci API sudah diatur<br>Ubah dengan /key YOUR_API_KEY | Preserve the literal command metavariable/syntax instead of translating it. |
| Neutral | Netral | Neutral | Preserve the exact named Material You palette preset under the owner’s updated guidance. |
| 12h AM/PM | 12j AM/PM | 12h AM/PM | Preserve the displayed literal time-format example and unit. |
| Usage: %1tool TOOL_NAME | Penggunaan: %1tool NAMA_ALAT | Penggunaan: %1tool TOOL_NAME | Preserve the literal command metavariable/syntax instead of translating it. |
| Tonal Spot | Titik Tonal | Tonal Spot | Preserve the exact named Material You palette preset under the owner’s updated guidance. |
| Expressive | Ekspresif | Expressive | Preserve the exact named Material You palette preset under the owner’s updated guidance. |
| Hug | Peluk | Melebar | Hug is the edge-spanning style, not the verb to embrace. |
| Rainbow | Pelangi | Rainbow | Preserve the exact named Material You palette preset under the owner’s updated guidance. |
| Fidelity | Fidelitas | Fidelity | Preserve the exact named Material You palette preset under the owner’s updated guidance. |
| Crosshair overlay | Overlay Crosshair | Hamparan bidik silang | Translate the residual English label using the chosen overlay and crosshair terms. |
| Keybinds | Pintasan keyboard | Pintasan | Keep the short label compact; the page includes mouse-button bindings as well as keyboard shortcuts. |
| Earbang protection | Perlindungan suara keras | Pelindung lonjakan volume | Specifically limits sudden volume jumps, not all loud sound. |
| Current tool: %1<br>Set it with %2tool TOOL | Alat saat ini: %1<br>Atur dengan %2tool ALAT | Alat saat ini: %1<br>Atur dengan %2tool TOOL | Preserve the literal command metavariable/syntax instead of translating it. |
| 24h | 24j | 24h | Preserve the displayed literal time-format example and unit. |
| Cookie clock settings | Pengaturan jam cookie | Pengaturan jam Cookie | Preserve the named Cookie shape/style. |
| Temperature<br>Change with /temp VALUE | Temperatur<br>Ubah dengan /temp NILAI | Temperatur<br>Ubah dengan /temp VALUE | Preserve the literal command metavariable/syntax instead of translating it. |
| Launch on startup | Luncurkan saat startup | Kunci saat startup | Actual source controls lock.launchOnStartup, so name locking on startup. |
| Free: | Gratis: | Tersedia: | Free is available memory/resources, not zero price. |
| Current API endpoint: %1<br>Set it with %2mode PROVIDER | Endpoint API saat ini: %1<br>Atur dengan %2mode PENYEDIA | Endpoint API saat ini: %1<br>Atur dengan %2mode PROVIDER | Preserve the literal command metavariable/syntax instead of translating it. |
| Monochrome | Monokrom | Monochrome | Preserve the exact named Material You palette preset under the owner’s updated guidance. |
| Enjoy! You can reopen the welcome app any time with <tt>Super+Shift+Alt+/</tt>. To open the settings app, hit <tt>Super+I</tt> | Enjoy! Anda dapat membuka kembali aplikasi selamat datang kapan saja dengan <tt>Super+Shift+Alt+/</tt>. Untuk membuka aplikasi pengaturan, tekan <tt>Super+I</tt> | Selamat menikmati! Anda dapat membuka kembali aplikasi selamat datang kapan saja dengan <tt>Super+Shift+Alt+/</tt>. Untuk membuka aplikasi pengaturan, tekan <tt>Super+I</tt> | Translate the remaining English greeting. |
| Usage: %1save CHAT_NAME | Penggunaan: %1save NAMA_OBROLAN | Penggunaan: %1save CHAT_NAME | Preserve the literal command metavariable/syntax instead of translating it. |
| Signed in. The plan models are in the picker now: type /model to choose between Gemini 3.8 Flash (High, Medium, Low) and Gemini 3.1 Pro (High, Low). | Sudah masuk. Model paket kini ada di pemilih: ketik /model untuk memilih antara Gemini 3.8 Flash (High, Medium, Low) dan Gemini 3.1 Pro (High, Low). | Sudah masuk. Model langganan kini ada di pemilih: ketik /model untuk memilih antara Gemini 3.8 Flash (Tinggi, Sedang, Rendah) dan Gemini 3.1 Pro (Tinggi, Rendah). | Subscription models use langganan; the visible effort levels are localized while command values remain literal. |
| Set thinking level (reasoning effort). Values: minimal, low, medium, high, auto. Replaces deprecated thinking budget. | Atur tingkat pemikiran (upaya penalaran). Nilai: minimal, low, medium, high, auto. Menggantikan thinking budget yang sudah usang. | Atur tingkat pemikiran (upaya penalaran). Nilai: minimal, low, medium, high, auto. Menggantikan jatah pemikiran yang sudah usang. | Translate the leftover English budget phrase as a processing allowance. |
| Signed in. Gemini Flash and Gemini Pro are in the picker now. Adjust thinking level with the reasoning pill or /think. | Sudah masuk. Gemini Flash dan Gemini Pro kini ada di pemilih. Sesuaikan tingkat pemikiran melalui pil status atau /think. | Sudah masuk. Gemini Flash dan Gemini Pro kini ada di pemilih. Sesuaikan tingkat pemikiran melalui kapsul penalaran atau /think. | The reasoning UI is a kapsul, not a medication pill or a generic status pill. |
| Thinking Level: %1<br>Click to cycle (minimal → low → medium → high → auto) | Tingkat pemikiran: %1<br>Klik untuk beralih (minimal → low → medium → high → auto) | Tingkat pemikiran: %1<br>Klik untuk beralih (minimal → rendah → sedang → tinggi → otomatis) | Concrete correction found during independent review; see the correction list. |
| Signed in. Gemini Flash and Gemini Pro are in the picker now. Adjust thinking level with /think. | Sudah masuk. Gemini Flash dan Gemini Pro sekarang ada di pemilih. Sesuaikan tingkat berpikir dengan /think. | Sudah masuk. Gemini Flash dan Gemini Pro sekarang ada di pemilih. Sesuaikan tingkat pemikiran dengan /think. | Use the same tingkat pemikiran term as the control. |
| Commands: /model <name> · /mode [ask\|auto\|plan] | Perintah: /model <nama> · /mode [ask\|auto\|plan] | Perintah: /model <name> · /mode [ask\|auto\|plan] | Preserve the literal command metavariable/syntax instead of translating it. |
| Controls extended thinking budget and verification effort. | Mengatur anggaran penalaran lanjutan dan upaya verifikasi. | Mengatur jatah pemikiran lanjutan dan upaya verifikasi. | Use the processing-allowance sense of jatah, not a financial-budget label. |
| Home | Rumah | Folder pribadi | Home means the personal folder, not a house. |
| Maximum reasoning budget for exhaustive verification | Anggaran penalaran maksimal untuk verifikasi menyeluruh | Jatah penalaran maksimal untuk verifikasi menyeluruh | Use the glossary processing allowance jatah penalaran. |
| Model default reasoning budget | Anggaran penalaran default model | Jatah penalaran bawaan model | Use the glossary processing allowance jatah penalaran. |
| Search across all files in your home folder | Cari di semua file di folder rumah Anda | Cari di semua file di folder pribadi Anda | Use folder pribadi consistently for the filesystem home. |
| [[ Command timed out after %1 s ]] | [[ Perintah habis waktu setelah %1 dtk ]] | [[ Perintah habis waktu setelah %1 s ]] | Preserve the supplied seconds unit in the formatted timeout. |
| Voice input could not read the Gemini API key because the keyring could not be unlocked. | Input suara tidak dapat membaca kunci API Gemini karena keyring tidak dapat dibuka kuncinya. | Input suara tidak dapat membaca kunci API Gemini karena ring kunci tidak dapat dibuka. | Use ring kunci consistently and retain unlock-failure meaning. |
| Only local models are allowed right now. To use online models, set AI to Yes in Settings > Interface > Left Sidebar. | Saat ini hanya model lokal yang diizinkan. Untuk memakai model online, atur AI ke Ya di Pengaturan > Antarmuka > Left Sidebar. | Saat ini hanya model lokal yang diizinkan. Untuk memakai model online, atur AI ke Ya di Pengaturan > Antarmuka > Sidebar Kiri. | Match the translated Left Sidebar settings breadcrumb. |

## Corrections from independent review

| Exact English key | Correction |
| --- | --- |
| Up %1 | Up is elapsed system uptime, not an upward direction. |
| Thinking Level: %1<br>Click to cycle (minimal → low → medium → high → auto) | Translate the visible effort-level progression in a click-cycle tooltip; preserve raw tokens only in command examples. |
| Removes a stutter in some older games on Intel processors.<br>Also removes a protection against one program stalling the machine. | State that the removed protection prevents a program from stalling the system, without implying the removal prevents stalls. |

## Intentionally English-identical values

These are individually checked Indonesian loanwords, shared words, names, units
or literal formats, not unfinished English prose.

| Exact English key | Reason |
| --- | --- |
| Material cookie | Preserved product, project, protocol, named layout, command or preset. |
| Info | Info is the standard abbreviation of informasi. |
| Audio | Audio is standard Indonesian vocabulary. |
| Volume | Volume is the Indonesian audio-level noun. |
| Gamma | Gamma is the conventional color-control term. |
| 12h am/pm | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Fruit Salad | Preserved product, project, protocol, named layout, command or preset. |
| OK | Conventional OK confirmation. |
| illogical-impulse | Preserved product, project, protocol, named layout, command or preset. |
| Dotfiles | Preserved product, project, protocol, named layout, command or preset. |
| Input | Input is the existing Indonesian computing loanword. |
| Format | Format is the standard Indonesian technical word. |
| Desktop | Desktop is the chosen desktop-environment term. |
| Neutral | Preserved product, project, protocol, named layout, command or preset. |
| 12h AM/PM | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Anime | Anime is the established genre name. |
| Output | Output is the existing Indonesian computing loanword. |
| Tonal Spot | Preserved product, project, protocol, named layout, command or preset. |
| Expressive | Preserved product, project, protocol, named layout, command or preset. |
| Superpaste | Preserved product, project, protocol, named layout, command or preset. |
| Rainbow | Preserved product, project, protocol, named layout, command or preset. |
| GitHub | Preserved product, project, protocol, named layout, command or preset. |
| Stopwatch | Stopwatch is the chosen established timer-device loanword. |
| Fidelity | Preserved product, project, protocol, named layout, command or preset. |
| Terminal | Terminal is standard Indonesian computing vocabulary. |
| Cloudflare WARP (1.1.1.1) | Preserved product, project, protocol, named layout, command or preset. |
| 24h | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Total: | Total is also the Indonesian quantity label. |
| Distro | Distro is the established distribution abbreviation. |
| Bluetooth | Preserved product, project, protocol, named layout, command or preset. |
| Pomodoro | Preserved product, project, protocol, named layout, command or preset. |
| AI | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Cloudflare WARP | Preserved product, project, protocol, named layout, command or preset. |
| Monochrome | Preserved product, project, protocol, named layout, command or preset. |
| Edit | Edit is a standard Indonesian software action. |
| Android | Preserved product, project, protocol, named layout, command or preset. |
| Internet | Internet is standard Indonesian vocabulary. |
| EasyEffects | Preserved product, project, protocol, named layout, command or preset. |
| Google Lens | Preserved product, project, protocol, named layout, command or preset. |
| Normal | Normal is an Indonesian adjective. |
| %1 nits | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| %1s | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| %1s… | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| %1… | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| 0° | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| 50 % APL  ·  %1 nits | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Cookie | Preserved product, project, protocol, named layout, command or preset. |
| dd/MM | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| dd.MM | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Digital | Digital is an Indonesian adjective. |
| Emoji | Emoji is the established borrowed noun. |
| LCD HDR 1000 | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| LCD HDR 600 | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Media | Media is an Indonesian noun. |
| Mode | Mode is an Indonesian noun. |
| MM/dd | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Mouse | Mouse is the chosen existing input-device loanword. |
| OLED / QD-OLED | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Status | Status is an Indonesian noun. |
| Swap | Swap is the established memory term; all current callers are memory statistics. |
| Tips & Info | Tips and Info are standard Indonesian UI loanwords/abbreviations. |
| Touchpad | Touchpad is the chosen input-device loanword. |
| VRAM: | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Web | Web is standard Indonesian vocabulary. |
| DaVinci Resolve | Preserved product, project, protocol, named layout, command or preset. |
| DaVinci Resolve Studio | Preserved product, project, protocol, named layout, command or preset. |
| Desktop + Big Picture | Desktop is Indonesian technical vocabulary; Big Picture is a feature name. |
| Drive | Drive is the chosen storage-device loanword. |
| File | File is the established invariant Indonesian noun. |
| Folder | Folder is the existing invariant Indonesian noun. |
| Celsius | Named temperature scale. |
| Fahrenheit | Named temperature scale. |
| Gaming | Gaming is the chosen existing gaming-category loanword. |
| Horizontal | Horizontal is an Indonesian adjective. |
| Master | Preserved product, project, protocol, named layout, command or preset. |
| Monocle | Preserved product, project, protocol, named layout, command or preset. |
| OBS Studio | Preserved product, project, protocol, named layout, command or preset. |
| Server | Server is the established technical loanword. |
| end-4 — Dotfiles | Preserved product, project, protocol, named layout, command or preset. |
| %1 (%2) | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Slideshow | Slideshow is the chosen familiar UI loanword. |
|  min | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Wallpaper | Wallpaper is the existing desktop-image term. |
| Radius | Radius is a standard Indonesian geometric term. |
| Minimal | Minimal is an Indonesian adjective. |
| tearing | Tearing is the established graphics term. |
| Notch | Preserved product, project, protocol, named layout, command or preset. |
| Discord | Preserved product, project, protocol, named layout, command or preset. |
| Keyboard | Keyboard is the chosen existing input-device loanword. |
| min | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| GitHub Sponsors | Preserved product, project, protocol, named layout, command or preset. |
| Ko-fi | Preserved product, project, protocol, named layout, command or preset. |
| Patreon | Preserved product, project, protocol, named layout, command or preset. |
| CRT | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Zoom | Zoom is the conventional UI/motion term. |
| ok | Conventional compact ok status. |
| updatems | Preserved product, project, protocol, named layout, command or preset. |
| updatems-system | Preserved product, project, protocol, named layout, command or preset. |
| macrecovery | Preserved product, project, protocol, named layout, command or preset. |
| AUR (yay/paru): | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Flatpak: | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Snap: | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Dotfiles (updatems): | Preserved product, project, protocol, named layout, command or preset. |
| <none> | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Email | Email is standard Indonesian vocabulary. |
| GIMP | Preserved product, project, protocol, named layout, command or preset. |
| Krita | Preserved product, project, protocol, named layout, command or preset. |
| LibreOffice | Preserved product, project, protocol, named layout, command or preset. |
| OnlyOffice | Preserved product, project, protocol, named layout, command or preset. |
| Sunshine | Preserved product, project, protocol, named layout, command or preset. |
| Moonlight | Preserved product, project, protocol, named layout, command or preset. |
| Blender | Preserved product, project, protocol, named layout, command or preset. |
| 15 fps | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| 30 fps | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Administrator | Administrator is the standard account-role noun. |
| WiVRn | Preserved product, project, protocol, named layout, command or preset. |
| Antigravity CLI — agy update | Preserved product, project, protocol, named layout, command or preset. |
| Antigravity: | Preserved product, project, protocol, named layout, command or preset. |
| Model: %1 · Mode: %2 | Preserved product, project, protocol, named layout, command or preset. |
| Ollama | Preserved product, project, protocol, named layout, command or preset. |
| UltraCode | Preserved product, project, protocol, named layout, command or preset. |
| GIF | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Video | Video is an Indonesian media noun. |
| %1 B | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| %1 KB | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| %1 MB | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| %1 GB | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| LocalSend | Preserved product, project, protocol, named layout, command or preset. |
| RAM | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| CPU | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Ethernet | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Wi-Fi | Unit, number/date format, acronym, placeholder-only label or literal updater sentinel. |
| Dynamic Island | Preserved product, project, protocol, named layout, command or preset. |
| Sidebar | Sidebar is the chosen existing desktop-panel loanword. |
| Dwindle | Preserved product, project, protocol, named layout, command or preset. |

## Shared keys, source issues and limits

- Indonesian count nouns are invariant: file, kontak, gambar and other counted nouns work with arbitrary numeric placeholders without plural duplication.
- The owner’s new naming policy preserves Dotfiles/dotfiles, Cookie/Material cookie, all seven Material You palette names, scratchpad, submap, fake fullscreen, pseudo-tiling, Notch and Dynamic Island. Expressive font is a normal translated font role. Short Island labels use Pulau; Hug uses Melebar; pill uses Kapsul.
- Standalone Swap serves memory statistics in the three current resource-panel callers. Keep Swap there; Tukar is used for window actions. The supplied offline Spanish reasoning inferred a window-action meaning without source access.
- Plan in provider descriptions is Langganan; execution Plan mode is Rencana. User-facing effort labels translate, while accepted command values and metavariables remain English. Reasoning budget means a processing allowance, Jatah, not money.
- Home is Folder pribadi. Files is File, the invariant Indonesian noun. Ring kunci stores personal secrets; Kumpulan kunci stores trusted signing keys. Countdown Timer is Pewaktu, while technical systemd .timer units retain Timer in logs.
- The standalone Locked key serves both lock-screen status and a shortcut type. Terkunci suits the state; the bind description and combined labels specify working while locked. Source needs separate keys if both short labels must be fully explicit. Launch on startup actually controls locking, so it is Kunci saat startup.
- Play is shared by a gaming heading and playback controls. Putar prioritizes the actionable playback controls; the gaming heading needs a separate source key. From/To are Dari/Ke for gradients and recipients.
- The source sharing-password warning mentions accents and emoji, but the validator allows printable ASCII only. Preserve the supplied meaning; the source should explain the complete restriction. Clearing a network’s firewall zone removes its assignment, not the zone definition.
- Streaming privacy hides Island presentation, not calls/messages on the phone. Current source checks for Discord/OBS windows or processes, without confirming an active stream. The source behavior/wording needs separate review.
- Country labels are English names from iso3166.tab. Do not invent localized injected content. Pricing/model capability statements are translated as supplied, not externally verified.
- The legacy git stash list advice lists stashes instead of restoring them; the newer key provides explicit show/pop commands. Literal commands remain unchanged. Legacy sidebar shortcuts and provider-mode arguments differ from current controls; translations do not silently fix those source differences.
- The old update-advice key contains literal \u2014; the key is unchanged and the value uses ordinary Indonesian punctuation. The actual English source digest and complete key order are verified.
- Short accurate compounds are retained where a one-word option would be wrong: Rect is Persegi panjang, not Persegi (square). Long technical labels and the full Indonesian sentences need eventual live UI-fit review; no manual wrapping line breaks were added.

## Historical reasoning review

Historical review record. Current rules and display names are consolidated in
[TERMINOLOGY.md](../../TERMINOLOGY.md); the English-preservation decisions in this
old report are superseded where the current guide specifies localized labels.

This is the focused follow-up requested after Ukrainian completion. It applies
the owner’s updated terminology, HANDOFF.md, and corrected es_MX example from
`/home/itsjustdroid/Downloads/updated-reasoning`. It supplements the initial
glossary and completion notes; the decisions below supersede older decisions
on these terms. Good existing values outside concrete findings are preserved.

Changes: **2 of 3,221 values**. Source English keys and order are
unchanged. **135 values remain English-identical**; new ones introduced
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
| Island position | Posisi Pulau |
| Island style | Gaya Pulau |
| Pills | Kapsul |
| Hug | Melebar |
| Notch | Notch |
| Earbang protection | Pelindung lonjakan volume |
| Unmuted | Bersuara |
| Home | Folder pribadi |
| Swap | Swap |
| Tray | Baki |
| System tray | Baki sistem |
| Blur | Buram |

All seven named palette presets stay in English: Fruit Salad, Neutral, Tonal Spot, Expressive, Rainbow, Fidelity, Monochrome.
Hyprland scratchpad, submap, fake fullscreen and pseudo-tiling stay literal.
Capitalization such as Material Cookie remains where it is already recognizable
English and correct for the locale; no case-only rewrites were made.

### Exact value changes

| Exact English key | Previous committed value | Reviewed value | Reason |
| --- | --- | --- | --- |
| at | di | pada | The actual caller is a battery-percentage threshold (PowerConfig.qml:434), not a clock time or physical location. |
| Conflicts with the shell's system tray implementation | Konflik dengan implementasi system tray shell | Konflik dengan implementasi baki sistem shell | Use the established system-tray term consistently with the translated tray labels. |

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

- "Material cookie" → "Kukis Material"
- "Fruit Salad" → "Salad buah"
- "Neutral" → "Netral"
- "Tonal Spot" → "Aksen tonal"
- "Expressive" → "Ekspresif"
- "Rainbow" → "Pelangi"
- "Fidelity" → "Ketepatan warna"
- "Cookie clock settings" → "Pengaturan jam Kukis"
- "Monochrome" → "Monokrom"
- "Use old sine wave cookie implementation" → "Gunakan implementasi Kukis berbasis gelombang sinus lama"
- "Cookie" → "Kukis"
- "Notch" → "Takik"

Current intentionally English-identical count: 126. Names, units, literal formats and natural shared vocabulary remain valid; the lower count is not the purpose of this pass.
