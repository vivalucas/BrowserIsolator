# 浏览器多开 (BrowserIsolator)

在一台 Mac 上同时运行多个彼此独立的 Chrome 环境。每个环境都有自己的 Cookie、LocalStorage、密码和登录状态，适合同时管理多个账号，而不用反复登录、退出、切换浏览器配置。

[English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Русский](README.ru.md)

BrowserIsolator 的目标很简单：做好本地浏览器环境隔离。它不是复杂的反检测平台，也不承诺绕过网站风控；它只是把多个浏览器环境清楚地分开，让日常多账号使用更稳定、更省心。

## 功能

- **独立环境**：每个环境使用单独的 Chrome 数据目录，登录状态、Cookie、缓存和扩展配置互不影响
- **一键启动/关闭**：在主面板或菜单栏快速启动、关闭单个环境，也可以一次关闭全部环境
- **环境信息展示**：面板显示运行状态、环境目录、调试端口、磁盘占用和最后使用时间
- **自定义命名**：通过右键菜单给环境命名，方便对应不同账号或用途
- **指纹差异化**：为不同环境注入不同的 `navigator.hardwareConcurrency` 和 `navigator.deviceMemory` 值
- **自动浏览器安装**：首次运行时自动下载官方 Google Chrome，并放在应用自己的数据目录中
- **本地优先**：配置、浏览器和环境数据都保存在本机，不上传、不收集用户数据

## 系统要求

- macOS 26 Tahoe 或更高版本
- Apple Silicon Mac（M1 及以上）

当前发布包按 `arm64-apple-macosx26.0` 构建，不支持 Intel Mac。

## 安装

### 方式一：下载 DMG

1. 打开本仓库的 [Releases](../../releases) 页面，下载最新的 `BrowserIsolator.dmg`
2. 打开 DMG，将 `BrowserIsolator.app` 拖入 Applications 文件夹
3. 首次启动时，如果 macOS 提示“无法验证开发者”或“应用已损坏”，这是未公证应用常见的 Gatekeeper 拦截。可以执行：

   ```bash
   xattr -cr /Applications/BrowserIsolator.app
   ```

   然后重新打开应用。也可以在 Finder 中右键应用，选择“打开”，再在弹窗中确认。

### 方式二：自行编译

如果只需要生成可执行文件：

```bash
cd BrowserIsolator
swift build -c release -Xswiftc -target -Xswiftc arm64-apple-macosx26.0
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

下载文件约 237 MB，耗时取决于网络情况。下载并安装完成后，应用会自动进入环境管理面板。

### macOS 可能阻止自动安装

首次下载浏览器时，macOS 可能弹出“隐私与安全性”提示，显示应用被阻止修改 Mac 上的 App。这通常是因为应用要把 Chrome 复制到自己的应用支持目录。

解决方法：

1. 打开 **系统设置 → 隐私与安全性 → 应用程序管理**
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

- **启动环境**：点击环境右侧的“启动”
- **关闭环境**：点击运行中环境右侧的“关闭”
- **全部关闭**：点击工具栏的“全部关闭”
- **添加环境**：点击工具栏的“添加环境”
- **重命名**：右键环境，选择“重命名”
- **删除环境**：右键未运行的环境，选择“删除”
- **菜单栏操作**：点击菜单栏图标，可快速启动、关闭环境，或打开管理面板

运行中的环境会排在列表前面。每个运行环境会显示当前使用的远程调试端口，主要用于诊断指纹注入和浏览器连接状态。

## 数据位置

所有数据都保存在：

```text
~/Library/Application Support/BrowserIsolator/
├── config.json          # 环境列表和自定义名称
├── Chromium/            # 独立 Chrome 副本
│   └── Google Chrome.app/
└── Profiles/            # 各环境数据
    ├── p1/
    ├── p2/
    └── p3/
```

卸载应用后，如果想完全清理数据，手动删除整个 `BrowserIsolator` 目录即可。

## 常见问题

### 为什么不用系统里已有的 Chrome？

为了避免污染你的日常浏览器。BrowserIsolator 使用自己的 Chrome 副本和自己的 profile 目录，不读取系统 Chrome 的书签、Cookie、密码或扩展配置。

### 它能防封号吗？

不能保证。BrowserIsolator 的核心能力是本地数据隔离，并做了少量基础指纹差异化。不同网站的风控规则差异很大，本项目不承诺绕过检测或规避平台限制。

### 指纹差异化具体做了什么？

应用通过 Chrome DevTools Protocol 给页面注入脚本，为不同环境设置不同的 CPU 核心数和内存值：

- `navigator.hardwareConcurrency`
- `navigator.deviceMemory`

这些值会根据环境编号稳定生成，同一个环境重启后保持一致。它是轻量差异化，不是完整设备模拟。

### 视频网站能正常播放吗？

可以。应用下载的是官方 Google Chrome，支持主流视频网站和常见编解码能力。

### 浏览器会自动更新吗？

不会。当前下载的 Chrome 会一直使用。如果需要更新，可以删除：

```text
~/Library/Application Support/BrowserIsolator/Chromium/
```

下次启动 BrowserIsolator 时会重新下载最新的 Chrome。

### 支持同时运行多少个环境？

没有硬性限制。建议同时运行不超过 5 个环境，具体取决于内存、CPU 和每个环境打开的网页数量。
