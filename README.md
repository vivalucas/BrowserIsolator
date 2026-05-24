# 浏览器多开 (BrowserIsolator)

在一台 Mac 上同时运行多个彼此独立的 Chrome 环境。每个环境都有自己的 Cookie、LocalStorage、密码、扩展配置和登录状态，适合同时管理多个账号，而不用反复登录、退出或切换浏览器配置。

[English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Русский](README.ru.md)

BrowserIsolator 的定位很简单：做好本地浏览器环境隔离。它不是复杂的反检测平台，也不承诺绕过网站风控；它只是把多个浏览器环境清楚地分开，让日常多账号使用更稳定、更省心。

## 主要功能

- **独立环境**：每个环境使用单独的 Chrome 数据目录，登录状态、Cookie、缓存、密码和扩展配置互不影响
- **快速启动和关闭**：在主窗口或菜单栏启动、关闭单个环境；也可以双击左侧环境行启动，或一次关闭全部环境
- **专业管理界面**：左侧环境列表用于快速扫描，右侧详情栏展示路径、调试端口、错误、操作和高级信息
- **自定义命名和备注**：新增环境后可以直接命名，也可以之后重命名或添加备注，方便对应不同账号、客户或用途
- **安全删除**：删除环境需要输入环境名称确认，数据会先移到废纸篓
- **轻量环境差异**：为不同环境注入稳定的 `navigator.hardwareConcurrency` 和 `navigator.deviceMemory` 值，并持续处理新打开的标签页
- **外部链接转发**：可以把 BrowserIsolator 设为系统默认浏览器，并指定外部链接默认进入哪个环境
- **自动浏览器安装**：首次运行时自动下载官方 Google Chrome 到应用数据目录
- **设置面板**：查看 Chrome 状态和版本、打开数据目录、复制路径、重新下载 Chrome、配置外部链接、切换语言、外观模式、高级详情显示，以及版本更新、作者和反馈入口
- **本地优先**：配置、浏览器和环境数据都保存在本机，不上传、不收集用户数据

## 系统要求

- macOS 13 Ventura 或更高版本
- Apple Silicon Mac（M1 及以上）

当前发布包按 `arm64-apple-macosx13.0` 构建，不支持 Intel Mac。

如果你需要 Windows 版本，可以参考另一个项目：[MoeMoeGit/ChromeIsolator](https://github.com/MoeMoeGit/ChromeIsolator)。

## 安装

### 方式一：下载 DMG

1. 打开本仓库的 [Releases](../../releases) 页面，下载最新的 `BrowserIsolator.dmg`
2. 打开 DMG，将 `BrowserIsolator.app` 拖入 Applications 文件夹
3. 首次启动时，如果 macOS 提示“无法验证开发者”或“应用已损坏”，这是未公证应用常见的 Gatekeeper 拦截。可以执行：

   ```bash
   xattr -cr /Applications/BrowserIsolator.app
   ```

   然后重新打开应用。也可以在 Finder 中右键应用，选择“打开”，再在弹窗中确认。

后续应用版本更新可以在应用内进入 **设置 -> 关于与支持 -> 检查更新**。BrowserIsolator 使用 Sparkle 从 GitHub Releases 获取更新；首次安装仍需要从 Releases 下载 DMG。

### 方式二：自行编译

如果只需要生成可执行文件：

```bash
cd BrowserIsolator
swift build -c release -Xswiftc -target -Xswiftc arm64-apple-macosx13.0
```

产物位于：

```bash
BrowserIsolator/.build/release/BrowserIsolator
```

如果需要生成可双击打开的 `.app`：

```bash
./build.sh
```

产物位于仓库根目录的 `BrowserIsolator.app`。

## 浏览器引擎

BrowserIsolator 使用独立的官方 Google Chrome 副本，不读取系统里已有的 Chrome 配置，也不影响你的日常 Chrome。

首次启动时，应用会自动下载 Chrome 到：

```text
~/Library/Application Support/BrowserIsolator/Chromium/Google Chrome.app/
```

下载文件约 237 MB，耗时取决于网络情况。应用会检查下载响应和 Chrome 可执行文件，下载并安装完成后自动进入环境管理界面。

### macOS 可能阻止自动安装

首次下载浏览器时，macOS 可能弹出“隐私与安全性”提示，显示应用被阻止修改 Mac 上的 App。这通常是因为应用要把 Chrome 复制到自己的应用支持目录；如果你信任本应用，可以允许它继续完成内置 Chrome 安装。

解决方法：

1. 打开 **系统设置 -> 隐私与安全性 -> 应用程序管理**
2. 允许“浏览器多开”管理应用
3. 重新打开 BrowserIsolator，它会继续下载和安装流程

### 手动安装 Chrome

如果自动下载失败，可以手动放置浏览器：

1. 下载 [Google Chrome](https://www.google.com/chrome/) 或直接下载 [Chrome DMG](https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg)
2. 打开 DMG，复制其中的 `Google Chrome.app`
3. 放到：

   ```text
   ~/Library/Application Support/BrowserIsolator/Chromium/
   ```

最终路径应为：

```text
~/Library/Application Support/BrowserIsolator/Chromium/Google Chrome.app
```

之后重新打开 BrowserIsolator 即可。

## 使用

主窗口分为两部分：

- **左侧环境列表**：显示环境名称、运行状态、最近使用时间和数据大小，运行中的环境会排在前面
- **右侧详情栏**：显示选中环境的 profile 路径、调试端口、错误信息、操作按钮和高级详情

常用操作：

- **启动环境**：点击环境行右侧的启动按钮、双击左侧环境行，或在右侧详情栏点击“启动”
- **关闭环境**：点击运行中环境的关闭按钮；环境会显示“关闭中”，直到 Chrome 进程退出
- **全部关闭**：点击工具栏的“全部关闭”，应用会等待所有环境退出
- **添加环境**：点击工具栏“添加环境”，可以立即命名，也可以跳过
- **重命名**：在右侧详情栏点击“重命名”，或右键环境选择“重命名”
- **备注**：在右侧详情栏或环境右键菜单添加简短备注，用来记录账号、用途或其他识别信息
- **查看详情**：选中环境，在右侧详情栏查看 profile 路径、调试端口、错误信息、操作和高级详情
- **删除环境**：右键未运行环境或在详情栏点击“删除”；输入环境名称确认后，数据会移到废纸篓
- **外部链接**：在设置里打开“外部链接”，选择外部链接要打开到哪个环境，并可将 BrowserIsolator 设为默认浏览器。如果浏览器环境还没准备好，应用会提示并允许复制链接
- **设置**：点击工具栏齿轮，查看 Chrome 状态、打开数据目录、复制路径、重新下载 Chrome、配置外部链接、切换语言和外观模式，或在“关于与支持”中检查更新、查看发布页、查看作者联系方式和提交反馈
- **菜单栏操作**：点击菜单栏图标，快速启动/关闭环境、关闭全部环境、打开主窗口或检查更新

如果 Chrome 不可用、端口被占用或 profile 被锁定，错误会显示在对应环境的详情栏中，可直接重试或清除错误。

## 数据位置

所有数据都保存在：

```text
~/Library/Application Support/BrowserIsolator/
├── config.json          # 环境列表、自定义名称和备注
├── Chromium/            # 独立 Chrome 副本
│   └── Google Chrome.app/
└── Profiles/            # 各环境数据
    ├── p1/
    ├── p2/
    └── p3/
```

删除单个环境时，BrowserIsolator 会将对应 profile 目录移到废纸篓。卸载应用后，如果想完全清理数据，手动删除整个 `BrowserIsolator` 目录即可。

## 常见问题

### 为什么不用系统里已有的 Chrome？

为了避免污染你的日常浏览器。BrowserIsolator 使用自己的 Chrome 副本和自己的 profile 目录，不读取系统 Chrome 的书签、Cookie、密码或扩展配置。

### 它能防封号吗？

不能保证。BrowserIsolator 的核心能力是本地数据隔离，并做少量基础环境差异化。不同网站的风控规则差异很大，本项目不承诺绕过检测或规避平台限制。

### 环境差异化具体做了什么？

应用通过 Chrome DevTools Protocol 给页面注入脚本，为不同环境设置不同的 CPU 核心数和内存值：

- `navigator.hardwareConcurrency`
- `navigator.deviceMemory`

这些值会根据环境编号稳定生成，同一个环境重启后保持一致。应用会定期同步当前 Chrome DevTools Protocol 中的 page target，因此新打开的标签页也会被注入。它是轻量差异化，不是完整设备模拟。

### 视频网站能正常播放吗？

可以。应用下载的是官方 Google Chrome，支持主流视频网站和常见编解码能力。

### 浏览器会自动更新吗？

不会。当前下载的 Chrome 会一直使用。如果需要更新，可以在设置中重新下载 Chrome，或手动删除：

```text
~/Library/Application Support/BrowserIsolator/Chromium/
```

下次启动 BrowserIsolator 时会重新下载 Chrome。

### BrowserIsolator 会自动更新吗？

支持应用内检查更新。点击菜单栏“检查更新”，或进入 **设置 -> 关于与支持 -> 检查更新**，应用会通过 Sparkle 检查 GitHub Releases 上的新版本。当前暂不提供 Homebrew 安装源，避免同一个安装实例被多个更新来源同时管理。

### 如何让其他 App 打开的链接进入指定环境？

进入 **设置 -> 外部链接**，选择“打开到”的环境，然后点击“设为默认浏览器”。之后从邮件、聊天软件、备忘录等其他 App 打开的 http/https 链接，会转发到你选择的环境。

如果浏览器环境还没准备好，BrowserIsolator 不会静默吞掉链接，而是会弹出提示并提供复制链接按钮。

### 支持同时运行多少个环境？

没有硬性限制。建议同时运行不超过 5 个环境，具体取决于内存、CPU 和每个环境打开的网页数量。
