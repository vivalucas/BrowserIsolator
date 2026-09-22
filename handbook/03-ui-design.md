# UI 与交互约定

> 适用状态：启用。当前代表页面是主窗口与独立设置窗口，入口均在 `App.swift`。

## 设计方向

保持原生 macOS 工具的清晰、克制和低干扰：左侧快速扫描环境，右侧完成当前环境的主要操作；设置集中承载低频全局能力。SwiftUI 为主，确需窗口、点击或系统 URL 行为时桥接 AppKit，不为了纯 SwiftUI 形式牺牲响应和平台习惯。

| 内容 | 唯一维护位置 / 参考 |
| --- | --- |
| 应用与窗口结构 | `BrowserIsolator/Sources/BrowserIsolator/App.swift` |
| 文案和 7 种语言 | `Localization.swift` 与 `BrowserIsolator/Resources/*.lproj` |
| 外观模式 | `AppAppearance`、`applyAppAppearance`、`AppStorage("AppAppearance")` |
| 主窗口尺寸与分栏 | `WindowFrameAutosaveView`、`WindowFrameStore`、`MainSidebarWidth` |
| 公共设置行和按钮样式 | `SettingsSection`、`Settings*Row`、`SettingsActionButtonStyle` |
| 当前认可页面 | `MainView`、`ProfileInspectorView`、`SettingsView` |

## 页面与交互规则

- 主窗口维持“列表 + 详情”结构：列表负责选择和快速操作，详情负责当前环境的信息、主要动作和恢复提示。
- 运行状态、启动中、关闭中、失败和禁用态要可区分；危险操作使用红色语义，添加环境使用明确主操作色，设置保持中性。
- 删除环境必须确认，且启动中、运行中、关闭中的环境不可删除；真实删除使用废纸篓以保留恢复机会。
- 模式管理保持“设置摘要 + 二级管理窗口”，支持搜索、仅显示可编辑环境和采集批量操作，不把全部环境直接铺在设置首页。
- 调试端口属于高级信息，只在运行且需要 CDP 时展示实际分配值；不要把首选端口冒充实际值。
- 主窗口位置、尺寸和左右分栏宽度应恢复到可用屏幕范围内；屏幕布局变化时必须约束无效旧坐标。
- 外观切换同时更新 SwiftUI `colorScheme` 和 AppKit `NSApp` / `NSWindow` appearance，避免设置窗和动态系统色半切换。
- 文案使用各语言自然的 UI 说法，不按中文逐字翻译；新增键必须覆盖所有七种语言。

## 验收

UI 改动至少检查：启动/关闭/全部关闭、选择和二次点击、重命名、备注、删除确认、模式禁用原因、空搜索、配置错误、下载错误、外部链接提示、更新提示、浅色/深色和窄窗口。环境可运行时查看真实界面；仅完成构建或静态检查时标明视觉未验收。
