# Ukrainian completion notes

Source: all 3,221 English keys, SHA256
`d222d7ae70507e91f555e6bd621ed7b574f7c7f722ff73a8a4826260be17617b`.
Based on mainstream `7d4a4f556` and the owner’s updated 2026-10-28 guidance.

Translates 2,567 previously English-identical values, corrects 84 existing
entries for concrete reasons, and preserves 494 sound prior translations.
All 87 remaining English-identical values are individually accounted for.
English keys, order and runtime syntax are unchanged.

## Validation and independent review

- Every applied batch passed catalog validation. The final catalog passes exact keys/order, placeholders and printf ordering, joining whitespace/newlines, markup, Markdown/code, names, commands, paths, URLs and flags.
- All 47 printf messages pass through the actual sdata/lib/tr.sh formatter using distinct arguments. A separate slash-command audit and English-source digest check pass.
- All 13 catalog-validator regression tests pass.
- Independent fresh-context review read all 1,638 packet pairs and available sample/ambiguity context. All 15 corrections were applied and independently reread against the final catalog, with no further concrete issue (1,653 pair reviews).
- The packet contains 1,638 unique pairs: a deterministic 200-key sample across 83 source buckets, all 321 runtime-placeholder keys, 497 risk candidates, 376 ambiguity candidates, the final 721 entries, all 79 original before/after corrections and all 87 identical entries. Sets overlap.
- Bucket by the first source path: settings/<first component after modules/settings/>, desktop/<first after modules/ii/>, services/AI for /Ai. or /ai/ and services/other otherwise, scripts for sdata/, legacy for missing source, apps/<basename> otherwise. Sort buckets lexically and their keys by raw SHA256 of uk_UA-fresh-context-review-v1 + NUL + key; round-robin to 200.
- Compact UTF-8 sample-key JSON SHA256: `1421b1fb6e3376235379bac13151d746246a3714defda59c0c92385cfa0b672c`. Packet-key JSON SHA256: `7541b18a566d7a1121c69a5f0e6fe0afe5917e483dbc37c85d266404af5d0472`.
- No native-speaker review or live language preview was performed. This is translation with automated validation and a separate review.

## Existing translations corrected

| Exact English key | Before | After | Concrete reason |
| --- | --- | --- | --- |
| Critical warning | Критичні попередження | Критичне попередження | Singular threshold setting, not plural warnings. |
| Load prompt from %1 | Завантажено запит з %1 | Завантажити запит із %1 | This is an actionable file suggestion, not a completed-load report. |
| Pinned on startup | Прикріплено до запуску | Закріплювати під час запуску | The dock is pinned during startup, not before startup. |
| Preferred wallpaper zoom (%) | Бажаний маштаб шпалер (%) | Бажаний масштаб шпалер (%) | Correct misspelling маштаб. |
| Gives the model search capabilities (immediately) | Надає можливість пошуку моделі (негайно) | Надає моделі можливість пошуку (одразу) | The model receives search capability; it is not a search for models. |
| No API key<br>Set it with /key YOUR_API_KEY | Немає API ключа<br>Встановіть його можна командою /key YOUR_API_KEY | Немає ключа API<br>Задайте його командою /key YOUR_API_KEY | Repair the malformed instruction while preserving the actual command. |
| %1 notifications | %1 сповіщень | Сповіщення: %1 | Use a count-neutral label valid for all Ukrainian number forms. |
| Automatically suspends the system when battery is low | Автоматично призупиняє роботу системи, коли батарея розряджається | Автоматично призупиняє систему за низького заряду батареї | Low charge is the condition, not any discharge state. |
| Local Ollama model \| %1 | Локальна модель Оллама \| %1 | Локальна модель Ollama \| %1 | Preserve the literal product name Ollama. |
| 12h am/pm | 12г AM/PM | 12h am/pm | Preserve the exact time-format example and supplied unit. |
| Fruit Salad | Фруктовий салат | Fruit Salad | Preserve the named preset or Dotfiles project name under the updated guidance. |
| Hibernate | Сплячий режим | Гібернація | Distinguish disk-backed hibernation from suspend/sleep. |
| Useless buttons | Безкорисні кнопки | Марні кнопки | Безкорисні means unselfish; use the useless meaning. |
| Dotfiles | Дотфайли | Dotfiles | Preserve the named preset or Dotfiles project name under the updated guidance. |
| Keep system awake | Тримати систему в режимі очікування | Не давати системі заснути | Inhibit sleep, rather than put the system in standby. |
| Unknown Album | Невідомий Альбои | Невідомий альбом | Correct the misspelled album noun. |
| Neutral | Нейтральний | Neutral | Preserve the named preset or Dotfiles project name under the updated guidance. |
| 12h AM/PM | 12г AM/PM | 12h AM/PM | Preserve the exact time-format example and supplied unit. |
| Number show delay when pressing Super (ms) | Затримка відображення номера при натисканні клавіші Super (мс) | Затримка відображення номера при натисканні клавіші Super (ms) | Preserve the literal supplied ms unit. |
| Dock | Лоток | Док | Dock is a dock, not the system tray. |
| Scale (%) | Розмір (%) | Масштаб (%) | This controls scale, not an arbitrary object dimension. |
| Set the tool to use for the model. | Вкажіть інструмент для роботи з моделью | Вкажіть інструмент для роботи моделі. | Correct the malformed model case and name who uses the tool. |
| Disable tools | Вимкнути інструмент | Вимкнути інструменти | Preserve the plural tools meaning. |
| Please charge!<br>Automatic suspend triggers at %1 | Будь ласка, зарядіть! <br>Автоматичне призупинення спрацьовування при %1 | Зарядіть батарею!<br>Автоматичне призупинення за рівня %1 | Repair malformed suspend-threshold warning. |
| Tonal Spot | Тональна пляма | Tonal Spot | Preserve the named preset or Dotfiles project name under the updated guidance. |
| Connection failed. Please inspect manually with the <tt>warp-cli</tt> command | Помилка зєднання. Перевірте самостійно за допомогою команди <tt>warp-cli</tt> | Помилка з’єднання. Перевірте самостійно за допомогою команди <tt>warp-cli</tt> | Restore the missing Ukrainian apostrophe. |
| Expressive | Виразний | Expressive | Preserve the named preset or Dotfiles project name under the updated guidance. |
| Suspend at | Зупиняти на | Призупиняти за рівня | Battery charge threshold triggers system suspension, not a generic stop. |
| Hug | Обійми | Розтягнутий | Hug is an edge-spanning shape option, not an embrace. |
| Rainbow | Веселка | Rainbow | Preserve the named preset or Dotfiles project name under the updated guidance. |
| Automatic suspend | Автоматична зупинка | Автоматичне призупинення | Name system suspension, not a generic stop. |
| Fidelity | Вірність | Fidelity | Preserve the named preset or Dotfiles project name under the updated guidance. |
| Tool set to: %1 | Інструмет вказано: %1 | Інструмент задано: %1 | Correct misspelled інструмент. |
| Could be better if you make a ton of typos,<br>but results can be weird and might not work with acronyms<br>(e.g. "GIMP" might not give you the paint program) | Було б краще, якби ви зробили купу помилок,<br>але результати можуть бути дивними і не працювати з абревіатурами<br>(наприклад, «GIMP» може не вивести програму для малювання). | Може допомогти, якщо ви часто помиляєтеся під час введення,<br>але результати можуть бути дивними й не працювати зі скороченнями<br>(наприклад, "GIMP" може не знайти графічний редактор) | The setting helps tolerate typos; it does not recommend making them. |
| Wallpaper parallax | Обємні шпалери | Паралакс шпалер | Parallax is a movement/depth effect, not just three-dimensional wallpaper. |
| Invalid arguments. Must provide `command`. | Неправельні параметри. Потрібно вказати `command`. | Неправильні аргументи. Потрібно вказати `command`. | Correct misspelled неправильні. |
| Earbang protection | Захист навушників | Захист від стрибків гучності | The feature limits abrupt volume jumps, not protection of headphone hardware. |
| Low warning | Незначні попередження | Попередження про низький заряд | Low refers to the battery charge threshold, not severity of warnings. |
| Show next time | Показати пізніше | Показувати наступного разу | Next time is a future launch, not an unspecified later time. |
| Online via %1 \| %2's model | Онлайн через %1 \| %2's модель | Онлайн через %1 \| Модель %2 | Remove the untranslated English possessive suffix. |
| Such regions could be images or parts of the screen that have some containment.<br>Might not always be accurate.<br>This is done with an image processing algorithm run locally and no AI is used. | Такими областями можуть бути зображення або частини екрана, які мають певні обмеження.<br>Може бути не завжди точним.<br>Це робиться за допомогою алгоритму обробки зображень, запущеного локально, і не використовується ШІ. | Такими областями можуть бути зображення або відокремлені частини екрана.<br>Результат не завжди точний.<br>Використовується локальний алгоритм обробки зображень, без ШІ. | The source refers to bounded visual regions, not restrictions. |
| Unknown | Невідмий | Невідомо | Correct the misspelled unknown state. |
| Polling interval (ms) | Інтервал між опитуваннями (мс) | Інтервал між опитуваннями (ms) | Preserve the literal supplied ms unit. |
| 24h | 24г | 24h | Preserve the exact time-format example and supplied unit. |
| Bar style | Стиль заголовку | Стиль панелі | Bar refers to the desktop bar, not a title bar. |
| Current model: %1<br>Set it with %2model MODEL | Поточна модель: %1<br>Задати її за допомогою %2model МОДЕЛЬ | Поточна модель: %1<br>Задайте її командою %2model MODEL | Restore the literal MODEL metavariable. |
| Invalid model. Supported: <br>``` | Неправельна модель. Підтримується: <br>``` | Неправильна модель. Підтримуються: <br>``` | Correct misspelled неправильна and the supported-list grammar. |
| Distro | Дистрибютив | Дистрибутив | Correct misspelled дистрибутив. |
| %1   •   %2 tasks | %1   •   %2 завдань | %1   •   Завдання: %2 | Use a count-neutral tasks label for arbitrary numbers. |
| Invalid tool. Supported tools:<br>- %1 | Неправельний інструмент. Підтримуються:<br>- %1 | Неправильний інструмент. Підтримуються:<br>- %1 | Correct misspelled неправильний. |
| Temperature<br>Change with /temp VALUE | Температура<br>Змінити можна командою /temp ЗНАЧЕННЯ | Температура<br>Змінити командою /temp VALUE | Restore the literal VALUE metavariable. |
| Night Light \| Right-click to toggle Auto mode | Нічне світло \| ПКМ щоб увімкнути автоматичний режим | Нічне світло \| Клацніть правою кнопкою, щоб перемкнути автоматичний режим | The right-click action toggles Auto, rather than only enabling it. |
| Columns | Стовбці | Стовпці | Correct the column noun стовпці. |
| For storing API keys and other sensitive information | Для зберігання API ключів та іншої конфіденційної інформація | Для зберігання ключів API та іншої конфіденційної інформації | Correct the case of інформації. |
| Load chat from %1 | Завантажено чат з %1 | Завантажити чат із %1 | Action suggestion rather than completed-loading message. |
| Current API endpoint: %1<br>Set it with %2mode PROVIDER | Поточна кінцева точка API: %1<br>Встановіть її за допомогою %2mode ПРОВАЙТЕР | Поточна кінцева точка API: %1<br>Задайте її командою %2mode PROVIDER | Restore the literal PROVIDER metavariable. |
| Drag or click a region • LMB: Copy • RMB: Edit | Перетягніть або клацніть регіон - LMB: Копіювати - RMB: Редагувати | Перетягніть або клацніть область • LMB: Копіювати • RMB: Редагувати | Preserve functional bullet separators and region wording. |
| %1 characters | %1 символів | Символів: %1 | Use a count-neutral characters label for arbitrary counts. |
| Monochrome | Монохромний | Monochrome | Preserve the named preset or Dotfiles project name under the updated guidance. |
| Switched to search mode. Continue with the user's request. | Перейшли в режим пошуку. Продовження пошуку за запитом користувача. | Перехід у режим пошуку виконано. Продовжуйте виконання запиту користувача. | Continue the user’s request, not necessarily a search-only subtask. |
| Usage: %1load CHAT_NAME | Виокристання: %1load CHAT_NAME | Використання: %1load CHAT_NAME | Correct misspelled використання. |
| No API key set for %1 | Немає вказаного API ключач для %1 | Не задано ключ API для %1 | Correct malformed key wording. |
| %1 queries pending | %1 запитів на розгляді | Запитів у черзі: %1 | Use a count-neutral label for queued requests. |
| Please charge!<br>Automatic suspend triggers at %1% | Будь ласка, зарядіть! <br>Автоматичне призупинення спрацьовування при %1% | Зарядіть батарею!<br>Автоматичне призупинення за рівня %1% | Repair malformed suspend-threshold warning. |
| Signed in. The plan models are in the picker now: type /model to choose between Gemini 3.8 Flash (High, Medium, Low) and Gemini 3.1 Pro (High, Low). | Вхід виконано. Моделі плану тепер у списку вибору: введіть /model, щоб обрати між Gemini 3.8 Flash (High, Medium, Low) та Gemini 3.1 Pro (High, Low). | Вхід виконано. Моделі за підпискою тепер доступні: введіть /model, щоб вибрати Gemini 3.8 Flash (високий, середній, низький) або Gemini 3.1 Pro (високий, низький). | Plan means subscription, and the parenthesized effort names are UI labels. |
| Set thinking level (reasoning effort). Values: minimal, low, medium, high, auto. Replaces deprecated thinking budget. | Встановити рівень міркувань (глибину роздумів). Значення: minimal, low, medium, high, auto. Замінює застарілий thinking budget. | Встановити рівень міркувань (інтенсивність). Значення: minimal, low, medium, high, auto. Замінює застарілий бюджет міркувань. | Translate residual thinking-budget prose; keep accepted argument values literal. |
| Signed in. Gemini Flash and Gemini Pro are in the picker now. Adjust thinking level with the reasoning pill or /think. | Вхід виконано. Gemini Flash та Gemini Pro тепер у списку вибору. Змінюйте рівень міркувань за допомогою кнопки або /think. | Вхід виконано. Gemini Flash та Gemini Pro тепер у списку вибору. Змінюйте рівень міркувань за допомогою капсули міркувань або /think. | Identify the capsule-shaped reasoning control as specified in the source. |
| Thinking Level: %1<br>Click to cycle (minimal → low → medium → high → auto) | Рівень міркувань: %1<br>Натисніть для перемикання (minimal → low → medium → high → auto) | Рівень міркувань: %1<br>Натисніть для перемикання (мінімальний → низький → середній → високий → авто) | Translate click-cycle UI labels; this is not typed command syntax. |
| Signed in. Gemini Flash and Gemini Pro are in the picker now. Adjust thinking level with /think. | Увійшли. Gemini Flash та Gemini Pro тепер доступні у виборі. Налаштуйте рівень мислення за допомогою /think. | Вхід виконано. Gemini Flash та Gemini Pro тепер доступні у виборі. Налаштуйте рівень міркувань за допомогою /think. | Use the established reasoning term міркування. |
| Attach file (browse inside sidebar) | Прикріпити файл (огляд у боковій панелі) | Прикріпити файл (огляд у бічній панелі) | Use бічна панель consistently across the shared sidebar controls; detach uses відокремити. |
| Ctrl+D to attach sidebar | Ctrl+D: приєднати бокову панель | Ctrl+D: приєднати бічну панель | Use бічна панель consistently across the shared sidebar controls; detach uses відокремити. |
| Ctrl+D to detach sidebar | Ctrl+D: від'єднати бокову панель | Ctrl+D: відокремити бічну панель | Use бічна панель consistently across the shared sidebar controls; detach uses відокремити. |
| Ctrl+O to collapse sidebar | Ctrl+O: згорнути бокову панель | Ctrl+O: згорнути бічну панель | Use бічна панель consistently across the shared sidebar controls; detach uses відокремити. |
| Ctrl+O to expand sidebar | Ctrl+O: розгорнути бокову панель | Ctrl+O: розгорнути бічну панель | Use бічна панель consistently across the shared sidebar controls; detach uses відокремити. |
| Ctrl+P to pin sidebar | Ctrl+P: закріпити бокову панель | Ctrl+P: закріпити бічну панель | Use бічна панель consistently across the shared sidebar controls; detach uses відокремити. |
| Ctrl+P to unpin sidebar | Ctrl+P: відкріпити бокову панель | Ctrl+P: відкріпити бічну панель | Use бічна панель consistently across the shared sidebar controls; detach uses відокремити. |
| Open the left sidebar pinned, reserving screen space for it | Відкривати ліву бокову панель закріпленою, резервуючи для неї місце на екрані | Відкривати ліву бічну панель закріпленою, резервуючи для неї місце на екрані | Use бічна панель consistently across the shared sidebar controls; detach uses відокремити. |
| Refresh local Ollama models | Оновити локальні моделі Ollama | Оновити список локальних моделей Ollama | This refreshes the installed-model list, not the model files. |
| Sidebar controls: | Керування боковою панеллю: | Керування бічною панеллю: | Use бічна панель consistently across the shared sidebar controls; detach uses відокремити. |
| Stop and send voice input (Right click or Esc to cancel) | Зупинити й надіслати голосовий ввід (ПКМ або Esc для скасування) | Зупинити й надіслати розпізнаний текст (ПКМ або Esc для скасування) | AI voice capture sends recognized text, unlike phone audio voice notes. |
| [[ Command timed out after %1 s ]] | [[ Час очікування команди вичерпано через %1 с ]] | [[ Час очікування команди вичерпано через %1 s ]] | Preserve the supplied seconds unit. |
| Only local models are allowed right now. To use online models, set AI to Yes in Settings > Interface > Left Sidebar. | Зараз дозволено лише локальні моделі. Щоб використовувати онлайн-моделі, виберіть для ШІ значення «Так» у розділі Параметри > Інтерфейс > Left Sidebar. | Зараз дозволено лише локальні моделі. Щоб використовувати онлайн-моделі, виберіть для ШІ значення «Так» у розділі Параметри > Інтерфейс > Ліва бічна панель. | Translate the residual settings breadcrumb to match its actual label. |
| Updated %1 min ago | Оновлено %1 хв тому | Оновлено %1 min тому | Preserve the supplied min unit. |
| Updated %1 h ago | Оновлено %1 год тому | Оновлено %1 h тому | Preserve the supplied h unit. |

## Independent-review correction log

| Exact English key | Final value | Reason |
| --- | --- | --- |
| at | за рівня | Battery charge threshold, not a time of day (PowerConfig.qml:434). |
| Number show delay when pressing Super (ms) | Затримка відображення номера при натисканні клавіші Super (ms) | Preserve the literal ms unit. |
| Polling interval (ms) | Інтервал між опитуваннями (ms) | Preserve the literal ms unit. |
| Clicking Apply will save these values to monitors.conf<br>and reload Hyprland immediately. | Кнопка «Застосувати» збереже ці значення в monitors.conf<br>й негайно перезавантажить конфігурацію Hyprland. | The action executes hyprctl reload, not a compositor restart (DisplayConfig.qml:1274). |
| Clicking Apply will save these values to monitors.lua<br>and reload Hyprland immediately. | Кнопка «Застосувати» збереже ці значення в monitors.lua<br>й негайно перезавантажить конфігурацію Hyprland. | The calibration action reloads configuration through the same implementation. |
| Login image updated. At %1 pixels it may look soft on the login screen. | Зображення входу оновлено. За розміру %1 px воно може виглядати нечітким на екрані входу. | The caller accepts arbitrary dimensions 1–511; px avoids wrong noun plurals (AccountsConfig.qml:239). |
| Refresh local Ollama models | Оновити список локальних моделей Ollama | The button refreshes the installed-model list (ModelSelectionSheet.qml:261, Ai.qml:1473). |
| Updated %1 min ago | Оновлено %1 min тому | Preserve the supplied min unit. |
| Updated %1 h ago | Оновлено %1 h тому | Preserve the supplied h unit. |
| Drop files anywhere to send to %1 | Перетягніть файли будь-куди для надсилання. Одержувач: %1 | A neutral recipient label works with the fallback ваш телефон and arbitrary runtime names (PhoneConversationList.qml:287). |
| yourself | собі | Use the self-reply form собі in the combined caption. |
| Replying to %1 | Відповідь (%1) | Neutral parenthesized author caption accepts self, names and generic message fallback (PhoneThreadView.qml:1834–1864). |
| Connected to %1 | З’єднано: %1 | A neutral status label works with the fallback телефон (PhoneTab.qml:436). |
| Reply to %1… | Відповідь: %1… | A neutral reply label works with privacy fallback контакт (PhonePanel.qml:588). |
| No output | Немає аудіовиходу | The missing object is Audio.sink, not a generic exit (SystemPanel.qml:108). |

## Intentionally English-identical entries

| Exact English key | Reason |
| --- | --- |
| Material cookie | Preserved product, provider, project, command, layout or named palette/shape. |
| 12h am/pm | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| Fruit Salad | Preserved product, provider, project, command, layout or named palette/shape. |
| illogical-impulse | Preserved product, provider, project, command, layout or named palette/shape. |
| Dotfiles | Preserved product, provider, project, command, layout or named palette/shape. |
| Neutral | Preserved product, provider, project, command, layout or named palette/shape. |
| 12h AM/PM | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| Tonal Spot | Preserved product, provider, project, command, layout or named palette/shape. |
| Expressive | Preserved product, provider, project, command, layout or named palette/shape. |
| Superpaste | Preserved product, provider, project, command, layout or named palette/shape. |
| Rainbow | Preserved product, provider, project, command, layout or named palette/shape. |
| GitHub | Preserved product, provider, project, command, layout or named palette/shape. |
| Fidelity | Preserved product, provider, project, command, layout or named palette/shape. |
| Cloudflare WARP (1.1.1.1) | Preserved product, provider, project, command, layout or named palette/shape. |
| 24h | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| Bluetooth | Preserved product, provider, project, command, layout or named palette/shape. |
| Pomodoro | Preserved product, provider, project, command, layout or named palette/shape. |
| Cloudflare WARP | Preserved product, provider, project, command, layout or named palette/shape. |
| Monochrome | Preserved product, provider, project, command, layout or named palette/shape. |
| Android | Preserved product, provider, project, command, layout or named palette/shape. |
| EasyEffects | Preserved product, provider, project, command, layout or named palette/shape. |
| Google Lens | Preserved product, provider, project, command, layout or named palette/shape. |
| %1 nits | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| %1s | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| %1s… | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| %1… | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| 0° | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| 50 % APL  ·  %1 nits | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| Cookie | Preserved product, provider, project, command, layout or named palette/shape. |
| dd/MM | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| dd.MM | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| LCD HDR 1000 | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| LCD HDR 600 | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| MM/dd | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| OLED / QD-OLED | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| VRAM: | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| DaVinci Resolve | Preserved product, provider, project, command, layout or named palette/shape. |
| DaVinci Resolve Studio | Preserved product, provider, project, command, layout or named palette/shape. |
| Master | Preserved product, provider, project, command, layout or named palette/shape. |
| Monocle | Preserved product, provider, project, command, layout or named palette/shape. |
| OBS Studio | Preserved product, provider, project, command, layout or named palette/shape. |
| end-4 — Dotfiles | Preserved product, provider, project, command, layout or named palette/shape. |
| %1 (%2) | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
|  min | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| Notch | Preserved product, provider, project, command, layout or named palette/shape. |
| Discord | Preserved product, provider, project, command, layout or named palette/shape. |
| min | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| GitHub Sponsors | Preserved product, provider, project, command, layout or named palette/shape. |
| Ko-fi | Preserved product, provider, project, command, layout or named palette/shape. |
| Patreon | Preserved product, provider, project, command, layout or named palette/shape. |
| CRT | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| ok | Preserved product, provider, project, command, layout or named palette/shape. |
| updatems | Preserved product, provider, project, command, layout or named palette/shape. |
| updatems-system | Preserved product, provider, project, command, layout or named palette/shape. |
| macrecovery | Preserved product, provider, project, command, layout or named palette/shape. |
| AUR (yay/paru): | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| Flatpak: | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| Snap: | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| Dotfiles (updatems): | Preserved product, provider, project, command, layout or named palette/shape. |
| <none> | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| GIMP | Preserved product, provider, project, command, layout or named palette/shape. |
| Krita | Preserved product, provider, project, command, layout or named palette/shape. |
| LibreOffice | Preserved product, provider, project, command, layout or named palette/shape. |
| OnlyOffice | Preserved product, provider, project, command, layout or named palette/shape. |
| Sunshine | Preserved product, provider, project, command, layout or named palette/shape. |
| Moonlight | Preserved product, provider, project, command, layout or named palette/shape. |
| Blender | Preserved product, provider, project, command, layout or named palette/shape. |
| 15 fps | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| 30 fps | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| WiVRn | Preserved product, provider, project, command, layout or named palette/shape. |
| Antigravity CLI — agy update | Preserved product, provider, project, command, layout or named palette/shape. |
| Antigravity: | Preserved product, provider, project, command, layout or named palette/shape. |
| Ollama | Preserved product, provider, project, command, layout or named palette/shape. |
| UltraCode | Preserved product, provider, project, command, layout or named palette/shape. |
| GIF | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| Instagram Reel | Preserved product, provider, project, command, layout or named palette/shape. |
| %1 B | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| %1 KB | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| %1 MB | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| %1 GB | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| LocalSend | Preserved product, provider, project, command, layout or named palette/shape. |
| RAM | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| CPU | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| Ethernet | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| Wi-Fi | Unit, numeric/date/time format, acronym, placeholder-only label or literal updater sentinel. |
| Dynamic Island | Preserved product, provider, project, command, layout or named palette/shape. |
| Dwindle | Preserved product, provider, project, command, layout or named palette/shape. |

## Source ambiguities, terminology and limits

- Updated names stay recognizable: Dotfiles/dotfiles, Material cookie/Cookie, all seven named Material You palettes, Superpaste, scratchpad, submap, fake fullscreen, pseudo-tiling, Notch and the full Dynamic Island name. Short Island compounds use острів. Pills use капсула. Hug uses розтягнутий, distinct from Notch’s edge-flush shape.
- Workspace stays the existing простір. Dock is док and system tray is системний лоток. Sidebar consistently uses бічна панель. Keyboard layouts are розкладки; window layouts are компонування. Blur/frost uses розмиття throughout, not cold-temperature wording.
- Reasoning budget keeps established computing-budget usage, not a monetary price. Plan in provider descriptions means підписка; execution Plan is план. Visible effort levels translate; literal typed command values stay English.
- Standalone Swap is memory in all three current resource callers, so it is своп. The supplied offline Spanish example inferred a window action without caller access; actual window-exchange keys use поміняти місцями.
- Standalone Locked serves both lock-screen status and a bind type. Заблоковано suits the state; combined bind labels describe working while locked. Separate source keys would allow fully explicit standalone labels. Launch on startup actually controls lock.launchOnStartup, so it describes locking.
- Focus here is used by Pomodoro timers and translates as зосередження. Window-focus phrases name фокус separately. Play serves playback and a gaming welcome heading; відтворити prioritizes playback, and the heading needs its own source key.
- Generic counted strings use count-neutral label constructions, or invariant abbreviations such as зобр. after an externally supplied image count. The lookup has no plural API. Separate existing singular/plural keys remain separate.
- Home is домашня тека. Personal secrets are stored in a в’язка ключів, whereas package-signing trust uses сховище ключів. Shared folders, LocalSend copies and phone attachments remain separate operations.
- Voice input sends recognized text; phone voice notes send recordings. Stream privacy hides Island presentation and does not stop phone calls/messages. Current source checks Discord/OBS presence, not an actual active stream.
- Sharing-password source warns about accents and emoji, but its validator permits printable ASCII only; the English should explain the full restriction. Clearing a firewall zone removes its assignment to the connection, not the zone definition.
- The old git stash list advice lists stashes rather than restoring them; the newer message supplies explicit show/pop commands. Commands were not silently corrected. Old and new sidebar shortcuts and provider-mode arguments are preserved as supplied.
- The legacy update-advice key contains literal \u2014. The key is unchanged; the translated value uses ordinary punctuation. Snapshot boot labels Snapshots/linux remain literal.
- Weather visibility is distance; Free means available resources; Up %1 is elapsed uptime; Junction is GPU hotspot. Close audio/Wi-Fi labels close their panels, not the services.
- External country names are injected from iso3166.tab, not translated here. Model capability/pricing claims are translated as supplied, without external verification. Longer compound controls and tooltips still need eventual UI-fit review in the running shell; no manual wrapping line breaks were added.

## Consolidated display-name pass, 2026-10-31

The current policy and approved terms are consolidated in [TERMINOLOGY.md](../../TERMINOLOGY.md). Earlier English-preservation rules and allowlists above are historical. The current pass changes 12 display values, preserving English keys, command syntax, identifiers and all formatting. These are self-reviewed working choices, not native-speaker-verified.

- "Material cookie" → "Печиво Material"
- "Fruit Salad" → "Фруктовий салат"
- "Neutral" → "Нейтральна"
- "Tonal Spot" → "Тональний акцент"
- "Expressive" → "Виразна"
- "Rainbow" → "Веселка"
- "Fidelity" → "Точність кольору"
- "Cookie clock settings" → "Параметри годинника «Печиво»"
- "Monochrome" → "Монохромна"
- "Use old sine wave cookie implementation" → "Використовувати стару реалізацію «Печива» на синусоїді"
- "Cookie" → "Печиво"
- "Notch" → "Виріз"

Current intentionally English-identical count: 77. Names, units, literal formats and natural shared vocabulary remain valid; the lower count is not the purpose of this pass.
