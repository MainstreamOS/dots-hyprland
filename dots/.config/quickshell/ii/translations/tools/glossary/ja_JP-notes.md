# Japanese completion notes

Catalog: `ja_JP.json`. Source: all 3,221 keys of `en_US.json`, based on mainstream `273873021`.

Completed 2,502 previously English-identical values. Corrected 24 existing translations for concrete defects; preserved the other 628. All 67 remaining English-identical entries are intentional and listed individually below. Keys, order, placeholders and source formatting are unchanged.

## Validation and review

- Each batch passed structural validation before writing. `tools/catalog-qa.py ja_JP` reports zero errors: exact keys, JSON uniqueness, placeholders and printf order, real line breaks, joining whitespace, markup/Markdown/backticks, protected names, numeric values, URLs, paths, command flags and config filenames.
- All 47 printf messages pass through the actual `sdata/lib/tr.sh` with distinct arguments. Exact key order and a separate slash-command audit pass. The slash-command audit uses ASCII identifier boundaries so a command followed immediately by Japanese text is still recognized without accepting a changed command name.
- All 13 validator regression tests pass. The six previously completed catalogs also still pass structural validation.
- A fresh-context review covered 1,157 unique initial entries: 200 feature-sampled keys across 83 source buckets, all 321 actual runtime-placeholder keys, 497 warning/destructive/access/update/recovery candidates, 376 terminology/ambiguity extras, all 67 English-identical entries and the seven corrections made before that review. Sets overlap. The percent-encoded Zerochan URL was checked separately and remains exact.
- Final corrections and consistency changes were reread in a 74-entry patch. Combined initial and patch coverage is 1,174 unique keys. Root additionally read all 652 baseline translations and audited glossary usage, English-identical values and source contexts.
- Sample selection groups by first candidate source: settings/<first component after modules/settings/>, desktop/<first after modules/ii/>, services/AI for /Ai. or /ai/, otherwise services/other; sdata/ becomes scripts; no source becomes legacy; other paths use apps/<basename>. Sort buckets lexically and keys within each bucket by raw SHA256 of `ja_JP-fresh-context-review-v1` + NUL + key, then take round-robin by bucket depth until 200.
- Compact UTF-8 JSON serialization (`ensure_ascii=False`, separators comma and colon) of sample keys hashes to `41f79395779ba100d6bb086a8fb05f2d1bb07520fb9d8417c923c7abfd68d89f`. Initial reviewed keys in catalog order hash to `674a376b874c8a08405b807b7e4274ee5efe17803ee5797e6fc02be9b5fc7da6`. Combined final reviewed key set in catalog order hashes to `023ba9e07009f7f7f177d61d7fc60da217f5911593980ebb7692718a926cb9ae`.
- Reused sound existing terms: キー割り当て, ピン留め, ナイトライト, ボリュームミキサー and 概要. New window-focus text uses フォーカス; Pomodoro keeps 集中. Technical suspend labels use サスペンド; existing user-facing sleep wording is retained where sound.
- No native-speaker review or live language preview was performed. These are translations with automated validation and a separate review.

## Existing translations corrected

| Exact English key | Reason |
| --- | --- |
| Reboot to firmware settings | Correct the reboot destination: enter firmware setup, rather than reboot within it. |
| No | Use the negative answer instead of Hide; shared with enable controls and confirmations. |
| Usage: %1tool TOOL_NAME | Restore the literal TOOL_NAME command metavariable. |
| Waifus only \| Excellent quality, limited quantity | Restore the female anime-character scope omitted by the generic character label. |
| Hug | Describe the edge-hugging shape rather than pinning behavior. |
| Could be better if you make a ton of typos,<br>but results can be weird and might not work with acronyms<br>(e.g. "GIMP" might not give you the paint program) | Restore the actual source line breaks and preserve the GIMP example and uncertainty. |
| Temperature<br>Change with /temp VALUE | Restore the literal VALUE command metavariable. |
| Yes | Use the affirmative answer instead of Show, including the account deletion confirmation. |
| To set an API key, pass it with the %4 command<br><br>To view the key, pass "get" with the command<br/><br><br>### For %1:<br><br>**Link**: %2<br><br>%3 | Keep ASCII quotes around the literal get command argument. |
| When enabled keeps the content of the right sidebar loaded to reduce the delay when opening,<br>at the cost of around 15MB of consistent RAM usage. Delay significance depends on your system's performance.<br>Using a custom kernel like linux-cachyos might help | Restore actual source line breaks and the exact RAM acronym, preserving the memory/performance caveats. |
| Might look ass. Unsupported. | State unsupported status rather than merely not recommended. |
| Usage: %1save CHAT_NAME | Restore the literal CHAT_NAME command metavariable. |
| Usage: %1load CHAT_NAME | Restore the literal CHAT_NAME command metavariable. |
| Please charge!<br>Automatic suspend triggers at %1% | Place the percent sign directly after the battery threshold placeholder. |
| Set thinking level (reasoning effort). Values: minimal, low, medium, high, auto. Replaces deprecated thinking budget. | Use the existing reasoning-effort term, translate remaining thinking-budget prose and distinguish deprecated from removed. |
| Signed in. Gemini Flash and Gemini Pro are in the picker now. Adjust thinking level with the reasoning pill or /think. | Name the reasoning capsule UI rather than a medicinal pill. |
| Minimal — Fast, concise answers | Translate the display-only effort level and match the existing Minimal label; typed lowercase arguments stay literal. |
| Low — Everyday tasks & quick coding | Translate the display-only effort level and match the existing Low label; typed lowercase arguments stay literal. |
| Medium — Balanced reasoning | Translate the display-only effort level and match the existing Medium label; typed lowercase arguments stay literal. |
| High — Deep thinking & complex math | Translate the display-only effort level and match the existing High label; typed lowercase arguments stay literal. |
| %1 requires approval to continue | Require approval for the named tool/action, rather than approval granted by it. |
| Commands: /model <name> · /mode [ask\|auto\|plan] | Restore the literal <name> command metavariable. |
| This approval is out of date, so nothing was run. | Describe invalid/stale approval without inventing a time-based expiration. |
| Only local models are allowed right now. To use online models, set AI to Yes in Settings > Interface > Left Sidebar. | Translate the Left Sidebar breadcrumb and match the corrected affirmative option. |

## Intentionally English-identical values

Each entry was checked individually. There is no remaining untranslated English UI prose.

| Exact English key | Reason |
| --- | --- |
| OK | Standard Japanese UI confirmation label OK. |
| illogical-impulse | Preserved product, project, named layout, command label or named visual style. |
| Superpaste | Preserved product, project, named layout, command label or named visual style. |
| GitHub | Preserved product, project, named layout, command label or named visual style. |
| Cloudflare WARP (1.1.1.1) | Preserved product, project, named layout, command label or named visual style. |
| Bluetooth | Preserved product, project, named layout, command label or named visual style. |
| AI | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| Cloudflare WARP | Preserved product, project, named layout, command label or named visual style. |
| Android | Preserved product, project, named layout, command label or named visual style. |
| EasyEffects | Preserved product, project, named layout, command label or named visual style. |
| Google Lens | Preserved product, project, named layout, command label or named visual style. |
| %1 nits | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| %1s | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| %1s… | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| %1… | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| 0° | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| 50 % APL  ·  %1 nits | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| Cookie | Preserved product, project, named layout, command label or named visual style. |
| dd/MM | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| dd.MM | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| LCD HDR 1000 | Preserved product, project, named layout, command label or named visual style. |
| LCD HDR 600 | Preserved product, project, named layout, command label or named visual style. |
| MM/dd | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| OLED / QD-OLED | Preserved product, project, named layout, command label or named visual style. |
| VRAM: | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| DaVinci Resolve | Preserved product, project, named layout, command label or named visual style. |
| DaVinci Resolve Studio | Preserved product, project, named layout, command label or named visual style. |
| Master | Preserved product, project, named layout, command label or named visual style. |
| Monocle | Preserved product, project, named layout, command label or named visual style. |
| OBS Studio | Preserved product, project, named layout, command label or named visual style. |
| %1 (%2) | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| Discord | Preserved product, project, named layout, command label or named visual style. |
| GitHub Sponsors | Preserved product, project, named layout, command label or named visual style. |
| Ko-fi | Preserved product, project, named layout, command label or named visual style. |
| Patreon | Preserved product, project, named layout, command label or named visual style. |
| CRT | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| updatems | Preserved product, project, named layout, command label or named visual style. |
| updatems-system | Preserved product, project, named layout, command label or named visual style. |
| macrecovery | Preserved product, project, named layout, command label or named visual style. |
| Flatpak: | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| Snap: | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| <none> | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| GIMP | Preserved product, project, named layout, command label or named visual style. |
| Krita | Preserved product, project, named layout, command label or named visual style. |
| LibreOffice | Preserved product, project, named layout, command label or named visual style. |
| OnlyOffice | Preserved product, project, named layout, command label or named visual style. |
| Sunshine | Preserved product, project, named layout, command label or named visual style. |
| Moonlight | Preserved product, project, named layout, command label or named visual style. |
| Blender | Preserved product, project, named layout, command label or named visual style. |
| 15 fps | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| 30 fps | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| WiVRn | Preserved product, project, named layout, command label or named visual style. |
| Antigravity CLI — agy update | Preserved product, project, named layout, command label or named visual style. |
| Ollama | Preserved product, project, named layout, command label or named visual style. |
| UltraCode | Preserved product, project, named layout, command label or named visual style. |
| GIF | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| %1 B | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| %1 KB | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| %1 MB | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| %1 GB | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| LocalSend | Preserved product, project, named layout, command label or named visual style. |
| RAM | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| CPU | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| Ethernet | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| Wi-Fi | Unit, date/number format, acronym, placeholder-only label or conventional updater sentinel. |
| Dynamic Island | Preserved product, project, named layout, command label or named visual style. |
| Dwindle | Preserved product, project, named layout, command label or named visual style. |

## Shared-key decisions and source issues

- `Play` is shared by the gaming category heading and media playback controls. 再生 prioritizes the actionable controls; a dedicated gaming-heading key would allow ゲーム.
- `From` 元 and `To` 先 are compact compromises for gradient endpoints and the shared message-recipient label. Separate context keys would allow 始点/終点 and 宛先. No context markers were invented.
- `Overview` retains the existing 概要 term. `To Do`/`To do` retain やること, while `Tasks` uses タスク. Fixed colors/dimensions use 固定; interactive pinning uses ピン留め.
- `Launch on startup` controls `lock.launchOnStartup`, so it says 起動時にロック. Junction is the GPU hotspot; Swap is memory swap; Call is a history noun; Calling is outgoing. The full-app-list launcher option applies when overview is disabled, not to all application windows.
- The streaming-privacy source says while streaming but suppresses Island phone alerts whenever selected Discord/OBS windows or processes exist. It does not verify an active stream. Translation preserves the presentation-only scope; resolve the source behavior separately.
- The sharing password source mentions accented letters and emoji, but FileSharing.qml accepts printable ASCII only, also excluding Japanese text. Translation preserves the supplied restriction; the English needs to state the full restriction.
- The legacy `Local edits stashed — restore with: cd ... && git stash list` instruction lists stashes rather than restoring them. The newer key supplies `git stash show --include-untracked stash@{0}` and `git stash pop`. Both literal instructions were preserved; reconcile the older source separately.
- Older help says Ctrl+P detaches the sidebar; newer help uses Ctrl+D for detach and Ctrl+P for pin. Preserve each supplied shortcut; reconcile source instructions separately.
- The historical provider tooltip uses `%2mode PROVIDER`, whereas newer execution-mode help uses `ask|auto|plan`. Supplied syntax is preserved.
- One update-advice key contains literal `\u2014` text. Its Japanese value uses natural punctuation; the lookup key remains exact. Boot entries `Snapshots` and `linux`, command metavariables, executables, paths and flags are kept literal.
- Model descriptions and pricing instructions were translated as provided, without externally verifying current product claims.

## Historical reasoning review

Historical review record. Current rules and display names are consolidated in
[TERMINOLOGY.md](../../TERMINOLOGY.md); the English-preservation decisions in this
old report are superseded where the current guide specifies localized labels.

This is the focused follow-up requested after Ukrainian completion. It applies
the owner’s updated terminology, HANDOFF.md, and corrected es_MX example from
`/home/itsjustdroid/Downloads/updated-reasoning`. It supplements the initial
glossary and completion notes; the decisions below supersede older decisions
on these terms. Good existing values outside concrete findings are preserved.

Changes: **41 of 3,221 values**. Source English keys and order are
unchanged. **77 values remain English-identical**; new ones introduced
by this review are explicitly listed below. Other identical entries retain the
individual audit from the original completion notes.

### Review and checks

- Root read the 90 related entries and all changes. Independent fresh-context review read the complete group-2 packet (360 records across four locales), including this locale’s 90 entries. Source context was checked for ambiguous controls.
- The separate 200-key feature sample and all required placeholder/risk reviews from the original locale completion are retained; this follow-up is a focused re-review, not a claim of another full-catalog linguistic review.
- Final structural checks pass for all 3,221 keys: JSON, key order, placeholders, line breaks/joining whitespace, markup/Markdown/code, names, URLs, paths and flags.
- All 47 printf messages pass through the actual sdata/lib/tr.sh formatter with distinct arguments. Expanded name/identifier and slash-command audits pass.
- The reviewer found an unchanged xray label that reversed the sampled surface. The direct-wallpaper wording was applied and independently reread; no further concrete issue remained.
- No native-speaker verification or live language preview was performed. Automated checks and independent review do not replace eventual local-user/UI-fit feedback.

### Updated terminology decisions

| English | Final label |
| --- | --- |
| Material cookie | Material Cookie |
| Cookie | Cookie |
| Dotfiles | Dotfiles |
| Superpaste | Superpaste |
| Dynamic Island | Dynamic Island |
| Island position | アイランドの位置 |
| Island style | アイランドのスタイル |
| Pills | カプセル |
| Hug | 引き伸ばし |
| Notch | Notch |
| Earbang protection | 音量急上昇防止 |
| Unmuted | ミュート解除 |
| Home | ホーム |
| Swap | スワップ |
| Tray | トレイ |
| System tray | システムトレイ |
| Blur | ぼかし |

All seven named palette presets stay in English: Fruit Salad, Neutral, Tonal Spot, Expressive, Rainbow, Fidelity, Monochrome.
Hyprland scratchpad, submap, fake fullscreen and pseudo-tiling stay literal.
Capitalization such as Material Cookie remains where it is already recognizable
English and correct for the locale; no case-only rewrites were made.

The existing conventional Home-folder label, natural restored-audio state,
and compact transliterated Island compounds are retained. The guidance is
applied for meaning and UI fit rather than mechanically copying Spanish.

### Exact value changes

| Exact English key | Previous committed value | Reviewed value | Reason |
| --- | --- | --- | --- |
| Fruit Salad | フルーツサラダ | Fruit Salad | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Dotfiles | ドットファイル | Dotfiles | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Neutral | ニュートラル | Neutral | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Tonal Spot | トーナルスポット | Tonal Spot | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Expressive | 表現豊か | Expressive | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Hug | 端に密着 | 引き伸ばし | Name the edge-spanning style; the earlier wording meant an embrace or attachment to an edge. |
| Rainbow | レインボー | Rainbow | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Fidelity | 忠実度 | Fidelity | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Earbang protection | 聴覚保護（急な大音量防止） | 音量急上昇防止 | Name sudden volume-jump protection concisely; this is neither visual flashing nor headphone hardware protection. |
| Monochrome | モノクロ | Monochrome | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Anti-flashbang | まぶしさを防ぐ | フラッシュ抑制 | Use the same visual-flash-protection term as the other levels of this control. |
| Enter submap | サブマップに切り替え | submap に切り替え | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Skip dotfiles | ドットファイルをスキップ | Dotfilesをスキップ | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Skip the Mainstream dotfiles refresh step (updatems). Dotfiles update only when a new release tag is published upstream; turn this on to manage them manually. | Mainstream のドットファイル更新（updatems）をスキップします。ドットファイルは、上流で新しいリリースタグが公開されたときだけ更新されます。手動で管理する場合は有効にしてください。 | Mainstream のDotfiles更新（updatems）をスキップします。Dotfilesは、上流で新しいリリースタグが公開されたときだけ更新されます。手動で管理する場合は有効にしてください。 | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Special (scratchpad) | 特殊（スクラッチパッド） | 特殊（scratchpad） | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle fake fullscreen | 擬似全画面を切り替え | fake fullscreen を切り替え | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle pseudo-tiling | 擬似タイル配置を切り替え | pseudo-tiling を切り替え | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle scratchpad | スクラッチパッドを切り替え | scratchpad を切り替え | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| end-4 — Dotfiles | end-4 — ドットファイル | end-4 — Dotfiles | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Blur through to the wallpaper | 壁紙を透かしてぼかす | 壁紙を直接ぼかす | The xray switch samples the wallpaper directly, rather than looking through the wallpaper (DecorationsConfig.qml:1081/1092). |
| How deep the frost goes. Deeper costs more to draw. | すりガラス効果の深さです。深くするほど描画の負荷が高くなります。 | ぼかしの深さです。深くするほど描画の負荷が高くなります。 | Use the chosen blur term consistently for blur and frosted surfaces. |
| no frost | すりガラス効果なし | ぼかしなし | Use the chosen blur term consistently for blur and frosted surfaces. |
| No frost behind it | 背後のすりガラス効果なし | 背後のぼかしなし | Use the chosen blur term consistently for blur and frosted surfaces. |
| Notch | ノッチ | Notch | Preserve Notch as the named drawn style, not a physical hardware-cutout noun. |
| Toggle the scratchpad workspace | スクラッチパッドワークスペースを切り替え | scratchpad ワークスペースを切り替え | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Exit the keybind submap | キー割り当てのサブマップを終了 | キー割り当ての submap を終了 | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Dotfiles: deferred — the system package update failed, and dotfile releases can depend on packages it would have installed. Re-run the update once the package step succeeds. | ドットファイル：延期しました。システムパッケージの更新に失敗しており、新しいドットファイルはその更新で入るパッケージに依存している場合があります。パッケージの更新が成功したら、更新を再実行してください。 | Dotfiles：延期しました。システムパッケージの更新に失敗しており、新しいDotfilesはその更新で入るパッケージに依存している場合があります。パッケージの更新が成功したら、更新を再実行してください。 | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Mainstream dotfiles — updatems | Mainstream ドットファイル — updatems | Mainstream Dotfiles — updatems | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles: skipped (per --skip-dotfiles) | ドットファイル：スキップ（--skip-dotfiles による指定） | Dotfiles：スキップ（--skip-dotfiles による指定） | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| No dotfiles clone at %s — bootstrapping from %s | %s にドットファイルのクローンがありません。%s から初期設定します | %s にDotfilesのクローンがありません。%s から初期設定します | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Cloned dotfiles to %s | ドットファイルを %s にクローンしました | Dotfilesを %s にクローンしました | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles (updatems): | ドットファイル（updatems）： | Dotfiles（updatems）： | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| The dotfiles clone at %s is damaged. Setting it aside as %s and cloning again. | %s のドットファイルのクローンが破損しています。%s に退避し、再度クローンします。 | %s のDotfilesのクローンが破損しています。%s に退避し、再度クローンします。 | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Update finished, but the Mainstream dotfiles did not update. See the Dotfiles line in the summary above. | 更新は終了しましたが、Mainstream のドットファイルは更新されていません。上の概要のドットファイルの行を確認してください。 | 更新は終了しましたが、Mainstream のDotfilesは更新されていません。上の概要のDotfilesの行を確認してください。 | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| [DRY-RUN] The dotfiles clone at %s is damaged; would set it aside as %s and clone again. | [DRY-RUN] %s のドットファイルのクローンが破損しています。%s に退避して再度クローンする予定です。 | [DRY-RUN] %s のDotfilesのクローンが破損しています。%s に退避して再度クローンする予定です。 | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Refreshing /etc/skel from the dotfiles... | ドットファイルから /etc/skel を更新中... | Dotfilesから /etc/skel を更新中... | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles: waiting for the desktop update that matches the new Qt. | ドットファイル：新しい Qt に対応するデスクトップの更新を待っています。 | Dotfiles：新しい Qt に対応するデスクトップの更新を待っています。 | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles: waiting for the system packages, which were held back. | ドットファイル：保留されたシステムパッケージの更新を待っています。 | Dotfiles：保留されたシステムパッケージの更新を待っています。 | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Signed in. The plan models are in the picker now: type /model to choose between Gemini 3.8 Flash (High, Medium, Low) and Gemini 3.1 Pro (High, Low). | ログインしました。プランモデルがセレクターに追加されました：/model と入力して Gemini 3.8 Flash (High, Medium, Low) または Gemini 3.1 Pro (High, Low) を選択できます。 | ログインしました。プランモデルがセレクターに追加されました：/model と入力して Gemini 3.8 Flash（高、中、低）または Gemini 3.1 Pro（高、低）を選択できます。 | The parenthesized names are visible effort levels, not literal command arguments. |
| Thinking Level: %1<br>Click to cycle (minimal → low → medium → high → auto) | 思考レベル: %1<br>クリックして切り替え (minimal → low → medium → high → auto) | 思考レベル: %1<br>クリックして切り替え（最小 → 低 → 中 → 高 → 自動） | Translate visible click-cycle effort labels; accepted typed command arguments elsewhere remain literal. |
| Frosted widget backgrounds | ウィジェットのすりガラス背景 | ウィジェットのぼかした背景 | Use the chosen blur term consistently for blur and frosted surfaces. |

### Newly English-identical values

These are restored names/identifiers, not untranslated prose.

- "Fruit Salad"
- "Dotfiles"
- "Neutral"
- "Tonal Spot"
- "Expressive"
- "Rainbow"
- "Fidelity"
- "Monochrome"
- "end-4 — Dotfiles"
- "Notch"

### Source-confirmed exceptions and remaining limits

- Standalone Swap means memory in Resources.qml, ResourcesPanel.qml and ResourcesPopup.qml. Window-action keys use exchange verbs separately. The offline Spanish interpretation did not have source access.
- at in the automatic-suspend row is a battery percentage. Up %1 is uptime. Home in KeybindCaptureItem.qml is an untranslated X11 keysym and does not share the translated personal-folder call.
- Cookie/Material cookie are shape names; Expressive font is a normal descriptive font role and stays translated. No source strings, commands, accepted arguments, runtime names or configuration keys were changed.
- Longer accurate compounds still need eventual visual fit checks. No explanatory label expansions or new manual wrapping line breaks were added.

## Consolidated display-name pass, 2026-10-31

The current policy and approved terms are consolidated in [TERMINOLOGY.md](../../TERMINOLOGY.md). Earlier English-preservation rules and allowlists above are historical. The current pass changes 12 display values, preserving English keys, command syntax, identifiers and all formatting. These are self-reviewed working choices, not native-speaker-verified.

- "Material cookie" → "マテリアルクッキー"
- "Fruit Salad" → "フルーツサラダ"
- "Neutral" → "ニュートラル"
- "Tonal Spot" → "トーナルスポット"
- "Expressive" → "エクスプレッシブ"
- "Rainbow" → "虹"
- "Fidelity" → "忠実度"
- "Cookie clock settings" → "クッキー時計の設定"
- "Monochrome" → "モノクロ"
- "Use old sine wave cookie implementation" → "従来の正弦波によるクッキー描画を使う"
- "Cookie" → "クッキー"
- "Notch" → "ノッチ"

Current intentionally English-identical count: 68. Names, units, literal formats and natural shared vocabulary remain valid; the lower count is not the purpose of this pass.
