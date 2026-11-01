# Turkish completion notes

Catalog: `tr_TR.json`. Source: all 3,221 keys of `en_US.json`, based on mainstream `7206d5a96`.

Translates 2,298 previously English-identical values and corrects 46 existing translations for specific meaning, grammar, terminology or protected-syntax defects. Preserves 801 sound existing translations. The 76 remaining English-identical values were individually checked and are listed below. Keys and order are unchanged.

## Validation and review

- Every batch passed structural validation before writing. `tools/catalog-qa.py tr_TR` reports zero errors: unique JSON and exact keys, placeholder counts and printf order, actual newlines and joining whitespace, markup/Markdown/backticks, protected names, numeric values, URLs, paths, flags and config filenames.
- All 47 printf-format messages pass through the actual `sdata/lib/tr.sh` with distinct arguments. Exact key order and a separate slash-command audit also pass.
- All 13 validator regression tests pass; the eight previously completed locale catalogs also pass structural checks.
- A fresh-context review covered all 1,617 packet records, including source excerpts and every old correction. All 14 reported defects were corrected, then all 14 corrected pairs were independently reread and confirmed resolved. No additional concrete command, placeholder-order, access-condition or recovery-warning defects were found in that packet.
- Required packet: 1,617 unique English/Turkish pairs: a 200-key feature sample across 83 source buckets, all 321 actual runtime-placeholder keys, 497 warning/destructive/access/update/recovery candidates, 376 ambiguity candidates, all final 721 AI/phone/Island keys, every old correction and every English-identical value. Sets overlap. The percent-encoded Zerochan URL is also checked exactly.
- Sample selection groups by first candidate source: settings/<first component after modules/settings/>, desktop/<first after modules/ii/>, services/AI for /Ai. or /ai/, otherwise services/other; sdata/ becomes scripts; no source becomes legacy; other paths use apps/<basename>. Sort buckets lexically and keys within each bucket by raw SHA256 of `tr_TR-fresh-context-review-v1` + NUL + key, then take round-robin by bucket depth until 200.
- Compact UTF-8 JSON serialization (`ensure_ascii=False`, separators comma and colon) of sample keys hashes to `e13af4b04ffc27d6c31e12da0a9853f247ea4c158a1baa25539561939b9bc6d2`. Packet keys in catalog order hash to `a35fd5904f66be3398ef987bc6d1f3350506433cf7d11c756d2b4aba3a181bd8`.
- Root audited glossary terms across the full catalog, compared all preexisting translations and read source contexts for ambiguous controls.
- No native-speaker review or live language preview was performed. These are translations with automated validation and a separate review.

## Existing translations replaced

Every replacement below is a concrete correction, not a stylistic rewrite.

| Exact English key | Previous value | Corrected value | Reason |
| --- | --- | --- | --- |
| Change any time later with /dark, /light, /wallpaper in the launcher<br>If the shell's colors aren't changing:<br>    1. Open the right sidebar with Super+N<br>    2. Click "Reload Hyprland & Quickshell" in the top-right corner | İstediğiniz zaman /dark, /light, /wallpaper komutlarıyla değiştirebilirsiniz<br>Shell renkleri değişmiyorsa:<br>    1. Super+N ile sağ kenar çubuğunu açın<br>    2. Sağ üst köşedeki "Hyprland ve Quickshell'i Yeniden Yükle" düğmesine tıklayın | Başlatıcıdaki /dark, /light, /wallpaper komutlarıyla istediğiniz zaman değiştirebilirsiniz<br>Kabuk renkleri değişmiyorsa:<br>    1. Super+N ile sağ kenar çubuğunu açın<br>    2. Sağ üst köşedeki "Hyprland ve Quickshell'i Yeniden Yükle" düğmesine tıklayın | Use the established Kabuk term, consistent with the existing conflict warnings. |
| Load prompt from %1 | %1'den komut yükle | %1 kaynağından istem yükle | Prompt is an instruction, not a shell command. |
| at | saat | eşik | Battery threshold, not time of day. |
| No API key<br>Set it with /key YOUR_API_KEY | API anahtarı yok<br>/key API_ANAHTARINIZ ile ayarlayın | API anahtarı yok<br>/key YOUR_API_KEY ile ayarlayın | Restore the literal command metavariable required by the source syntax. |
| Usage: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt><br>Supply <tt>i</tt> when you want images<br>Examples:<br><tt>%1superpaste 4i</tt> for the last 4 images<br><tt>%1superpaste 7</tt> for the last 7 entries | Kullanım: <tt>%1superpaste GIRDI_SAYISI[i]</tt><br>Görseller için <tt>i</tt> ekleyin<br>Örnekler:<br><tt>%1superpaste 4i</tt> son 4 görsel için<br><tt>%1superpaste 7</tt> son 7 girdi için | Kullanım: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt><br>Görseller için <tt>i</tt> ekleyin<br>Örnekler:<br><tt>%1superpaste 4i</tt> son 4 görsel için<br><tt>%1superpaste 7</tt> son 7 girdi için | Restore the literal command metavariable required by the source syntax. |
| 12h am/pm | 12s öö/ös | 12 saat öö/ös | h denotes hours, not Turkish second abbreviation s. |
| Visibility | Görünürlük | Görüş mesafesi | Weather visibility is a distance measurement. |
| Shell & utilities | Shell ve yardımcı programlar | Kabuk ve yardımcı programlar | Use the established Kabuk term, consistent with the existing conflict warnings. |
| Uses Gemini to categorize the wallpaper then picks a preset based on it.<br>You'll need to set Gemini API key on the left sidebar first.<br>Images are downscaled for performance, but just to be safe,<br>do not select wallpapers with sensitive information. | Gemini kullanarak duvar kağıdını kategorize eder ve ona göre bir ön ayar seçer.<br>Önce sol kenar çubuğunda Gemini API anahtarını ayarlamanız gerekir.<br>Görseller performans için küçültülür, ancak güvenli olmak için<br>hasas bilgi içeren duvar kağıtlarını seçmeyin. | Gemini kullanarak duvar kağıdını kategorize eder ve ona göre bir ön ayar seçer.<br>Önce sol kenar çubuğunda Gemini API anahtarını ayarlamanız gerekir.<br>Görseller performans için küçültülür, ancak güvenli olmak için<br>hassas bilgi içeren duvar kağıtlarını seçmeyin. | Correct hassas spelling in the sensitive-information warning. |
| Pills | Haplar | Kapsüller | Pill denotes a UI capsule, not medicine. |
| Shell conflicts killer | Shell çakışma giderici | Kabuk çakışma giderici | Use the established Kabuk term, consistent with the existing conflict warnings. |
| API key is set<br>Change with /key YOUR_API_KEY | API anahtarı ayarlandı<br>/key API_ANAHTARINIZ ile değiştirin | API anahtarı ayarlandı<br>/key YOUR_API_KEY ile değiştirin | Restore the literal command metavariable required by the source syntax. |
| 12h AM/PM | 12s ÖÖ/ÖS | 12 saat ÖÖ/ÖS | h denotes hours, not Turkish second abbreviation s. |
| System prompt | Sistem komutu | Sistem istemi | Use the chosen system-prompt term istem. |
| Usage: %1tool TOOL_NAME | Kullanım: %1tool ARAÇ_ADI | Kullanım: %1tool TOOL_NAME | Restore the literal command metavariable required by the source syntax. |
| Suspend at | Askıya alma zamanı | Askıya alma eşiği | Battery suspend threshold, not a time. |
| Hug | Sarıl | Kenara yaslı | Hug names an edge-adhering style, not an embrace. |
| Sides | Yanlar | Kenar sayısı | Polygon side count, not physical left/right sides. |
| Line-separated | Satır ayrılmış | Çizgilerle ayrılmış | Bar separators are lines, not newline-delimited text. |
| Loaded the following system prompt<br><br>---<br><br>%1 | Aşağıdaki sistem komutu yüklendi<br><br>---<br><br>%1 | Aşağıdaki sistem istemi yüklendi<br><br>---<br><br>%1 | Use system istemi consistently for system prompt. |
| Current tool: %1<br>Set it with %2tool TOOL | Mevcut araç: %1<br>%2tool ARAÇ ile ayarlayın | Mevcut araç: %1<br>%2tool TOOL ile ayarlayın | Restore the literal command metavariable required by the source syntax. |
| Shell command | Shell komutu | Kabuk komutu | Use the established Kabuk term, consistent with the existing conflict warnings. |
| 24h | 24s | 24 saat | h denotes hours, not seconds. |
| Random osu! seasonal background<br>Image is saved to ~/Pictures/Wallpapers | Rastgele osu! mevsimlik arka plan<br>Görsel ~/Resimler/Wallpapers dizinine kaydedilir | Rastgele osu! mevsimlik arka plan<br>Görsel ~/Pictures/Wallpapers dizinine kaydedilir | Restore the actual literal filesystem path. |
| Work safety | İş güvenliği | İşyerine uygun içerik | Content suitable for work, not occupational safety. |
| Temperature<br>Change with /temp VALUE | Sıcaklık<br>/temp DEĞER ile değiştirin | Sıcaklık<br>/temp VALUE ile değiştirin | Restore the literal command metavariable required by the source syntax. |
| Closet | Dolap | Gizli | Concealed anime page, not a physical closet. |
| Launch on startup | Başlangıçta başlat | Başlangıçta kilitle | Source controls lock.launchOnStartup, so say lock at startup. |
| Shell & utilities theming must also be enabled | Shell ve yardımcı program temalaması da etkinleştirilmelidir | Kabuk ve yardımcı program temalaması da etkinleştirilmelidir | Use the established Kabuk term, consistent with the existing conflict warnings. |
| Current API endpoint: %1<br>Set it with %2mode PROVIDER | Mevcut API uç noktası: %1<br>%2mode SAĞLAYICI ile ayarlayın | Mevcut API uç noktası: %1<br>%2mode PROVIDER ile ayarlayın | Restore the literal command metavariable required by the source syntax. |
| Set the system prompt for the model. | Model için sistem komutunu ayarlayın. | Model için sistem istemini ayarlayın. | Use system istemi consistently for system prompt. |
| Open the shell config file.<br>If the button doesn't work or doesn't open in your favorite editor,<br>you can manually open ~/.config/illogical-impulse/config.json | Shell yapılandırma dosyasını açın.<br>Düğme çalışmıyorsa veya favori düzenleyicinizde açılmıyorsa,<br>~/.config/illogical-impulse/config.json dosyasını manuel olarak açabilirsiniz | Kabuk yapılandırma dosyasını açın.<br>Düğme çalışmıyorsa veya favori düzenleyicinizde açılmıyorsa,<br>~/.config/illogical-impulse/config.json dosyasını manuel olarak açabilirsiniz | Use the established Kabuk term, consistent with the existing conflict warnings. |
| The current system prompt is<br><br>---<br><br>%1 | Mevcut sistem komutu<br><br>---<br><br>%1 | Mevcut sistem istemi<br><br>---<br><br>%1 | Use system istemi consistently for system prompt. |
| Usage: %1save CHAT_NAME | Kullanım: %1save SOHBET_ADI | Kullanım: %1save CHAT_NAME | Restore the literal command metavariable required by the source syntax. |
| Usage: %1load CHAT_NAME | Kullanım: %1load SOHBET_ADI | Kullanım: %1load CHAT_NAME | Restore the literal command metavariable required by the source syntax. |
| Language not listed or incomplete translations?<br>You can choose to generate translations for it with Gemini.<br>1. Open the left sidebar with Super+A, set model to Gemini (if it isn't already)<br>2. Type /key, hit Enter and follow the instructions<br>3. Type /key YOUR_API_KEY<br>4. Type the locale of your language below and press Generate | Dil listede yok veya çeviriler eksik mi?<br>Gemini ile çeviriler oluşturmayı seçebilirsiniz.<br>1. Super+A ile sol kenar çubuğunu açın, modeli Gemini olarak ayarlayın (değilse)<br>2. /key yazın, Enter'a basın ve talimatları izleyin<br>3. /key API_ANAHTARINIZ yazın<br>4. Dilinizin yerel ayarını aşağıya yazın ve Oluştur'a basın | Diliniz listede yok mu veya çeviriler eksik mi?<br>Gemini ile çeviri oluşturabilirsiniz.<br>1. Super+A ile sol kenar çubuğunu açın ve modeli Gemini olarak ayarlayın (henüz seçili değilse)<br>2. /key yazın, Enter'a basın ve talimatları izleyin<br>3. /key YOUR_API_KEY yazın<br>4. Aşağıya dilinizin yerel ayar kodunu girin ve Oluştur'a basın | Restore the literal command metavariable required by the source syntax. |
| Full warning | Tam uyarı | Tam doluluk uyarısı | Battery full-charge warning, not an entire warning. |
| Open the shell config file<br>Alternatively right-click to copy path | Shell yapılandırma dosyasını açın<br>Alternatif olarak yolu kopyalamak için sağ tıklayın | Kabuk yapılandırma dosyasını açın<br>Alternatif olarak yolu kopyalamak için sağ tıklayın | Use the established Kabuk term, consistent with the existing conflict warnings. |
| Signed in. The plan models are in the picker now: type /model to choose between Gemini 3.8 Flash (High, Medium, Low) and Gemini 3.1 Pro (High, Low). | Giriş yapıldı. Plan modelleri artık seçicide: Gemini 3.8 Flash (High, Medium, Low) ile Gemini 3.1 Pro (High, Low) arasında seçim yapmak için /model yazın. | Oturum açıldı. Abonelik modelleri artık seçicide: Gemini 3.8 Flash (High, Medium, Low) ile Gemini 3.1 Pro (High, Low) arasında seçim yapmak için /model yazın. | Provider subscription models must be distinct from execution Plan mode. |
| Set thinking level (reasoning effort). Values: minimal, low, medium, high, auto. Replaces deprecated thinking budget. | Düşünme düzeyini (akıl yürütme çabasını) ayarlayın. Değerler: minimal, low, medium, high, auto. Kullanımdan kaldırılan thinking budget yerine geçer. | Düşünme düzeyini (akıl yürütme eforunu) ayarlayın. Değerler: minimal, low, medium, high, auto. Kullanımdan kaldırılan düşünme bütçesinin yerini alır. | Use the existing reasoning-effort term and translate the prose thinking-budget concept. |
| Signed in. Gemini Flash and Gemini Pro are in the picker now. Adjust thinking level with the reasoning pill or /think. | Giriş yapıldı. Gemini Flash ve Gemini Pro artık seçicide. Düşünme düzeyini durum göstergesine tıklayarak veya /think ile ayarlayın. | Oturum açıldı. Gemini Flash ve Gemini Pro artık seçicide. Düşünme düzeyini akıl yürütme kapsülüyle veya /think ile ayarlayın. | Identify the reasoning capsule rather than an unspecified status indicator. |
| Attach file (browse inside sidebar) | Dosya ekle (kenar çubuğunda gözat) | Dosya ekle (kenar çubuğunda göz at) | Correct göz at spelling in the attachment browser tooltip. |
| Commands: /model <name> · /mode [ask\|auto\|plan] | Komutlar: /model <ad> · /mode [ask\|auto\|plan] | Komutlar: /model <name> · /mode [ask\|auto\|plan] | Restore the literal command metavariable required by the source syntax. |
| Thought for %1 | %1 düşündü | %1 boyunca düşündü | The placeholder is elapsed duration; add the required duration construction. |
| Signed in. The plan models are in the picker now: type /model to choose one. | Oturum açıldı. Plan modelleri artık seçicide: birini seçmek için /model yazın. | Oturum açıldı. Abonelik modelleri artık seçicide: birini seçmek için /model yazın. | Provider subscription models must be distinct from execution Plan mode. |
| Only local models are allowed right now. To use online models, set AI to Yes in Settings > Interface > Left Sidebar. | Şu anda yalnızca yerel modellere izin veriliyor. Çevrimiçi modelleri kullanmak için Ayarlar > Arayüz > Left Sidebar bölümünde AI seçeneğini Evet yapın. | Şu anda yalnızca yerel modellere izin veriliyor. Çevrimiçi modelleri kullanmak için Ayarlar > Arayüz > Sol kenar çubuğu bölümünde AI seçeneğini Evet yapın. | Translate the Left Sidebar settings breadcrumb to match the interface. |

## Draft corrections after independent review

| Exact English key | Correction |
| --- | --- |
| Change any time later with /dark, /light, /wallpaper in the launcher<br>If the shell's colors aren't changing:<br>    1. Open the right sidebar with Super+N<br>    2. Click "Reload Hyprland & Quickshell" in the top-right corner | Restore the launcher location for slash commands. |
| Language not listed or incomplete translations?<br>You can choose to generate translations for it with Gemini.<br>1. Open the left sidebar with Super+A, set model to Gemini (if it isn't already)<br>2. Type /key, hit Enter and follow the instructions<br>3. Type /key YOUR_API_KEY<br>4. Type the locale of your language below and press Generate | Restore the condition that Gemini need only be selected if not already selected. |
| Locked Desc | Describe a shortcut working while locked, not a description owned by the lock screen. |
| Locked Non-cons | Describe a forwarding shortcut working while locked. |
| Locked Repeat | Describe a repeating shortcut working while locked. |
| Open Overview with <b>Super <font face='JetBrains Mono NF'>(󰖳)</font></b>, then drag — move an already-open window from one workspace tile to another, or grab a fresh app from the drawer and drop it on any workspace. Either way, the app lands right where you want it. | Use yerleşir so moving an already-open window does not imply opening it again. |
| Turning Wi-Fi off also turns off the wireless adapter for the Steam Frame (experimental), so the headset cannot stream through it until Wi-Fi is back on. | The headset receives its stream through the wireless adapter, not through itself. |
| Attach file (browse inside sidebar) | Correct göz at spelling. |
| Replying to %1 | Use a label form that works with an author name or kendiniz. |
| until full | Use a grammatical suffix after the duration: sonra tam dolu. |
| remaining | Use the complete duration suffix kaldı. |
| Reply to %1… | Use a reply prompt that also works with the fallback contact label. |
| Close audio output | Specify that the action closes the audio-output panel rather than disables audio. |
| Close Wi-Fi networks | Specify that the action closes the Wi-Fi panel rather than disables networking. |

## Intentionally English-identical values

All entries below were individually checked; none is unfinished English prose.

| Exact English key | Reason |
| --- | --- |
| illogical-impulse | Preserved product, project, named layout, protocol or command label. |
| Anime | Anime is the normal Turkish genre term. |
| Dock | Dock is the chosen Turkish UI loanword. |
| GitHub | Preserved product, project, named layout, protocol or command label. |
| Cloudflare WARP (1.1.1.1) | Preserved product, project, named layout, protocol or command label. |
| Bluetooth | Preserved product, project, named layout, protocol or command label. |
| Pomodoro | Pomodoro is the named timer method. |
| AI | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| Cloudflare WARP | Preserved product, project, named layout, protocol or command label. |
| Android | Preserved product, project, named layout, protocol or command label. |
| EasyEffects | Preserved product, project, named layout, protocol or command label. |
| Google Lens | Preserved product, project, named layout, protocol or command label. |
| Normal | Normal is also the Turkish adjective. |
| %1 nits | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| %1s | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| %1s… | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| %1… | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| 0° | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| 50 % APL  ·  %1 nits | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| dd/MM | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| dd.MM | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| Emoji | Emoji is the Turkish media label. |
| Fan: | Fan is also the Turkish hardware term. |
| LCD HDR 1000 | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| LCD HDR 600 | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| MM/dd | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| OLED / QD-OLED | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| VRAM: | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| Web | Web is standard Turkish technical usage. |
| DaVinci Resolve | Preserved product, project, named layout, protocol or command label. |
| DaVinci Resolve Studio | Preserved product, project, named layout, protocol or command label. |
| Master | Preserved product, project, named layout, protocol or command label. |
| Monocle | Preserved product, project, named layout, protocol or command label. |
| OBS Studio | Preserved product, project, named layout, protocol or command label. |
| %1 (%2) | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| Discord | Preserved product, project, named layout, protocol or command label. |
| GitHub Sponsors | Preserved product, project, named layout, protocol or command label. |
| Ko-fi | Preserved product, project, named layout, protocol or command label. |
| Patreon | Preserved product, project, named layout, protocol or command label. |
| CRT | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| updatems | Preserved product, project, named layout, protocol or command label. |
| updatems-system | Preserved product, project, named layout, protocol or command label. |
| macrecovery | Preserved product, project, named layout, protocol or command label. |
| AUR (yay/paru): | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| Flatpak: | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| Snap: | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| <none> | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| GIMP | Preserved product, project, named layout, protocol or command label. |
| Krita | Preserved product, project, named layout, protocol or command label. |
| LibreOffice | Preserved product, project, named layout, protocol or command label. |
| OnlyOffice | Preserved product, project, named layout, protocol or command label. |
| Sunshine | Preserved product, project, named layout, protocol or command label. |
| Moonlight | Preserved product, project, named layout, protocol or command label. |
| Blender | Preserved product, project, named layout, protocol or command label. |
| 15 fps | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| 30 fps | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| WiVRn | Preserved product, project, named layout, protocol or command label. |
| Antigravity CLI — agy update | Preserved product, project, named layout, protocol or command label. |
| Antigravity: | Preserved product, project, named layout, protocol or command label. |
| Ollama | Preserved product, project, named layout, protocol or command label. |
| Plan | Plan is also the Turkish noun for the non-executing assistant mode. |
| UltraCode | Preserved product, project, named layout, protocol or command label. |
| GIF | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| Video | Video is the Turkish media term. |
| Instagram Reel | Preserved product, project, named layout, protocol or command label. |
| %1 B | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| %1 KB | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| %1 MB | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| %1 GB | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| LocalSend | Preserved product, project, named layout, protocol or command label. |
| RAM | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| CPU | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| Ethernet | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| Wi-Fi | Preserved unit, date/number format, acronym, placeholder-only label or updater sentinel. |
| Dynamic Island | Preserved product, project, named layout, protocol or command label. |
| Dwindle | Preserved product, project, named layout, protocol or command label. |

## Shared keys and source issues

- `Play` is shared by a gaming heading and playback controls. Oynat prioritizes the actionable media use; a separate source key would permit Oyun for the heading.
- Shared `From` Başlangıç and `To` Hedef compromise between gradient endpoints and a message recipient. Separate keys would allow a more specific end-color and recipient label.
- Provider subscription Plan is Abonelik; execution Plan is Plan. Window focus uses Odak while Pomodoro Focus follows existing Odaklan. The shared Minimal label En az serves both indicators and reasoning effort.
- `Locked` is a lock-screen state and a shortcut flag; descriptions explicitly preserve operation while locked. `Launch on startup` controls screen locking. `at` is a battery threshold, `Junction:` a GPU hotspot and `Swap` memory swap.
- Privacy settings hide Island alerts and personal details, not phone communications. The streaming option currently suppresses alerts when selected Discord/OBS windows or processes exist, without verifying active streaming; source behavior needs separate attention.
- Sharing-password validation accepts printable ASCII only, while English mentions only accented letters and emoji. This also excludes Turkish-specific letters. The translation preserves the supplied warning; source help should describe the complete restriction.
- Clearing the firewall zone means removing the connection assignment, not deleting the zone. Mount labels identify a drive, not a login user. All boot-menu linux/Snapshots entry names remain literal.
- Legacy git stash list instructions list saved changes rather than restoring them. Newer text supplies git stash show --include-untracked stash@{0} and git stash pop. Literal supplied commands are preserved; reconcile the old source separately.
- Older help uses Ctrl+P to detach; newer help uses Ctrl+D to detach and Ctrl+P to pin. Older provider help uses %2mode PROVIDER while newer execution help uses ask|auto|plan. Each supplied command is preserved.
- One update-advice key contains literal \u2014 text. Its value uses natural Turkish punctuation without modifying the lookup key.
- The old account-deletion dialog concatenates an opening quote, account name and closing question/warning. Turkish preserves a grammatical combined question.
- Short label Polling interval (m) uses the existing Turkish minute abbreviation d; numeric values and explicit units in full strings remain as supplied. Turkish percentages retain the supplied notation so they cannot become accidental Qt placeholders.
- Names, model descriptions and pricing are translated as supplied, not verified as current external product claims.

## Historical reasoning review

Historical review record. Current rules and display names are consolidated in
[TERMINOLOGY.md](../../TERMINOLOGY.md); the English-preservation decisions in this
old report are superseded where the current guide specifies localized labels.

This is the focused follow-up requested after Ukrainian completion. It applies
the owner’s updated terminology, HANDOFF.md, and corrected es_MX example from
`/home/itsjustdroid/Downloads/updated-reasoning`. It supplements the initial
glossary and completion notes; the decisions below supersede older decisions
on these terms. Good existing values outside concrete findings are preserved.

Changes: **47 of 3,221 values**. Source English keys and order are
unchanged. **91 values remain English-identical**; new ones introduced
by this review are explicitly listed below. Other identical entries retain the
individual audit from the original completion notes.

### Review and checks

- Root read the 90 related entries and all changes. Independent fresh-context review read the complete group-3 packet (360 records across four locales), including this locale’s 90 entries. Source context was checked for ambiguous controls.
- The separate 200-key feature sample and all required placeholder/risk reviews from the original locale completion are retained; this follow-up is a focused re-review, not a claim of another full-catalog linguistic review.
- Final structural checks pass for all 3,221 keys: JSON, key order, placeholders, line breaks/joining whitespace, markup/Markdown/code, names, URLs, paths and flags.
- All 47 printf messages pass through the actual sdata/lib/tr.sh formatter with distinct arguments. Expanded name/identifier and slash-command audits pass.
- The reviewer found an ablative-suffix error after the English Dotfiles name. The voiced -dan correction was applied and independently reread; no further concrete issue remained.
- No native-speaker verification or live language preview was performed. Automated checks and independent review do not replace eventual local-user/UI-fit feedback.

### Updated terminology decisions

| English | Final label |
| --- | --- |
| Material cookie | Material cookie |
| Cookie | Cookie |
| Dotfiles | Dotfiles |
| Superpaste | Superpaste |
| Dynamic Island | Dynamic Island |
| Island position | Ada konumu |
| Island style | Ada stili |
| Pills | Kapsüller |
| Hug | Yayılmış |
| Notch | Notch |
| Earbang protection | Ses sıçraması koruması |
| Unmuted | Ses açık |
| Home | Kişisel klasör |
| Swap | Takas alanı |
| Tray | Tepsi |
| System tray | Sistem tepsisi |
| Blur | Bulanıklık |

All seven named palette presets stay in English: Fruit Salad, Neutral, Tonal Spot, Expressive, Rainbow, Fidelity, Monochrome.
Hyprland scratchpad, submap, fake fullscreen and pseudo-tiling stay literal.
Capitalization such as Material Cookie remains where it is already recognizable
English and correct for the locale; no case-only rewrites were made.

### Exact value changes

| Exact English key | Previous committed value | Reviewed value | Reason |
| --- | --- | --- | --- |
| Material cookie | Material Kurabiye | Material cookie | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Fruit Salad | Meyve Salatası | Fruit Salad | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Dotfiles | Nokta dosyaları | Dotfiles | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Neutral | Nötr | Neutral | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Tonal Spot | Tonal Nokta | Tonal Spot | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Expressive | İfadeli | Expressive | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Hug | Kenara yaslı | Yayılmış | Name the edge-spanning style; the earlier wording meant an embrace or attachment to an edge. |
| Superpaste | Süper yapıştır | Superpaste | Preserve the Superpaste command/feature name. |
| Rainbow | Gökkuşağı | Rainbow | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Fidelity | Sadakat | Fidelity | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Earbang protection | Kulak patlama koruması | Ses sıçraması koruması | Name sudden volume-jump protection concisely; this is neither visual flashing nor headphone hardware protection. |
| Cookie clock settings | Kurabiye saat ayarları | Cookie saat ayarları | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Monochrome | Monokrom | Monochrome | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Unmuted | Sessiz değil | Ses açık | Use a natural sound-enabled state instead of an awkward negation. |
| Use old sine wave cookie implementation | Eski sinüs dalgası kurabiye uygulamasını kullan | Eski sinüs dalgası Cookie uygulamasını kullan | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Cookie | Kurabiye | Cookie | Preserve the Cookie/Material cookie shape name instead of translating it as food. |
| Swap | Takas | Takas alanı | All three current resource-panel callers mean disk-backed memory, not a window exchange action. |
| Enter submap | Alt tuş haritasına geç | submap'e geç | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Skip dotfiles | Yapılandırma dosyalarını atla | Dotfiles'ı atla | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Skip the Mainstream dotfiles refresh step (updatems). Dotfiles update only when a new release tag is published upstream; turn this on to manage them manually. | Mainstream yapılandırma dosyalarını yenileme adımını (updatems) atla. Bu dosyalar yalnızca kaynak projede yeni bir sürüm etiketi yayımlandığında güncellenir; bunları elle yönetmek için bu seçeneği açın. | Mainstream dotfiles yenileme adımını (updatems) atla. Dotfiles yalnızca kaynak projede yeni bir sürüm etiketi yayımlandığında güncellenir; bunları elle yönetmek için bu seçeneği açın. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Special (scratchpad) | Özel (karalama alanı) | Özel (scratchpad) | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle fake fullscreen | Sahte tam ekranı aç/kapat | fake fullscreen'i aç/kapat | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle pseudo-tiling | Sözde döşemeyi aç/kapat | pseudo-tiling'i aç/kapat | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle scratchpad | Karalama alanını aç/kapat | scratchpad'i aç/kapat | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| end-4 — Dotfiles | end-4 — Yapılandırma dosyaları | end-4 — Dotfiles | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| How deep the frost goes. Deeper costs more to draw. | Buzlu cam etkisinin derinliği. Derinlik arttıkça çizim maliyeti artar. | Bulanıklığın derinliği. Derinlik arttıkça çizim maliyeti artar. | Use the chosen blur term consistently for blur and frosted surfaces. |
| no frost | buzlu cam yok | bulanıklık yok | Use the chosen blur term consistently for blur and frosted surfaces. |
| No frost behind it | Arkasında buzlu cam olmasın | Arkasında bulanıklık olmasın | Use the chosen blur term consistently for blur and frosted surfaces. |
| Notch | Çentik | Notch | Preserve Notch as the named drawn style, not a physical hardware-cutout noun. |
| Toggle the scratchpad workspace | Karalama çalışma alanını aç/kapat | scratchpad çalışma alanını aç/kapat | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Exit the keybind submap | Tuş ataması alt haritasından çık | Tuş ataması submap'inden çık | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Dotfiles: deferred — the system package update failed, and dotfile releases can depend on packages it would have installed. Re-run the update once the package step succeeds. | Yapılandırma dosyaları: ertelendi, sistem paketi güncellemesi başarısız oldu ve yapılandırma sürümleri kurulacak paketlere bağlı olabilir. Paket adımı başarılı olunca güncellemeyi yeniden çalıştırın. | Dotfiles: ertelendi, sistem paketi güncellemesi başarısız oldu ve dotfiles sürümleri kurulacak paketlere bağlı olabilir. Paket adımı başarılı olunca güncellemeyi yeniden çalıştırın. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Mainstream dotfiles — updatems | Mainstream yapılandırma dosyaları — updatems | Mainstream dotfiles — updatems | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles: skipped (per --skip-dotfiles) | Yapılandırma dosyaları: atlandı (--skip-dotfiles uyarınca) | Dotfiles: atlandı (--skip-dotfiles uyarınca) | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| No dotfiles clone at %s — bootstrapping from %s | %s konumunda yapılandırma deposu kopyası yok, %s kaynağından oluşturuluyor | %s konumunda dotfiles deposu kopyası yok, %s kaynağından oluşturuluyor | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Cloned dotfiles to %s | Yapılandırma dosyaları %s konumuna klonlandı | Dotfiles %s konumuna klonlandı | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles (updatems): | Yapılandırma dosyaları (updatems): | Dotfiles (updatems): | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| The dotfiles clone at %s is damaged. Setting it aside as %s and cloning again. | %s konumundaki yapılandırma deposu kopyası hasarlı. %s adıyla bir kenara alınıp yeniden klonlanıyor. | %s konumundaki dotfiles deposu kopyası hasarlı. %s adıyla bir kenara alınıp yeniden klonlanıyor. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Update finished, but the Mainstream dotfiles did not update. See the Dotfiles line in the summary above. | Güncelleme tamamlandı ancak Mainstream yapılandırma dosyaları güncellenmedi. Yukarıdaki özette Yapılandırma dosyaları satırına bakın. | Güncelleme tamamlandı ancak Mainstream dotfiles güncellenmedi. Yukarıdaki özette Dotfiles satırına bakın. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| [DRY-RUN] The dotfiles clone at %s is damaged; would set it aside as %s and clone again. | [DRY-RUN] %s konumundaki yapılandırma deposu kopyası hasarlı; %s adıyla bir kenara alınır ve yeniden klonlanırdı. | [DRY-RUN] %s konumundaki dotfiles deposu kopyası hasarlı; %s adıyla bir kenara alınır ve yeniden klonlanırdı. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Refreshing /etc/skel from the dotfiles... | /etc/skel yapılandırma dosyalarından yenileniyor... | /etc/skel dotfiles'dan yenileniyor... | Retain the Dotfiles name and use the voiced ablative suffix -dan after the final /z/ of files. |
| Dotfiles: waiting for the desktop update that matches the new Qt. | Yapılandırma dosyaları: yeni Qt ile eşleşen masaüstü güncellemesi bekleniyor. | Dotfiles: yeni Qt ile eşleşen masaüstü güncellemesi bekleniyor. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles: waiting for the system packages, which were held back. | Yapılandırma dosyaları: bekletilen sistem paketleri bekleniyor. | Dotfiles: bekletilen sistem paketleri bekleniyor. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Signed in. The plan models are in the picker now: type /model to choose between Gemini 3.8 Flash (High, Medium, Low) and Gemini 3.1 Pro (High, Low). | Oturum açıldı. Abonelik modelleri artık seçicide: Gemini 3.8 Flash (High, Medium, Low) ile Gemini 3.1 Pro (High, Low) arasında seçim yapmak için /model yazın. | Oturum açıldı. Abonelik modelleri artık seçicide: Gemini 3.8 Flash (Yüksek, Orta, Düşük) ile Gemini 3.1 Pro (Yüksek, Düşük) arasında seçim yapmak için /model yazın. | The parenthesized names are visible effort levels, not literal command arguments. |
| Thinking Level: %1<br>Click to cycle (minimal → low → medium → high → auto) | Düşünme düzeyi: %1<br>Değiştirmek için tıklayın (minimal → low → medium → high → auto) | Düşünme düzeyi: %1<br>Değiştirmek için tıklayın (en az → düşük → orta → yüksek → otomatik) | Translate visible click-cycle effort labels; accepted typed command arguments elsewhere remain literal. |
| Home | Ana Klasör | Kişisel klasör | Name the personal filesystem folder, rather than a start page or generic main folder. |
| Frosted widget backgrounds | Buzlu cam bileşen arka planları | Bulanık bileşen arka planları | Use the chosen blur term consistently for blur and frosted surfaces. |

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
- "end-4 — Dotfiles"
- "Notch"
- "Mainstream dotfiles — updatems"
- "Dotfiles (updatems):"

### Source-confirmed exceptions and remaining limits

- Standalone Swap means memory in Resources.qml, ResourcesPanel.qml and ResourcesPopup.qml. Window-action keys use exchange verbs separately. The offline Spanish interpretation did not have source access.
- at in the automatic-suspend row is a battery percentage. Up %1 is uptime. Home in KeybindCaptureItem.qml is an untranslated X11 keysym and does not share the translated personal-folder call.
- Cookie/Material cookie are shape names; Expressive font is a normal descriptive font role and stays translated. No source strings, commands, accepted arguments, runtime names or configuration keys were changed.
- Longer accurate compounds still need eventual visual fit checks. No explanatory label expansions or new manual wrapping line breaks were added.

## Consolidated display-name pass, 2026-10-31

The current policy and approved terms are consolidated in [TERMINOLOGY.md](../../TERMINOLOGY.md). Earlier English-preservation rules and allowlists above are historical. The current pass changes 12 display values, preserving English keys, command syntax, identifiers and all formatting. These are self-reviewed working choices, not native-speaker-verified.

- "Material cookie" → "Material kurabiyesi"
- "Fruit Salad" → "Meyve salatası"
- "Neutral" → "Nötr"
- "Tonal Spot" → "Ton vurgusu"
- "Expressive" → "İfadeli"
- "Rainbow" → "Gökkuşağı"
- "Fidelity" → "Aslına sadık"
- "Cookie clock settings" → "Kurabiye saat ayarları"
- "Monochrome" → "Tek renk"
- "Use old sine wave cookie implementation" → "Eski sinüs dalgalı Kurabiye uygulamasını kullanın"
- "Cookie" → "Kurabiye"
- "Notch" → "Çentik"

Current intentionally English-identical count: 81. Names, units, literal formats and natural shared vocabulary remain valid; the lower count is not the purpose of this pass.
