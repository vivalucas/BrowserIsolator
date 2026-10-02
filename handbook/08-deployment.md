# 部署、发行与恢复

> 适用状态：启用。这里的“部署”指 macOS 安装包发行，不涉及服务器。

## 当前发行链路

- 版本来源：根 `Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion`。
- 触发关系：普通 push 到 `main` 只运行 CI；推送 `v*` 标签会运行 Release workflow 并创建 GitHub Release。
- 产物：arm64 `BrowserIsolator.dmg` 和由 Sparkle 工具签名的 `appcast.xml`。
- 更新地址：`https://github.com/vivalucas/BrowserIsolator/releases/latest/download/appcast.xml`。
- 当前源码版本：2.1.0（build 48），发行标签为 `v2.1.0`；本次推送后不等待远端构建完成。
- 最近已核验的发布版本：[2.0.0（build 47）](https://github.com/vivalucas/BrowserIsolator/releases/tag/v2.0.0)。DMG 与签名 appcast 已上传，更新源版本和下载地址已核对；发行包安装与跨版本更新尚未验收。发布应用使用 ad-hoc code signing，未做 Apple 公证。

## 发布流程

1. 确认本轮已获版本发布授权，工作区和目标分支明确。
2. 更新 `Info.plist` 的短版本和 build 号；同步用户可见 release notes 与必要文档。
3. 在 `BrowserIsolator/` 运行 `swift test`，并执行 arm64 Release 构建；检查三种语言资源和用户主路径。
4. 提交版本变更，创建与短版本一致的 `vX.Y.Z` 标签，推送当前分支和标签。
5. 观察 `.github/workflows/release.yml`：测试 → 构建 → 打包 → ad-hoc 签名 → DMG → 签名 appcast → GitHub Release。
6. 从 Release 下载产物，验证安装、启动、检查更新和主要环境操作；仅 workflow 成功不等于发行验收完成。

普通提交推送不授权改版本、打标签或创建 Release。`SPARKLE_PRIVATE_KEY` 必须与 `Info.plist` 中 `SUPublicEDKey` 匹配；私钥丢失后不能继续给已安装版本提供受信更新，需要通过一次人工安装迁移公钥。

## 回滚与恢复

- 代码可从已知良好标签重新构建并手动创建 Release，但不得移动或覆盖已发布标签。
- Sparkle 默认向用户提供最新 appcast；要回退需确认版本比较、appcast 和用户数据兼容，不能只上传旧 DMG。
- 配置格式目前向后兼容。任何不兼容数据变化必须在发布前提供备份、迁移和回滚说明。
- Chrome 安装时先移动旧 `Chromium/` 到 `Chromium.backup/`，新副本验证成功后删除备份；失败则恢复旧副本。这是运行时安装恢复，不是 Release 回滚。

## 验证边界

CI 使用 `macos-14` 并显式选择 Xcode 16.2（Swift 6）；发布目标是 `arm64-apple-macosx13.0`。真实 macOS 13、Sparkle 跨版本更新、Gatekeeper、Chrome 下载和系统默认浏览器行为仍需要人工验证。Intel Mac、Windows 和 Ubuntu 不在发布范围。

## CLI 随包发行

macOS 的本地和 Release 打包均复制 `isolator` 至 Contents/MacOS，并复制 SwiftPM 核心资源 bundle 至 Contents/Resources，随应用一起签名。Windows publish 在同一输出目录发布 GUI 与独立控制台 CLI，资源嵌入程序集；ZIP 与 MSI 的现有文件收集逻辑一并包含 CLI。2.1.0 通过同版本标签触发发行构建；构建成功与安装验收需另行确认。接入见 [14](14-automation.md)。
