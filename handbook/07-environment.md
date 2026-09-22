# 环境、换机与运维

> 适用状态：启用。项目只支持 macOS；Windows 和 Ubuntu 开发/运行不适用。

## 环境矩阵

| 环境 | 工具链依据 | 安装与启动入口 | 已验证范围 |
| --- | --- | --- | --- |
| Apple Silicon macOS 13+ | Swift 6 / SwiftPM；Xcode 或 Swift 工具链 | `Package.swift`、`build.sh` | CI 在 macOS 14 测试并构建 arm64 Release |
| Intel macOS | 无发布目标 | 不支持 | 未验证 |
| Windows / Ubuntu | 非本项目平台 | 不适用 | 独立 Windows 项目不代表本仓库通过 |

## 首次开发

```bash
git clone https://github.com/vivalucas/BrowserIsolator.git
cd BrowserIsolator/BrowserIsolator
swift test
swift build
```

生成可双击 `.app` 时在仓库根目录运行 `./build.sh`。脚本执行 arm64 Release 构建、复制 Sparkle framework 和资源，并进行 ad-hoc 签名。日常源码开发也可用 Xcode 打开 `BrowserIsolator/Package.swift`。

依赖版本由 `Package.swift` 和 `Package.resolved` 管理。换机时重新解析/构建，不复制 `.build`、`.swiftpm` 或 `.app`。构建结束若产物不需要交付，应清理并检查：

```bash
find . -maxdepth 3 \( -name '.build' -o -name 'BrowserIsolator.app' -o -name '*.dSYM' -o -name '.swiftpm' \) -print
```

SwiftPM 构建缓存可能保存 checkout 的绝对路径。仓库移动后若出现指向旧目录的 XCFramework 错误，先确认没有需要保留的构建任务，再使用新的 scratch path 或清理并重新解析缓存；不要把 `.build` 从旧设备复制过来。

## 配置与本机数据

运行时无必需环境变量。开发机配置和用户数据位于 `~/Library/Application Support/BrowserIsolator/`，不是仓库内容。语言、外观、窗口布局及默认外链环境使用 UserDefaults。

发布 workflow 需要 GitHub Actions Secret `SPARKLE_PRIVATE_KEY`；它只用于生成签名 appcast，不得写入仓库、handbook 或本机共享配置。CI 的普通测试与构建不需要该密钥。

首次运行会从 Google 官方地址下载 Chrome；离线开发可以编译和运行测试，但无法验证下载、安装和真实 profile 流程。手动 Chrome 安装和用户使用方法见根 [README](../README.md)。
