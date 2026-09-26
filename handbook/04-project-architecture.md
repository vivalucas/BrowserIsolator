# 架构约定

> 适用状态：启用。这里维护当前边界；完整目录树由仓库本身提供。

## 系统边界

| 模块 / 目录 | 职责 | 主要依赖 | 不承担什么 |
| --- | --- | --- | --- |
| `App.swift` | 应用生命周期、主窗口、菜单栏、设置和 Sparkle UI | BrowserManager、Localization、Sparkle、AppKit | 配置文件细节和 CDP 协议实现 |
| `UIComponents.swift` | 共享控件尺寸、动作按钮样式与状态 | SwiftUI、系统颜色 | 业务命令和配置读写 |
| `BrowserManager.swift` | Chrome 生命周期、端口、下载、外链、环境状态 | Models、FingerprintInjector、Foundation/AppKit | 具体视图布局 |
| `FingerprintInjector.swift` | browser-level CDP 连接、target 跟踪和脚本注入 | URLSession WebSocket | profile 数据和 UI 状态 |
| `Models.swift` | Profile/AppConfig、路径和 JSON 恢复 | Foundation、文件系统 | 进程管理 |
| `Localization.swift` + `Resources` | 语言选择和本地化资源 | UserDefaults / Bundle | 业务状态 |
| `Tests` | 跨平台兼容契约 | XCTest、可测试的纯函数 | 完整 UI / 系统集成测试 |

## 关键路径

```text
SwiftUI / MenuBar / URL event
            │
            ▼
BrowserManager (@MainActor)
  ├─ Process → 独立 Google Chrome + Profiles/pN
  ├─ ConfigStore → config.json / .bak / 磁盘重建
  └─ FingerprintInjector (actor) → 本机 CDP WebSocket
```

- `BrowserManager` 是界面状态的权威来源；所有 `@Published` 状态在主 actor 更新。
- `FingerprintInjector` 以 actor 隔离连接、重连、pending response 和 target 状态；UI 不直接操作 WebSocket。
- Chrome 进程按 profile 分开，profile 目录是隔离边界；应用退出和全部关闭需要集中收口进程。
- 外部链接由 `AppDelegate` 接收，经 `BrowserManager` 校验和选择环境；启动中的链接通过 `pendingExternalURLs` 排队。
- 配置数据由 `ConfigStore` 独占读写与恢复；UserDefaults 只保存语言、外观、窗口布局、默认外链环境等偏好。

## 约束与演进

当前 `BrowserManager` 职责较多。只有出现可验证的维护或测试收益时才拆分，拆分后仍保持单一 UI 状态来源，不创建平行管理器。模式端口计算和 Chrome 参数保留为可测试纯函数，跨平台契约变化必须先更新测试。
