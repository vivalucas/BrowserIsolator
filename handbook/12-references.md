# 外部服务与参考资料

> 适用状态：启用。外部信息会变化，修改相关实现前重新核对官方资料。

| 服务 / 资料 | 官方来源或原件位置 | 本项目用途 | 当前实现入口 |
| --- | --- | --- | --- |
| Sparkle | [官方文档](https://sparkle-project.org/documentation/) | App 内更新、appcast 生成与 EdDSA 校验 | `Package.swift`、`App.swift`、`Info.plist`、Release workflow |
| GitHub Releases | [官方文档](https://docs.github.com/en/repositories/releasing-projects-on-github) | 托管 DMG 和 appcast | `.github/workflows/release.yml` |
| Chrome DevTools Protocol | [官方协议文档](https://chromedevtools.github.io/devtools-protocol/) | 本机 target 发现、事件监听和脚本注入 | `FingerprintInjector.swift` |
| Google Chrome | [官方产品页](https://www.google.com/chrome/) | 独立浏览器引擎 | `BrowserManager.chromeDownloadURL` |
| Windows/macOS 对齐说明 | [仓库文档](../docs/windows-alignment.md) | 模式、端口、参数和平台差异契约 | 测试与 BrowserManager |
| 1.9.0 发行说明 | [仓库文档](../docs/release-notes-1.9.0.md) | 当前功能与配置恢复变化 | 用户发布说明 |

## 采用边界

- Sparkle feed 是公开资源；私钥只在 GitHub Actions Secret 中，公钥在 `Info.plist`。
- GitHub 最新 Release API 只用于应用自己的轻量版本提示；实际应用内安装由 Sparkle 处理。
- CDP 无认证，因此必须仅监听 loopback。项目只使用 target 管理、Page 和 Runtime 相关能力，不把完整协议镜像进仓库。
- Chrome 使用官方 Universal Stable DMG，但 BrowserIsolator 发布包仍仅支持 arm64。项目当前验证可执行文件和安装结果，尚未强校验 Team ID。
- 外部服务地址、Sparkle API 或 GitHub Actions 版本变化时，以官方资料和当前锁文件为准，不沿用旧日志中的缓存描述。
