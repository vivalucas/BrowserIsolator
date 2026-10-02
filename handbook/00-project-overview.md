# 项目定义

> 状态：已初始化；依据当前代码、`Info.plist`、SwiftPM 清单和 1.9.0 文档核对。

## 目标与边界

BrowserIsolator 是面向 Apple Silicon Mac 的原生浏览器环境管理工具。它在同一台 Mac 上运行多个彼此独立的 Google Chrome profile，让 Cookie、LocalStorage、密码、扩展配置和登录状态互不影响，减少多账号使用时反复登录和切换配置的成本。

主要用户是同时管理多个账号或客户环境的个人、运营人员和开发者。成功标准是：环境数据可靠隔离；创建、启动、关闭、命名、备注和删除路径清楚；高级模式不影响默认兼容性；配置损坏时尽量保住磁盘中已有环境。

项目明确不承诺绕过网站风控或防止封号，不提供代理/VPN、扩展管理、跨设备数据同步和精确的 Chrome 窗口编排。Chrome 本身不由本项目维护。

核心术语：

- **环境 / Profile**：一个 `pN` 配置项及对应的独立 Chrome 用户数据目录。
- **基础模式**：只隔离 profile，不开放 CDP、不注入页面脚本。
- **采集模式**：开放仅绑定 `127.0.0.1` 的 CDP 端口，供本机采集工具使用，不修改 `navigator`。
- **差异模式**：开放 CDP，并注入稳定的 `hardwareConcurrency` 和 `deviceMemory`。

详细能力和验收边界见 [02 功能设计](02-function-design.md)。

## 技术与平台

| 项目 | 实际选择 | 版本 / 配置依据 | 核对日期 |
| --- | --- | --- | --- |
| 语言与构建 | Swift 6、Swift Package Manager | `BrowserIsolator/Package.swift`（tools 6.0） | 2026-09-22 |
| UI | SwiftUI，必要处桥接 AppKit / ApplicationServices | `App.swift`、`BrowserManager.swift` | 2026-09-22 |
| 并发 | `BrowserManager` 使用 `@MainActor`；`FingerprintInjector` 使用 actor | 源码 | 2026-09-22 |
| 外部依赖 | Sparkle 2.7.0 起，解析版本由锁文件固定 | `Package.swift`、`Package.resolved` | 2026-09-22 |
| 平台 | macOS 13+、发布目标 arm64 | `Package.swift`、`Info.plist`、构建脚本 | 2026-09-22 |
| 数据 | JSON 配置 + UserDefaults + profile 目录；无数据库 | `Models.swift`、`App.swift` | 2026-09-22 |
| 发行 | GitHub Actions、GitHub Releases、Sparkle appcast | `.github/workflows/*.yml` | 2026-09-22 |

发布包仅支持 Apple Silicon。Google Chrome 使用官方 Universal DMG，但本项目自身不声明 Intel Mac 支持。Windows 版属于独立项目；本仓库只维护必要的行为契约对齐。

通用本地网页自动化接口已加入产品边界，见 [14](14-automation.md)；调用方负责网站业务策略和程序编排。
