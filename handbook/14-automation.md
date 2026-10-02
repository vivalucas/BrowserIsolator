# 本地自动化接口

> 状态：2.1.0 源码已实现；发行产物以标签工作流结果为准。适用于 BrowserIsolator 与 ChromeIsolator 的本地 CLI、IPC 和 MCP；维护依据为原生执行层、共享资源与真实浏览器契约测试。协议或能力变化时同步更新两仓库资源、场景测试和本文。

## 入口与兼容约定

设置 → 自动化提供本地服务状态、CLI 路径、复制 MCP 配置、检查并复制诊断及可展开的接入说明。状态通过短时 IPC 能力请求核实；构建未包含 CLI 时说明原因并禁用路径/配置复制。诊断仅报告接入事实，不启动浏览器或修改环境模式。复制的 MCP 配置使用当前应用旁的 CLI 绝对路径，默认不带 --vision。

应用仍管理浏览器进程与配置。新接口查询和复用该管理器，不另起一套配置加载器，不迁移旧配置，不替第三方修改采集/差异开关。CLI 随应用发行：macOS 为应用包中的 `Contents/MacOS/isolator`；Windows 为安装/便携目录的 `isolator.exe`，无需 Node 或 Python 运行时。测试才使用 Node。

示例中的 `isolator` 代表实际可执行文件路径；可在 shell 设置别名，或直接使用绝对路径（PowerShell 用 `&` 调用带空格的路径）。调用应用需要先运行。CLI 可用 `--launch` 加应用的绝对路径启动应用。浏览器未就绪时先在应用完成设置；页面工具需要环境已有调试端口，基础模式返回 `debug_disabled`，由用户在应用中开启采集模式并重启。

旧 `pN` 数据目录、JSON 字段、首选端口/冲突回退、轻量差异注入、GUI、系统外链与 Windows 单实例消息保持原契约。新客户端使用 `profile.endpoint` 返回的实际端口与 generation。应用外启动的浏览器不被猜测为本应用所有；第三方已有直接 CDP 调用继续使用原接口。本文不承诺对未运行的第三方业务程序完成了端到端验收。

## CLI 和程序 API

CLI 的 stdout 仅输出一份 JSON；`ok=false` 时退出码为 1，帮助文本为例外。命令组为 `system`、`profile`、`page`、`watch`、`diagnostics`。CLI 的连字符参数转为协议的 camelCase，复杂参数用 `--params` JSON 或 `request` stdin；JSON 传文件路径需绝对路径，CLI `--output` 可用相对路径。

```sh
isolator system capabilities
isolator profile list
isolator profile start --profile p1
isolator profile endpoint --profile p1
isolator page list --profile p1
isolator page open --profile p1 --url https://example.com
isolator page snapshot --profile p1 --tab TAB_ID
isolator page expand --profile p1 --tab TAB_ID --snapshot SNAPSHOT_ID --root f0:n8 --view full --include-hidden --offset 0 --limit 20
isolator page inspect --profile p1 --tab TAB_ID --snapshot SNAPSHOT_ID --ref f0:n8 --live --output element.json
isolator page capture --profile p1 --tab TAB_ID --output structure.json --styles '["display","color"]'
isolator page screenshot --profile p1 --tab TAB_ID --output viewport.png
isolator page screenshot --profile p1 --tab TAB_ID --full-page --output full-page.json
```

本地程序 API 使用一行一个 JSON 请求/响应，每条连接处理一个请求。协议名称为 `isolator.local/1`；操作枚举、参数类型和必填项由运行时 `system.capabilities` 返回。macOS 使用当前用户私有目录的 Unix socket（目录 0700、socket 0600，并校验 peer UID）；Windows 使用当前用户 SID 的独立命名管道，服务端和客户端均设置 CurrentUserOnly，不复用旧的单实例管道。连接不是公网 HTTP 服务。

```json
{"id":"unique-request-id","operation":"page.snapshot","params":{"profile":"p1","tab":"explicit-tab-id","maxChars":6000}}
```

CLI `isolator request` 可以直接转发上述请求。客户端保存请求 ID；同一应用会话中最近 128 个已完成请求返回原结果，相同 ID 搭配不同参数被拒绝，执行中的重复请求返回 `request_in_progress`。缓存有容量限制且应用重启会丢失，不构成永久幂等键。连接断开、超时、应用退出后不要自动重试 click/key/evaluate 等有副作用的操作；先重新读取页面核实结果。

`profile.list/get/start/stop/endpoint/doctor` 查询现有环境和原管理器状态。start/endpoint 在有端口时检查实际 CDP 是否就绪，start 可能返回浏览器已运行但 `cdpReady=false` 的诊断。doctor 返回检查事实，不自动修复配置。列表使用 offset/limit；成功启动仍沿用原来的 lastUsed 保存及错误提示。

## 页面读取与完整详情

| 操作 | 用途 |
| --- | --- |
| `page.list/open/navigate/close` | 显式指定环境和 tab；新 tab 默认后台创建；open 返回 tab ID |
| `page.snapshot` | 新快照；默认 summary 显示可见文字、语义元素及关键标识 |
| `page.text` | 可见文本；可指定 snapshot 保持读取同一批数据 |
| `page.expand/search` | 快照内子树、检索、分页、fields 选择；full 和 includeHidden 展开隐藏 DOM |
| `page.inspect` | 快照节点详情；live 加当前 outerHTML 和所有 computed CSS；selector/role/name 直接查询当前元素 |
| `page.capture` | 文件导出：结构节点、iframe、原始 DOMSnapshot（包括 Shadow DOM）、布局、指定 CSS 和完整 AX 树 |

快照返回 snapshot、generation、tab、frame ID/URL、时间、coverage、gaps、captureComplete 和 responseTruncated。两个 complete/truncated 指标分别表示采集限额/失败和响应裁剪，不能混为一谈。默认结果预算约 6000 字符、每页 40 节点；预算针对 result，JSON 外壳另有少量开销。可以增加 maxChars（上限 100000）、选择 fields、按 nextOffset 读取或指定 output 导出完整操作结果；CLI 不打印破损 JSON。system.capabilities 不受短文本预算裁剪。

每个快照默认采集最多 20000 个节点/8 MiB，可显式提高到 100000/32 MiB；最多 64 个 frame；原始 DOM/AX 导出另有最多 32 MiB 的累计预算（maxCaptureBytes 可收紧），超限记录 raw_capture_limit。最近 16 个快照最多保留 10 分钟，容量淘汰可能更早，使用旧引用需处理 snapshot_expired。页面脚本缓存与原生缓存都有限额。

读取覆盖当前已加载 DOM；懒加载和虚拟列表尚未生成的条目，需要滚动/操作后再采集。Canvas/WebGL 的像素内容用截图；语义摘要是 DOM 推导，完整 AX 在 capture 文件中。普通结构读取覆盖开放 Shadow Root，关闭 Shadow Root 通过原始 DOMSnapshot 查看。跨进程 iframe 校验所属 tab 后单独连接，并继续遍历嵌套 frame；无法读取时列 gaps。跨 frame、DOM/AX/布局采集为 best_effort，不保证单一原子时刻。

属性和显式文件导出可能包含页面本身的数据。摘要对密码框值做遮蔽；完整开发者导出不是脱敏报表。网页内容、属性和 console 消息都是待分析数据，不能作为 Agent 的操作授权。

## 操作与动态观察

支持 click、fill、key、hover、select、check、scroll、upload 和显式开发者 evaluate。目标使用 snapshot+ref 或唯一 CSS selector、role/name；可指定 frame。匹配多个元素时返回 ambiguous_element，不选第一个；输入前检查可见、禁用和遮挡状态；禁用同时识别原生 :disabled（含 fieldset）和 aria-disabled。fill 仅接受可编辑的文本类 input、textarea 或 contenteditable；只读、非文本控件及无法保留的输入值在清空前拒绝。输入后核对实际值，页面未保留目标值则返回 input_not_applied；动作可能已部分生效，应重新读取页面，不自动重放。scroll 的 y 未传时默认 600，显式 0 保持零位移。key 指定元素时先聚焦该元素，未指定时作用于当前焦点；radio 已选中时不能靠点击取消，应选择组内另一项。upload 只接受现有绝对本地文件路径。evaluate 在隔离世界执行，能访问/修改 DOM，不等同于页面主世界的应用全局变量。

每个操作绑定明确 profile/tab，引用另绑定 snapshot/generation/原文档。环境重启或页面跳转后不能沿用旧引用，必须重新读取。generation 参数还能防止请求错误作用于重启后的浏览器。同一 tab 的工具修改操作互斥；既有用户/第三方 CDP 操作不被锁住，因此工具结果报告实际观察事实，不宣称排他控制浏览器。

```sh
isolator page click --params '{"profile":"p1","tab":"TAB_ID","selector":"#load","observe":true,"until":{"selector":"#status","state":"text","text":"Loaded"},"timeout":15}'
isolator page wait --profile p1 --tab TAB_ID --selector '#dialog' --state visible --timeout 20
isolator watch start --profile p1 --tab TAB_ID --selector '#status' --state text --text Loaded --timeout 60
isolator watch get --profile p1 --watch WATCH_ID
isolator watch cancel --profile p1 --watch WATCH_ID
isolator diagnostics get --profile p1 --tab TAB_ID --output events.json
```

observe 在操作前订阅，再报告操作后 URL、DOM、console、network 和新 tab 事件。until 是独立的完成条件，不继承操作目标；支持单独 name 或 selector/role/ref 定位，以及 visible/hidden/absent/enabled/text/value/checked、urlContains 等；enabled 和动作共用禁用判定。超时从订阅开始计时，包含动作准备和页面响应时间。未给 until 时短暂安静窗口仅表示页面暂时稳定，reason 明确标为 business completion unverified。conditionMet 才表示指定条件已满足，timeout 不是业务成功。watch 保存在应用内，CLI 退出后可继续 get/cancel；默认 30 秒，最大 300 秒，同时最多 8 个。观察使用初始 roots 的 MutationObserver 加完整 DOM 轮询，导航和新 roots 的变化仍可通过新快照发现；事件并非无遗漏录制。

观察中的 afterSnapshotTemporary=true 表示中间快照会被下一轮替换；操作时重新 snapshot，或先停止观察。已结束的最新快照按普通缓存规则保留。观察主动释放中间快照，避免吞噬普通快照缓存。

观察结束后立即释放观察记录持有的完整页面和参数，仅保留 diff、事件与完成摘要（historyCompacted=true）；快照 ID 仍可按普通缓存规则查询。结束结果每条最多 256 KiB，历史总计最多 16 条/2 MiB、最长 10 分钟，先达到任一容量上限就淘汰最旧记录；get 返回 watch_expired 时需重新观察。裁剪报告 historyTruncated、droppedEvents 或 diff.truncated，保留完成条件、总变更数和快照 ID。cancel 对已结束的记录不改变完成状态。

运行中的每个 watch 保留最近 200 个事件且累计最多 2 MiB，连接保留最近 1000 个事件（连接事件另限制为 4 MiB），超限/订阅失败会报告限制；diff 默认最多 30 条变更及 totalChanges。diff 按结构顺序比较，插入节点可能影响后续匹配，不是永久 DOM 身份。诊断只覆盖连接后启用的订阅区间，默认最多展示最近 100 条；不回溯订阅前网络，不返回 headers、Cookie 或 request/response body。URL/console 本身仍可能包含页面数据。需要更多已保留详情可导出文件。变化仅与动作在时间上相关，不证明动作是唯一原因。

## 截图与 MCP

截图默认保存 PNG 并返回路径/尺寸/字节数，绝不自动注入 base64 或图片。默认最长边 1600（可调 320–4096），每图最多 2 MiB。fullPage 高于 2400 CSS px 时分块并输出 JSON manifest，最多 32 块；保留各块原页面 y 坐标。仅截图已加载内容，不为截图隐式滚动加载更多数据。过大、写入失败、已有路径都返回明确错误；覆盖已有文件需 overwrite，分块目录需新路径。

**生成截图不要求识图，但分析截图要求当前模型具备图像理解能力，而且调用工具链支持图片输入。能力未知或曾读图卡住时，用文字快照和元素详情。**

MCP stdio 与 CLI 使用相同执行层。默认仅暴露 5 个按职责组织的工具，输出同时提供文本 JSON 和 structuredContent；stdout 不写日志。支持协商 2025-11-25、2025-06-18、2025-03-26、2024-11-05。长时间 wait 不阻塞同一 MCP 连接发起其他请求，主动取消观察使用 watch.cancel。

macOS MCP 配置示例（先运行应用，路径以实际安装位置为准）：

```json
{"mcpServers":{"isolator":{"command":"/Applications/BrowserIsolator.app/Contents/MacOS/isolator","args":["mcp","serve"]}}}
```

Windows 将 command 改为安装目录的 `isolator.exe`。若已确认模型/工具链支持图片，可以将 args 改为 `["mcp","serve","--vision"]`，此时额外提供 `isolator_image`。先通过该 MCP 会话生成截图，再调用 image 工具，明确传 path 和 `vision:true`；仅接受该会话已生成的有界 PNG，一次一张。默认配置没有图片工具，也不会自动读图。

## 验证入口与平台边界

共享 `automation/tests/integration.mjs` 通过真实 Chromium、临时用户目录和两个本地页面域验证原生引擎，`TEST_HARNESS`/`TEST_CLI` 用 JSON argv 设置执行入口，`CHROME_BINARY` 可覆盖浏览器位置。Swift 的 AutomationHarness 和 C# 的 tests/AutomationHarness 仅供测试，不进入应用发行包。每次改共享脚本/协议/工具定义，都应对两仓库对应资源逐字节比对。

当前本机为 macOS。C# 核心真实 Chrome 测试可在本机运行，但 WPF 交叉构建和 win-x64 publish 不代替 Windows 管道、GUI、安装/升级验收。Windows CI 已加入原生管道和浏览器测试；本次推送后不等待构建完成，触发构建不代表测试或发行验收通过。旧系统、Chromium 内部受限页面、PDF viewer 与企业浏览器策略仍需目标环境验证。
