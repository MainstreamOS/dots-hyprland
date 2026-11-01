# Korean completion notes

Catalog: `ko_KR.json`. Source: all 3,221 keys of `en_US.json`, based on mainstream `4f6196092`.

This new locale translates 3,153 previously English-identical values. There were no existing translations to replace. All 68 remaining English-identical values were individually checked and are listed below. Keys and their order are unchanged.

## Validation and review

- Every batch passed structural validation before writing. `tools/catalog-qa.py ko_KR` reports zero errors: JSON uniqueness and exact keys, placeholders and printf order, actual newlines, joining whitespace, markup/Markdown/backticks, protected names, numeric values, URLs, paths, flags and config filenames.
- All 47 printf-format messages were exercised through the actual `sdata/lib/tr.sh` with distinct arguments. Exact source key order and a separate slash-command audit pass. The command audit uses ASCII identifier boundaries to recognize commands immediately followed by Korean particles without accepting changed command names.
- All 13 validator regression tests pass. The seven previously completed locale catalogs also pass structural checks.
- A fresh-context review covered 1,588 unique English/Korean pairs: a 200-key feature sample across 83 source buckets, all 321 actual runtime-placeholder keys, 497 warning/destructive/access/update/recovery candidates, 376 ambiguity and terminology candidates, all final 721 AI/phone/Island keys, and every English-identical value. These sets overlap. The percent-encoded Zerochan URL was also checked exactly. All four corrected pairs were reread after correction.
- Sample selection groups by first candidate source: settings/<first component after modules/settings/>, desktop/<first after modules/ii/>, services/AI for /Ai. or /ai/, otherwise services/other; sdata/ becomes scripts; no source becomes legacy; other paths use apps/<basename>. Sort buckets lexically and keys within each bucket by raw SHA256 of `ko_KR-fresh-context-review-v1` + NUL + key, then take round-robin by bucket depth until 200.
- Compact UTF-8 JSON serialization (`ensure_ascii=False`, separators comma and colon) of the sample keys hashes to `0dbbc65595c4c2da05fd5572260eadf4742c59ef50c26eac38b4b9d8cd2a16cf`. All reviewed keys in catalog order hash to `92671d0307d9c4b20a2a41c4d0ee3fa1144b626c8ba012cd0ef43abc15b4846a`.
- Root audited the glossary across the full catalog and read source contexts for ambiguous labels. Expected contextual differences remain: appearance snapshots are records of a theme, the HDR test window is a bright test region, and identifiers such as sidebar.booru.zerochan.username remain literal.
- No native-speaker review or live language preview was performed. These are translations with automated validation and a separate review.

## Draft corrections after independent review

| Exact English key | Correction |
| --- | --- |
| Line-separated | 구분선으로 나누기 describes the bar widget separators; the draft had incorrectly described newline separation. |
| Scales the overall brightness of SDR content in HDR mode. 1.0 is the reference level; increase if SDR applications look dim compared to native HDR content.<br><br>The grey ramp updates in real time to show how all SDR tones shift. | Use 네이티브 HDR 콘텐츠 rather than default HDR content. |
| Manage local Ollama models (list, pull, status) | Keep list, pull and status as the literal command arguments parsed by the interface. |
| Move windows aside while the hidden bar shows | Use direction-neutral 밀어내기 because top/bottom bars and Dynamic Island reserve vertical space too. |

## Existing translations replaced

None. The starting catalog contained English placeholders only.

## Intentionally English-identical values

Each entry was checked individually. None is remaining untranslated English prose.

| Exact English key | Reason |
| --- | --- |
| OK | Widely understood confirmation label OK. |
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
| Antigravity: | Preserved product, project, named layout, command label or named visual style. |
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

- `Play` is shared by a gaming heading and media playback controls. 재생 prioritizes actionable playback; the gaming heading needs its own source key for 게임.
- `From` 시작 and `To` 대상 are compromises for gradient endpoints and the shared recipient label. Separate source keys would permit gradient 시작/끝 and recipient 받는 사람. No context markers were invented.
- Provider subscription Plan is 구독; the non-executing assistant mode is 계획. Window focus is 초점; Pomodoro concentration is 집중. Generic desktop layout uses 배치; keyboard layout uses 배열. The shared Minimal label is 최소 for both indicators and AI effort.
- `Locked` is both a lock-screen state and a key-binding flag; the binding explanation says it works even when locked. `Launch on startup` controls lock.launchOnStartup and says 시작 시 잠금. Junction is the GPU hotspot, Swap is memory swap, and Call is a history noun.
- The full-app-list launcher option is scoped to overview being disabled, not all application windows. Phone privacy hides Island notifications rather than disabling phone communications. The streaming setting suppresses alerts whenever selected Discord/OBS windows or processes exist, without checking that streaming is active; resolve this source behavior separately.
- Sharing password validation accepts printable ASCII only, while its source help mentions only accented letters and emoji. This also excludes Hangul. Translation preserves the supplied restriction; English needs the full restriction.
- The legacy git stash list recovery instruction lists stashes rather than restoring them. The newer key provides git stash show --include-untracked stash@{0} and git stash pop. Literal supplied commands are preserved; reconcile the older source separately.
- Old help uses Ctrl+P to detach; newer help uses Ctrl+D to detach and Ctrl+P to pin. Each supplied shortcut is preserved. The older API-provider help uses %2mode PROVIDER, while newer execution-mode help uses ask|auto|plan.
- One update-advice key contains literal \u2014 text; the value uses natural Korean punctuation without changing the lookup key. Literal Snapshots/linux boot entries, typed arguments, executables, service names, URLs, paths and flags are preserved.
- The legacy account-deletion prompt is built from an opening fragment, the account name and a closing fragment. Korean puts the question and irreversible warning in the closing fragment so the complete message reads naturally.
- Names and model/pricing descriptions were translated as supplied, not externally verified as current product claims.

## Historical reasoning review

Historical review record. Current rules and display names are consolidated in
[TERMINOLOGY.md](../../TERMINOLOGY.md); the English-preservation decisions in this
old report are superseded where the current guide specifies localized labels.

This is the focused follow-up requested after Ukrainian completion. It applies
the owner’s updated terminology, HANDOFF.md, and corrected es_MX example from
`/home/itsjustdroid/Downloads/updated-reasoning`. It supplements the initial
glossary and completion notes; the decisions below supersede older decisions
on these terms. Good existing values outside concrete findings are preserved.

Changes: **39 of 3,221 values**. Source English keys and order are
unchanged. **79 values remain English-identical**; new ones introduced
by this review are explicitly listed below. Other identical entries retain the
individual audit from the original completion notes.

### Review and checks

- Root read the 90 related entries and all changes. Independent fresh-context review read the complete group-2 packet (360 records across four locales), including this locale’s 90 entries. Source context was checked for ambiguous controls.
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
| Island position | 아일랜드 위치 |
| Island style | 아일랜드 스타일 |
| Pills | 캡슐 |
| Hug | 확장 |
| Notch | Notch |
| Earbang protection | 음량 급증 방지 |
| Unmuted | 음소거 해제됨 |
| Home | 홈 |
| Swap | 스왑 |
| Tray | 트레이 |
| System tray | 시스템 트레이 |
| Blur | 흐림 |

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
| Fruit Salad | 과일 샐러드 | Fruit Salad | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Dotfiles | 설정 파일 | Dotfiles | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Neutral | 중립 | Neutral | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Tonal Spot | 톤 스폿 | Tonal Spot | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Expressive | 표현력 풍부 | Expressive | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Hug | 가장자리에 밀착 | 확장 | Name the edge-spanning style; the earlier wording meant an embrace or attachment to an edge. |
| Rainbow | 무지개 | Rainbow | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Fidelity | 충실도 | Fidelity | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Earbang protection | 갑작스러운 큰 소리 방지 | 음량 급증 방지 | Name sudden volume-jump protection concisely; this is neither visual flashing nor headphone hardware protection. |
| Monochrome | 단색 | Monochrome | Keep the Material You palette preset’s searchable identifier/name unchanged. |
| Enter submap | 서브맵으로 전환 | submap으로 전환 | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Skip dotfiles | 설정 파일 건너뛰기 | dotfiles 건너뛰기 | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Skip the Mainstream dotfiles refresh step (updatems). Dotfiles update only when a new release tag is published upstream; turn this on to manage them manually. | Mainstream 설정 파일 갱신 단계(updatems)를 건너뜁니다. 설정 파일은 원본에 새 릴리스 태그가 게시될 때만 업데이트됩니다. 직접 관리하려면 켜세요. | Mainstream dotfiles 갱신 단계(updatems)를 건너뜁니다. Dotfiles는 원본에 새 릴리스 태그가 게시될 때만 업데이트됩니다. 직접 관리하려면 켜세요. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Special (scratchpad) | 특수(스크래치패드) | 특수(scratchpad) | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle fake fullscreen | 가상 전체 화면 전환 | fake fullscreen 전환 | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle pseudo-tiling | 의사 타일링 전환 | pseudo-tiling 전환 | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Toggle scratchpad | 스크래치패드 전환 | scratchpad 전환 | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| end-4 — Dotfiles | end-4 — 설정 파일 | end-4 — Dotfiles | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| How deep the frost goes. Deeper costs more to draw. | 반투명 유리 효과의 깊이입니다. 깊을수록 그리기 부하가 커집니다. | 흐림 효과의 깊이입니다. 깊을수록 그리기 부하가 커집니다. | Use the chosen blur term consistently for blur and frosted surfaces. |
| no frost | 유리 효과 없음 | 흐림 없음 | Use the chosen blur term consistently for blur and frosted surfaces. |
| No frost behind it | 뒤의 유리 효과 끄기 | 뒤의 흐림 끄기 | Use the chosen blur term consistently for blur and frosted surfaces. |
| Notch | 노치 | Notch | Preserve Notch as the named drawn style, not a physical hardware-cutout noun. |
| Toggle the scratchpad workspace | 스크래치패드 작업 공간 전환 | scratchpad 작업 공간 전환 | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Exit the keybind submap | 키 바인딩 서브맵 나가기 | 키 바인딩 submap 나가기 | Preserve the Hyprland configuration/dispatcher name so it remains identifiable and searchable. |
| Dotfiles: deferred — the system package update failed, and dotfile releases can depend on packages it would have installed. Re-run the update once the package step succeeds. | 설정 파일: 연기됨. 시스템 패키지 업데이트에 실패했으며 설정 파일 릴리스가 해당 단계에서 설치할 패키지에 의존할 수 있습니다. 패키지 단계가 성공한 후 업데이트를 다시 실행하세요. | Dotfiles: 연기됨. 시스템 패키지 업데이트에 실패했으며 dotfiles 릴리스가 해당 단계에서 설치할 패키지에 의존할 수 있습니다. 패키지 단계가 성공한 후 업데이트를 다시 실행하세요. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Mainstream dotfiles — updatems | Mainstream 설정 파일 — updatems | Mainstream dotfiles — updatems | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles: skipped (per --skip-dotfiles) | 설정 파일: 건너뜀(--skip-dotfiles 지정) | Dotfiles: 건너뜀(--skip-dotfiles 지정) | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| No dotfiles clone at %s — bootstrapping from %s | %s 위치에 설정 파일 복제본이 없어 %s에서 초기 설정합니다 | %s 위치에 dotfiles 복제본이 없어 %s에서 초기 설정합니다 | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Cloned dotfiles to %s | 설정 파일을 %s에 복제했습니다 | Dotfiles를 %s에 복제했습니다 | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles (updatems): | 설정 파일(updatems): | Dotfiles(updatems): | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| The dotfiles clone at %s is damaged. Setting it aside as %s and cloning again. | %s의 설정 파일 복제본이 손상되었습니다. %s(으)로 옮겨 두고 다시 복제합니다. | %s의 dotfiles 복제본이 손상되었습니다. %s(으)로 옮겨 두고 다시 복제합니다. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Update finished, but the Mainstream dotfiles did not update. See the Dotfiles line in the summary above. | 업데이트는 끝났지만 Mainstream 설정 파일은 업데이트하지 못했습니다. 위 요약의 설정 파일 항목을 확인하세요. | 업데이트는 끝났지만 Mainstream dotfiles는 업데이트하지 못했습니다. 위 요약의 Dotfiles 항목을 확인하세요. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| [DRY-RUN] The dotfiles clone at %s is damaged; would set it aside as %s and clone again. | [DRY-RUN] %s의 설정 파일 복제본이 손상되었습니다. %s(으)로 옮겨 두고 다시 복제할 예정입니다. | [DRY-RUN] %s의 dotfiles 복제본이 손상되었습니다. %s(으)로 옮겨 두고 다시 복제할 예정입니다. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Refreshing /etc/skel from the dotfiles... | 설정 파일에서 /etc/skel 갱신 중... | Dotfiles에서 /etc/skel 갱신 중... | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles: waiting for the desktop update that matches the new Qt. | 설정 파일: 새로운 Qt와 호환되는 데스크톱 업데이트를 기다리는 중입니다. | Dotfiles: 새로운 Qt와 호환되는 데스크톱 업데이트를 기다리는 중입니다. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Dotfiles: waiting for the system packages, which were held back. | 설정 파일: 보류된 시스템 패키지를 기다리는 중입니다. | Dotfiles: 보류된 시스템 패키지를 기다리는 중입니다. | Preserve the Dotfiles/dotfiles repository and update-step name, including log references and credits. |
| Signed in. The plan models are in the picker now: type /model to choose between Gemini 3.8 Flash (High, Medium, Low) and Gemini 3.1 Pro (High, Low). | 로그인했습니다. 이제 구독 모델을 선택할 수 있습니다. /model로 Gemini 3.8 Flash(High, Medium, Low)와 Gemini 3.1 Pro(High, Low)를 선택하세요. | 로그인했습니다. 이제 구독 모델을 선택할 수 있습니다. /model로 Gemini 3.8 Flash(높음, 중간, 낮음)와 Gemini 3.1 Pro(높음, 낮음)를 선택하세요. | The parenthesized names are visible effort levels, not literal command arguments. |
| Thinking Level: %1<br>Click to cycle (minimal → low → medium → high → auto) | 생각 수준: %1<br>클릭하여 순환(minimal → low → medium → high → auto) | 생각 수준: %1<br>클릭하여 순환(최소 → 낮음 → 중간 → 높음 → 자동) | Translate visible click-cycle effort labels; accepted typed command arguments elsewhere remain literal. |
| Frosted widget backgrounds | 반투명 유리 위젯 배경 | 위젯 배경 흐림 | Use the chosen blur term consistently for blur and frosted surfaces. |

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
- "Mainstream dotfiles — updatems"

### Source-confirmed exceptions and remaining limits

- Standalone Swap means memory in Resources.qml, ResourcesPanel.qml and ResourcesPopup.qml. Window-action keys use exchange verbs separately. The offline Spanish interpretation did not have source access.
- at in the automatic-suspend row is a battery percentage. Up %1 is uptime. Home in KeybindCaptureItem.qml is an untranslated X11 keysym and does not share the translated personal-folder call.
- Cookie/Material cookie are shape names; Expressive font is a normal descriptive font role and stays translated. No source strings, commands, accepted arguments, runtime names or configuration keys were changed.
- Longer accurate compounds still need eventual visual fit checks. No explanatory label expansions or new manual wrapping line breaks were added.

## Consolidated display-name pass, 2026-10-31

The current policy and approved terms are consolidated in [TERMINOLOGY.md](../../TERMINOLOGY.md). Earlier English-preservation rules and allowlists above are historical. The current pass changes 12 display values, preserving English keys, command syntax, identifiers and all formatting. These are self-reviewed working choices, not native-speaker-verified.

- "Material cookie" → "머티리얼 쿠키"
- "Fruit Salad" → "과일 샐러드"
- "Neutral" → "중립"
- "Tonal Spot" → "토널 스폿"
- "Expressive" → "표현형"
- "Rainbow" → "무지개"
- "Fidelity" → "충실도"
- "Cookie clock settings" → "쿠키 시계 설정"
- "Monochrome" → "단색"
- "Use old sine wave cookie implementation" → "기존 사인파 쿠키 구현 사용"
- "Cookie" → "쿠키"
- "Notch" → "노치"

Current intentionally English-identical count: 70. Names, units, literal formats and natural shared vocabulary remain valid; the lower count is not the purpose of this pass.
