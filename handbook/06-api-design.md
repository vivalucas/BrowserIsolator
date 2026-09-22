# 接口约定

> 适用状态：启用。本项目不提供公网业务 API；接口主要是本机 CDP、系统 URL 事件和外部更新服务。

| 能力 / 操作 | 实现或契约入口 | 调用方 | 当前状态 |
| --- | --- | --- | --- |
| Chrome 启动参数 | `browserLaunchArguments` | BrowserManager / 兼容契约测试 | 稳定 |
| 模式首选端口 | `preferredDebugPort` | BrowserManager / 兼容契约测试 | 稳定 |
| CDP target 查询与 WebSocket | `FingerprintInjector.swift` | 差异模式 | 稳定，失败降级 |
| 外部 http/https URL | `CFBundleURLTypes`、`AppDelegate.application(_:open:)` | macOS Launch Services | 稳定 |
| GitHub 最新 Release API | `BrowserManager.checkForUpdates` | 设置和菜单栏的检查入口 | 公开、无认证 |
| Sparkle appcast | `Info.plist` 的 `SUFeedURL` / `SUPublicEDKey` | Sparkle | 稳定、EdDSA 校验 |
| Chrome 下载 | `chromeDownloadURL` | BrowserManager | 官方 HTTPS DMG |

## CDP 契约

- 端点只在高级模式需要时开放，并显式绑定 `127.0.0.1`；不提供远程访问或认证。
- 采集工具使用实际分配端口。首选端口规则见 [02](02-function-design.md)，冲突回退后不能继续假定固定端口。
- 差异模式通过 browser-level WebSocket 监听 target 事件，并对 page target 发送 `Page.addScriptToEvaluateOnNewDocument` 和 `Runtime.evaluate`。
- 轮询和 WebSocket 响应必须有超时、有限重试和清理；断线可重连，失败不得阻塞基础浏览器环境。

## 外部服务和兼容

- 客户端读取公开 GitHub 资源，不携带仓库凭据。发布阶段的权限和 Sparkle 私钥只存在于 GitHub Actions。
- 下载只接受成功 HTTP 响应及合理的 DMG MIME 类型，安装后验证 Chrome 可执行文件；当前尚未强校验 Team ID。
- 外部 URL 只接受 http/https，并由应用级默认浏览器注册转发到配置中的环境；macOS 不支持把单个 profile 注册为独立默认浏览器。
- 改变端口、启动参数、配置字段或 URL 行为前，检查所有调用方、兼容测试、README 和 Windows 对齐文档。
