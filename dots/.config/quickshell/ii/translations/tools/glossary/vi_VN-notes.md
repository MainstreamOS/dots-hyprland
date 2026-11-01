# Vietnamese completion notes

Source: all 3,221 English keys, SHA256
`d222d7ae70507e91f555e6bd621ed7b574f7c7f722ff73a8a4826260be17617b`.
Based on local mainstream `ea1b7e593` and the owner’s updated 2026-10-28 terminology.

Translates 2,573 previously English-identical values, corrects 67 existing entries
for concrete reasons and preserves 486 good prior translations. All 101
remaining English-identical values have been individually audited. Keys and order are unchanged.

## Validation and independent review

- Every successfully applied batch passes catalog validation; initial preexisting defects were cleared during translation. Final structural checks cover exact keys/order, placeholders, printf order, joining whitespace and newlines, markup, Markdown/code, protected names, numeric values, commands/flags, paths and URLs.
- All 47 printf messages pass through the actual sdata/lib/tr.sh formatter using distinct arguments. Expanded identifier/slash-command checks and English-source digest pass.
- All 13 catalog-validator regression tests pass.
- Independent fresh-context review read all 1,639 packet pairs and all 60 initial old-value comparisons, then independently reread all seven final corrections (1,646 pair reviews). No remaining concrete finding was reported. All 101 English-identical values were checked as intentional.
- Review packet: 1,639 unique pairs, comprising a deterministic 200-key sample across 83 source buckets, all 321 runtime-placeholder entries, 497 risk candidates, 376 ambiguity candidates, all final 721 entries, all 60 initial old-value corrections and all 101 English-identical values. These sets overlap.
- Sampling: bucket by first source path into settings/<first component after modules/settings/>, desktop/<first after modules/ii/>, services/AI for /Ai. or /ai/, services/other otherwise, scripts for sdata/, legacy for missing source, apps/<basename> otherwise. Sort buckets lexically, keys by raw SHA256 of vi_VN-fresh-context-review-v1 + NUL + key; round-robin to 200.
- Compact UTF-8 sample-key JSON SHA256: `1d57908df3c9522ce2586c903f46896dad0ed16dfde1731615bd340ecef4c7d9`. Packet-key JSON SHA256: `67a035ed8072abc16c1b0228ad03c9264483a13ee3ec196bf82693e80e9dac20`.
- This is translation with automated validation and a separate review. No native-speaker verification or live language preview. Longer Vietnamese compound labels still need eventual UI-fit review.

## Existing translations corrected

| Exact English key | Before | After | Concrete reason |
| --- | --- | --- | --- |
| Elements | Nguyên tố | Thành phần | Use the interface-components sense of Elements, not chemical elements; no active caller remains, so this is a legacy-context inference. |
| Depends on workspace | Phụ thuộc vào workspace | Phụ thuộc vào không gian làm việc | Use không gian làm việc consistently for workspace controls. |
| Workspaces shown | Số workspace hiển thị | Số không gian làm việc hiển thị | Use không gian làm việc consistently for workspace controls. |
| No API key<br>Set it with /key YOUR_API_KEY | Không có API key<br>Đặt bằng /key API_KEY | Không có API key<br>Đặt bằng /key YOUR_API_KEY | Restore the literal command metavariable; accepted syntax must remain copyable. |
| Max allowed increase | Thay đổi tối đa | Mức tăng tối đa | Preserve the upward direction: the control limits a volume increase, not any change. |
| Online \| %1's 1T parameter flagship. Strong at coding, agentic workflows, and structured tool use. Disadvantages: higher initial latency and tends to be verbose | Trực tuyến \| Mô hình đầu bảng 1T tham số của %1. Mạnh về lập trình, quy trình làm việc tác tử và sử dụng công cụ có cấu trúc. Nhược điểm: độ trễ ban đầu cao hơn và có xu hướng dài dòng | Trực tuyến \| Model đầu bảng 1T tham số của %1. Mạnh về lập trình, quy trình làm việc tác tử và sử dụng công cụ có cấu trúc. Nhược điểm: độ trễ ban đầu cao hơn và có xu hướng dài dòng | Use the established model loan consistently in provider descriptions. |
| Fruit Salad | Salad hoa quả | Fruit Salad | Preserve the named Material You palette under the updated terminology. |
| On-screen display | Âm lượng/độ sáng | Hiển thị trên màn hình | On-screen display is the status surface (including gamma), not only volume/brightness. |
| Keep system awake | Giữ hệ thống bật | Giữ hệ thống thức | Name inhibition of sleep rather than merely keeping the machine powered. |
| API key is set<br>Change with /key YOUR_API_KEY | API key đã đặt<br>Thay đổi bằng /key API_KEY | API key đã đặt<br>Thay đổi bằng /key YOUR_API_KEY | Restore the literal command metavariable; accepted syntax must remain copyable. |
| Neutral | Trung tính | Neutral | Preserve the named Material You palette under the updated terminology. |
| Type /key to get started with online models<br>Ctrl+O to expand the sidebar<br>Ctrl+P to detach sidebar into a window | Gõ /key để bắt đầu dùng các model trực tuyến<br>Ctrl+O để mở rộng sidebar<br>Ctrl+P để nhấc sidebar thành cửa sổ | Gõ /key để bắt đầu dùng các model trực tuyến<br>Ctrl+O để mở rộng thanh bên<br>Ctrl+P để tách thanh bên thành cửa sổ | Use thanh bên consistently for sidebar controls; detach remains distinct from pinning. |
| Usage: %1tool TOOL_NAME | Hướng dẫn: %1tool TÊN_CÔNG_CỤ | Hướng dẫn: %1tool TOOL_NAME | Restore the literal command metavariable; accepted syntax must remain copyable. |
| Workspaces | Các workspace | Không gian làm việc | Use không gian làm việc consistently for workspace controls. |
| Prevents abrupt increments and restricts volume limit | Chặn thay đổi đột ngột và giới hạn âm lượng | Chặn mức tăng đột ngột và giới hạn âm lượng | Limit sudden upward volume increments, not all changes. |
| Expressive | Biểu cảm | Expressive | Preserve the named Material You palette under the updated terminology. |
| Suspend at | Tạm dừng ở | Ngủ ở mức | Battery threshold triggers system sleep, not a generic pause. |
| Hug | Ôm | Giãn | Hug names an edge-spanning shape, not an embrace. |
| Rainbow | Cầu vồng | Rainbow | Preserve the named Material You palette under the updated terminology. |
| Show regions of potential interest | Hiển thị vùng thông minh | Hiện vùng đáng chú ý | The image-processing feature identifies potentially interesting regions; the source explicitly does not use AI. |
| Fidelity | Khá giống gốc | Fidelity | Preserve the named Material You palette under the updated terminology. |
| Prefixes | Kí tự đầu | Tiền tố | The fields configure search prefixes, not just an initial character. |
| Depends on sidebars | Phụ thuộc vào sidebar | Phụ thuộc vào thanh bên | Use thanh bên consistently for sidebar controls; detach remains distinct from pinning. |
| Earbang protection | Bảo vệ tai | Chống tăng vọt âm lượng | Limits abrupt volume jumps, not generic protection of ears. |
| Current tool: %1<br>Set it with %2tool TOOL | Công cụ: %1<br>Đặt bằng %2tool CÔNG_CỤ | Công cụ: %1<br>Đặt bằng %2tool TOOL | Restore the literal command metavariable; accepted syntax must remain copyable. |
| Such regions could be images or parts of the screen that have some containment.<br>Might not always be accurate.<br>This is done with an image processing algorithm run locally and no AI is used. | Các vùng có thể là hình ảnh hoặc phần của màn hình cớ vẻ được bao chứa.<br>Không luôn chính xác.<br>Sử dụng một thuật toán xử lý ảnh chạy trên máy, không dùng AI. | Các vùng có thể là hình ảnh hoặc phần màn hình có ranh giới bao quanh.<br>Không phải lúc nào cũng chính xác.<br>Dùng thuật toán xử lý ảnh chạy trên máy, không dùng AI. | Repair the misspelling and preserve bounded image-region meaning. |
| Invalid arguments. Must provide `key` and `value`. | Biến không hợp lệ. cần cả `key` và `value`. | Tham số không hợp lệ. Phải cung cấp `key` và `value`. | Arguments are parameters, not variables; repair capitalization/grammar. |
| Bar style | Phong cách bar | Kiểu thanh | Translate the residual bar loan using the desktop-bar glossary. |
| Color generation | Chỉnh màu | Tạo màu | Generates colors rather than just editing existing colors. |
| Temperature<br>Change with /temp VALUE | Nhiệt độ (độ ngẫu nhiên)<br>Thay đổi bằng /temp GIÁ_TRỊ | Nhiệt độ (độ ngẫu nhiên)<br>Thay đổi bằng /temp VALUE | Restore the literal command metavariable; accepted syntax must remain copyable. |
| Content | Giống gốc | Nội dung | Use the content-derived palette sense rather than the different Fidelity label. |
| Shell & utilities theming must also be enabled | Cần Shell & công cụ cũng bật | Cũng cần bật chủ đề cho Shell & tiện ích | The requirement is enabling shell/utilities theming, not merely enabling the shell itself. |
| **Pricing**: free. Data used for training.<br><br>**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key | **Giá**: miễn phí. Dữ liệu được sử dụng cho mục đích huấn luyện. **Hướng dẫn**: Đăng nhập vào tài khoản Google, cho phép AI Studio tạo dự án Google Cloud gì đó, quay lại rồi ấn Get API key | **Giá**: miễn phí. Dữ liệu được sử dụng cho mục đích huấn luyện.<br><br>**Hướng dẫn**: Đăng nhập vào tài khoản Google, cho phép AI Studio tạo dự án Google Cloud hoặc làm theo yêu cầu, quay lại rồi ấn Get API key | Restore the two source newlines and preserve the full cloud-project instruction. |
| Monochrome | Đen trắng | Monochrome | Preserve the named Material You palette under the updated terminology. |
| Usage: %1save CHAT_NAME | Hướng dẫn: %1save TÊN_ĐOẠN_CHAT | Hướng dẫn: %1save CHAT_NAME | Restore the literal command metavariable; accepted syntax must remain copyable. |
| Online \| Google's model<br>A Gemini 2.5 Flash model optimized for cost-efficiency and high throughput. | Trực tuyến \| Model của Google<br>Model Gemini 2.5 Flash tối ưu hóa cho hiệu quả chi phí và băng thông. | Trực tuyến \| Model của Google<br>Model Gemini 2.5 Flash tối ưu hóa cho hiệu quả chi phí và thông lượng cao. | Model throughput is processing capacity, not network bandwidth. |
| Performance Profile toggle | Nút Performance Profile | Nút chuyển chế độ hiệu năng | Translate the residual performance-profile label. |
| Usage: %1load CHAT_NAME | Hướng dẫn: %1load TÊN_ĐOẠN_CHAT | Hướng dẫn: %1load CHAT_NAME | Restore the literal command metavariable; accepted syntax must remain copyable. |
| **Pricing**: free tier, with data used for training. Web search needs billing turned on.<br><br>**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key | **Giá**: có gói miễn phí, dữ liệu được sử dụng cho mục đích huấn luyện. Tìm kiếm web yêu cầu bật thanh toán.<br><br>**Hướng dẫn**: Đăng nhập vào tài khoản Google, cho phép AI Studio tạo dự án Google Cloud gì đó, quay lại rồi ấn Get API key | **Giá**: có gói miễn phí, dữ liệu được sử dụng cho mục đích huấn luyện. Tìm kiếm web yêu cầu bật thanh toán.<br><br>**Hướng dẫn**: Đăng nhập vào tài khoản Google, cho phép AI Studio tạo dự án Google Cloud hoặc làm theo yêu cầu, quay lại rồi ấn Get API key | Preserve Google Cloud project setup and following requests, not an unspecified project. |
| Signed in. The plan models are in the picker now: type /model to choose between Gemini 3.8 Flash (High, Medium, Low) and Gemini 3.1 Pro (High, Low). | Đã đăng nhập. Các model trong gói hiện đã có trong bộ chọn: gõ /model để chọn giữa Gemini 3.8 Flash (High, Medium, Low) và Gemini 3.1 Pro (High, Low). | Đã đăng nhập. Các model trong gói hiện đã có trong bộ chọn: gõ /model để chọn giữa Gemini 3.8 Flash (Cao, Trung bình, Thấp) và Gemini 3.1 Pro (Cao, Thấp). | Parenthesized effort levels are UI labels, not literal typed command arguments. |
| Set thinking level (reasoning effort). Values: minimal, low, medium, high, auto. Replaces deprecated thinking budget. | Đặt mức độ suy nghĩ (nỗ lực suy luận). Giá trị: minimal, low, medium, high, auto. Thay thế cho thinking budget đã lỗi thời. | Đặt mức độ suy nghĩ (mức suy luận). Giá trị: minimal, low, medium, high, auto. Thay thế hạn mức suy nghĩ đã lỗi thời. | Translate residual thinking-budget prose as a processing allowance while preserving accepted arguments. |
| Signed in. Gemini Flash and Gemini Pro are in the picker now. Adjust thinking level with the reasoning pill or /think. | Đã đăng nhập. Gemini Flash và Gemini Pro hiện đã có trong bộ chọn. Điều chỉnh mức độ suy nghĩ bằng biểu tượng trạng thái hoặc /think. | Đã đăng nhập. Gemini Flash và Gemini Pro hiện đã có trong bộ chọn. Điều chỉnh mức độ suy nghĩ bằng nút suy luận dạng con nhộng hoặc /think. | The reasoning control is capsule-shaped, not an unspecified status icon. |
| Thinking Level: %1<br>Click to cycle (minimal → low → medium → high → auto) | Mức độ suy nghĩ: %1<br>Nhấn để chuyển đổi (minimal → low → medium → high → auto) | Mức độ suy nghĩ: %1<br>Nhấn để chuyển đổi (tối thiểu → thấp → trung bình → cao → tự động) | Translate UI effort labels in the click-cycle tooltip; this is not typed command syntax. |
| Signed in via %1<br>No API key needed | Đã đăng nhập qua %1<br>Không cần khóa API | Đã đăng nhập qua %1<br>Không cần API key | Use the existing API key term consistently. |
| Medium — Balanced reasoning | Vừa — Suy luận cân bằng | Trung bình — Suy luận cân bằng | Use Trung bình consistently for Medium in the reasoning-level set. |
| Online \| Google's model<br>Google's Gemini models with a free tier: Gemini Flash and Gemini Pro. | Trực tuyến \| Mô hình của Google<br>Các mô hình Gemini của Google có gói miễn phí: Gemini Flash và Gemini Pro. | Trực tuyến \| Model của Google<br>Các model Gemini của Google có gói miễn phí: Gemini Flash và Gemini Pro. | Keep the established model loan consistent in provider descriptions. |
| Attach file (browse inside sidebar) | Đính kèm tệp (duyệt trong sidebar) | Đính kèm tệp (duyệt trong thanh bên) | Use thanh bên consistently for sidebar controls; detach remains distinct from pinning. |
| Commands: /model <name> · /mode [ask\|auto\|plan] | Lệnh: /model <tên> · /mode [ask\|auto\|plan] | Lệnh: /model <name> · /mode [ask\|auto\|plan] | Preserve the literal <name> command metavariable and matching markup. |
| Controls extended thinking budget and verification effort. | Điều chỉnh ngân sách suy nghĩ mở rộng và mức độ kiểm chứng. | Điều chỉnh hạn mức suy nghĩ mở rộng và mức độ kiểm chứng. | Reasoning budget is a processing allowance rather than money. |
| Ctrl+D to attach sidebar | Ctrl+D để gắn sidebar | Ctrl+D để gắn thanh bên | Use thanh bên consistently for sidebar controls; detach remains distinct from pinning. |
| Ctrl+D to detach sidebar | Ctrl+D để tách sidebar | Ctrl+D để tách thanh bên | Use thanh bên consistently for sidebar controls; detach remains distinct from pinning. |
| Ctrl+O to collapse sidebar | Ctrl+O để thu gọn sidebar | Ctrl+O để thu gọn thanh bên | Use thanh bên consistently for sidebar controls; detach remains distinct from pinning. |
| Ctrl+O to expand sidebar | Ctrl+O để mở rộng sidebar | Ctrl+O để mở rộng thanh bên | Use thanh bên consistently for sidebar controls; detach remains distinct from pinning. |
| Ctrl+P to pin sidebar | Ctrl+P để ghim sidebar | Ctrl+P để ghim thanh bên | Use thanh bên consistently for sidebar controls; detach remains distinct from pinning. |
| Ctrl+P to unpin sidebar | Ctrl+P để bỏ ghim sidebar | Ctrl+P để bỏ ghim thanh bên | Use thanh bên consistently for sidebar controls; detach remains distinct from pinning. |
| Maximum reasoning budget for exhaustive verification | Ngân sách suy luận tối đa để kiểm chứng toàn diện | Hạn mức suy luận tối đa để kiểm chứng toàn diện | Reasoning budget is a processing allowance rather than money. |
| Model default reasoning budget | Ngân sách suy luận mặc định của model | Hạn mức suy luận mặc định của model | Reasoning budget is a processing allowance rather than money. |
| Open the left sidebar pinned, reserving screen space for it | Mở sidebar trái ở trạng thái ghim, dành sẵn không gian màn hình cho nó | Mở thanh bên trái ở trạng thái ghim, dành sẵn không gian màn hình cho nó | Use thanh bên consistently for sidebar controls; detach remains distinct from pinning. |
| Refresh local Ollama models | Làm mới các model Ollama trên máy | Làm mới danh sách model Ollama trên máy | The action refreshes the model list, not downloaded model data. |
| Sidebar controls: | Điều khiển sidebar: | Điều khiển thanh bên: | Use thanh bên consistently for sidebar controls; detach remains distinct from pinning. |
| Stop and send voice input (Right click or Esc to cancel) | Dừng và gửi giọng nói (Nhấn chuột phải hoặc Esc để hủy) | Dừng và gửi văn bản nhận dạng giọng nói (Nhấn chuột phải hoặc Esc để hủy) | AI voice input sends recognized text, distinct from recorded phone voice notes. |
| [[ Command timed out after %1 s ]] | [[ Lệnh đã hết thời gian chờ sau %1 giây ]] | [[ Lệnh đã hết thời gian chờ sau %1 s ]] | Preserve the supplied seconds symbol s. |
| Usage checks are rate limited. Trying again soon. | Việc kiểm tra mức sử dụng đang bị giới hạn tần suất. Sẽ thử lại sau ít phút. | Việc kiểm tra mức sử dụng đang bị giới hạn tần suất. Sẽ sớm thử lại. | Soon does not promise a delay of several minutes. |
| Voice input could not read the Gemini API key because the keyring could not be unlocked. | Nhập bằng giọng nói không đọc được Gemini API key vì không thể mở khóa keyring. | Nhập bằng giọng nói không đọc được Gemini API key vì không thể mở khóa kho khóa. | Use the established Vietnamese keyring term in the error. |
| Only local models are allowed right now. To use online models, set AI to Yes in Settings > Interface > Left Sidebar. | Hiện chỉ cho phép model chạy trên máy. Để dùng model trực tuyến, hãy đặt AI thành Có trong Cài đặt > Giao diện > Left Sidebar. | Hiện chỉ cho phép model chạy trên máy. Để dùng model trực tuyến, hãy đặt AI thành Có trong Cài đặt > Giao diện > Thanh bên trái. | Localize the settings breadcrumb to match the actual sidebar label. |
| Updated %1 min ago | Cập nhật %1 phút trước | Cập nhật %1 min trước | Preserve the supplied minute symbol min. |
| Updated %1 h ago | Cập nhật %1 giờ trước | Cập nhật %1 h trước | Preserve the supplied hour symbol h. |

## Independent-review correction log

| Index | English key | Final correction and reason |
| --- | --- | --- |
| 79 | Online provider description, 1T model | Use Model consistently with the provider-description glossary. |
| 124 | On-screen display | Hiển thị trên màn hình names the OSD surface, which also supports gamma, rather than only volume/brightness. |
| 2440 | Free-tier pricing/instructions | Preserve creating a Google Cloud project or following the requested setup, replacing the vague “gì đó”. |
| 2514 | Thinking Level click-cycle tooltip | Translate the displayed effort labels; retain typed command syntax elsewhere. |
| 2729 | Command timed out after %1 s | Restore the supplied s unit symbol. |
| 2749 | Updated %1 min ago | Restore the supplied min unit symbol. |
| 2750 | Updated %1 h ago | Restore the supplied h unit symbol. |

All seven values were independently reread from the final catalog. Source checks
confirmed that count/contact/reply fallbacks compose acceptably. Raw Home and
think identifiers found by text search are not Translation.tr callers and were
not mistaken for user-facing catalog context.

## Intentionally English-identical entries

| Exact English key | Reason |
| --- | --- |
| Material cookie | Preserved product, provider, project, command, layout or named palette/shape. |
| API key:<br><br>```txt<br>%1<br>``` | Existing API key technical term plus protected fenced placeholder; no prose to translate. |
| Gamma | Gamma is the established image/color parameter name. |
| 12h am/pm | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Fruit Salad | Preserved product, provider, project, command, layout or named palette/shape. |
| OK | OK is an established acknowledgement label. |
| illogical-impulse | Preserved product, provider, project, command, layout or named palette/shape. |
| Dotfiles | Preserved product, provider, project, command, layout or named palette/shape. |
| Neutral | Preserved product, provider, project, command, layout or named palette/shape. |
| 12h AM/PM | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Anime | Anime is an established cultural loan. |
| Dock | Dock is the established desktop loan, distinguished from khay hệ thống. |
| Tonal Spot | Preserved product, provider, project, command, layout or named palette/shape. |
| Expressive | Preserved product, provider, project, command, layout or named palette/shape. |
| Superpaste | Preserved product, provider, project, command, layout or named palette/shape. |
| Rainbow | Preserved product, provider, project, command, layout or named palette/shape. |
| GitHub | Preserved product, provider, project, command, layout or named palette/shape. |
| Fidelity | Preserved product, provider, project, command, layout or named palette/shape. |
| Terminal | Terminal is an established computing loan. |
| Cloudflare WARP (1.1.1.1) | Preserved product, provider, project, command, layout or named palette/shape. |
| 24h | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Bluetooth | Preserved product, provider, project, command, layout or named palette/shape. |
| Pomodoro | Preserved product, provider, project, command, layout or named palette/shape. |
| AI | Preserved product, provider, project, command, layout or named palette/shape. |
| Cloudflare WARP | Preserved product, provider, project, command, layout or named palette/shape. |
| Monochrome | Preserved product, provider, project, command, layout or named palette/shape. |
| Windows | Preserved product, provider, project, command, layout or named palette/shape. |
| Android | Preserved product, provider, project, command, layout or named palette/shape. |
| Internet | Internet is an established network term. |
| EasyEffects | Preserved product, provider, project, command, layout or named palette/shape. |
| Google Lens | Preserved product, provider, project, command, layout or named palette/shape. |
| %1 nits | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| %1s | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| %1s… | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| %1… | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| 0° | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| 50 % APL  ·  %1 nits | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Cookie | Preserved product, provider, project, command, layout or named palette/shape. |
| dd/MM | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| dd.MM | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Emoji | Emoji is the established character-category term. |
| LCD HDR 1000 | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| LCD HDR 600 | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| MM/dd | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| OLED / QD-OLED | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| VRAM: | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Web | Web is an established Vietnamese computing loan. |
| DaVinci Resolve | Preserved product, provider, project, command, layout or named palette/shape. |
| DaVinci Resolve Studio | Preserved product, provider, project, command, layout or named palette/shape. |
| Celsius | Temperature-scale proper name. |
| Fahrenheit | Temperature-scale proper name. |
| Master | Preserved product, provider, project, command, layout or named palette/shape. |
| Monocle | Preserved product, provider, project, command, layout or named palette/shape. |
| OBS Studio | Preserved product, provider, project, command, layout or named palette/shape. |
| end-4 — Dotfiles | Preserved product, provider, project, command, layout or named palette/shape. |
| %1 (%2) | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
|  min | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Notch | Preserved product, provider, project, command, layout or named palette/shape. |
| Discord | Preserved product, provider, project, command, layout or named palette/shape. |
| min | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| GitHub Sponsors | Preserved product, provider, project, command, layout or named palette/shape. |
| Ko-fi | Preserved product, provider, project, command, layout or named palette/shape. |
| Patreon | Preserved product, provider, project, command, layout or named palette/shape. |
| CRT | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| updatems | Preserved product, provider, project, command, layout or named palette/shape. |
| updatems-system | Preserved product, provider, project, command, layout or named palette/shape. |
| macrecovery | Preserved product, provider, project, command, layout or named palette/shape. |
| AUR (yay/paru): | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Flatpak: | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Snap: | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Dotfiles (updatems): | Preserved product, provider, project, command, layout or named palette/shape. |
| <none> | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| GIMP | Preserved product, provider, project, command, layout or named palette/shape. |
| Krita | Preserved product, provider, project, command, layout or named palette/shape. |
| LibreOffice | Preserved product, provider, project, command, layout or named palette/shape. |
| OnlyOffice | Preserved product, provider, project, command, layout or named palette/shape. |
| Sunshine | Preserved product, provider, project, command, layout or named palette/shape. |
| Moonlight | Preserved product, provider, project, command, layout or named palette/shape. |
| Blender | Preserved product, provider, project, command, layout or named palette/shape. |
| 15 fps | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| 30 fps | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| WiVRn | Preserved product, provider, project, command, layout or named palette/shape. |
| Antigravity CLI — agy update | Preserved product, provider, project, command, layout or named palette/shape. |
| Antigravity: | Preserved product, provider, project, command, layout or named palette/shape. |
| Code | Preserve the existing code loan used by the AI sidebar. |
| Ollama | Preserved product, provider, project, command, layout or named palette/shape. |
| UltraCode | Preserved product, provider, project, command, layout or named palette/shape. |
| GIF | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Video | Video is an established media loan. |
| Instagram Reel | Preserved product, provider, project, command, layout or named palette/shape. |
| %1 B | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| %1 KB | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| %1 MB | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| %1 GB | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| LocalSend | Preserved product, provider, project, command, layout or named palette/shape. |
| RAM | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| CPU | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Ethernet | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Wi-Fi | Unit, format, acronym, placeholder-only label or literal updater sentinel. |
| Dynamic Island | Preserved product, provider, project, command, layout or named palette/shape. |
| Dwindle | Preserved product, provider, project, command, layout or named palette/shape. |

## Source ambiguities, terminology and limits

- Named identifiers remain recognizable: Dotfiles/dotfiles, Material cookie/Cookie, seven Material You palettes, Superpaste, scratchpad, submap, fake fullscreen, pseudo-tiling, Notch and Dynamic Island. Short Island compounds use đảo. Pill describes a con nhộng shape; Hug is giãn, distinct from Notch’s edge-flush outline.
- Workspace uses không gian làm việc; Sidebar uses thanh bên; Dock remains the familiar loan and System tray is khay hệ thống. Existing model/API key/token/code/terminal loans are retained where sound. Home is thư mục riêng.
- Blur/frost consistently uses làm mờ, dim uses làm tối, and opacity remains separate from transparency. The xray option samples the wallpaper directly rather than looking through it.
- Reasoning budget is hạn mức (processing allowance). Execution Plan is Kế hoạch; provider Plan means Gói đăng ký. Ordinary UI effort labels translate; literal accepted command values remain English.
- Current standalone Swap callers display memory statistics: bộ nhớ hoán đổi. Actual window-exchange actions use hoán đổi cửa sổ. This intentionally differs from the offline Spanish example’s unverified action assumption.
- Locked is shared between a lock state and a bind type; Đã khóa suits the state, while combined bind labels explain availability while locked. Launch on startup controls lock.launchOnStartup and therefore says Khóa khi khởi động.
- Play is shared between playback controls and a gaming welcome heading; Phát prioritizes playback. The source needs a distinct key for the gaming heading. Focus is Pomodoro concentration; window-focus phrases explicitly name selecting the window.
- The lookup has no plural API. Vietnamese nouns are invariant after counts, so natural counted wording works with both singular and plural runtime values. Existing singular/plural keys remain separate.
- AI voice input sends recognized text; phone voice notes send recordings. Streaming privacy hides Island presentation, not calls/messages on the phone; current detection checks Discord/OBS presence rather than an actual active stream.
- Sharing password source warns against accents and emoji, but the implementation permits printable ASCII only; the English should describe that full restriction. Clearing a firewall zone removes its assignment to the connection, not the zone definition.
- The old git stash list advice lists stashes rather than restoring them. Its command stays unchanged; a newer source key explicitly supplies show/pop commands. Old/new sidebar shortcuts and provider arguments remain as supplied.
- Snapshot boot entries Snapshots and linux stay literal. The legacy update-advice key contains literal \u2014; only its translated value uses normal punctuation. No stale/script keys were pruned.
- at is a battery percentage threshold, Up %1 is uptime, Free is available resources, weather Visibility is distance, Junction is GPU hotspot. Close audio/Wi-Fi labels close the corresponding panel rather than stopping the service.
- External country names come from iso3166.tab rather than this catalog. Product/model capability and price claims are translated as supplied, without external verification. Missing source context for legacy keys is an explicit review limit.

## Final catalog scan, 2026-10-31

Corrected legacy `Windows` from the product name to `Cửa sổ`, the generic application-window label. SharingConfig explicitly avoids that bare key for the operating-system name. The earlier allowlist entry above was incorrect. The final source has 3,256 keys and 101 intentional English-identical values; structural checks pass.

## Consolidated display-name pass, 2026-10-31

The current policy and approved terms are consolidated in [TERMINOLOGY.md](../../TERMINOLOGY.md). Earlier English-preservation rules and allowlists above are historical. The current pass changes 12 display values, preserving English keys, command syntax, identifiers and all formatting. These are self-reviewed working choices, not native-speaker-verified.

- "Material cookie" → "Bánh quy Material"
- "Fruit Salad" → "Salad trái cây"
- "Neutral" → "Trung tính"
- "Tonal Spot" → "Nhấn tông"
- "Expressive" → "Biểu cảm"
- "Rainbow" → "Cầu vồng"
- "Fidelity" → "Trung thực"
- "Cookie clock settings" → "Cài đặt đồng hồ Bánh quy"
- "Monochrome" → "Đơn sắc"
- "Use old sine wave cookie implementation" → "Dùng cách vẽ Bánh quy bằng sóng sin cũ"
- "Cookie" → "Bánh quy"
- "Notch" → "Tai thỏ"

Current intentionally English-identical count: 91. Names, units, literal formats and natural shared vocabulary remain valid; the lower count is not the purpose of this pass.
