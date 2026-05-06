# 浏览器多开 (BrowserIsolator)

在一台 Mac 上同时运行多个独立浏览器，每个环境独立保存密码、Cookie 和登录状态，互不干扰。

---

经常需要在同一台电脑上同时登录多个账号，来回切换非常麻烦。试过一些多开工具，要么太复杂、带一堆用不上的指纹伪装功能，要么不稳定容易出问题。

其实需求很简单：一台电脑上同时开几个浏览器，浏览器各登各的号，互不影响。不需要防封号、不需要设备码模拟，就是纯粹的登录状态隔离。

浏览器多开就是这么来的。一个轻量工具，帮你同时运行多个独立浏览器，每个环境的数据完全隔离。

---

## 功能

- **多环境隔离**：每个浏览器环境独立保存 Cookie、LocalStorage 和登录状态，互不干扰
- **状态一目了然**：运行中的环境自动排在前面，绿色圆点标识运行状态
- **快速操作**：一键启动/关闭环境，支持全部关闭
- **自定义命名**：右键菜单重命名，方便区分不同账号
- **菜单栏快捷操作**：通过菜单栏图标快速启动/关闭环境，无需打开管理面板
- **完全本地**：所有数据保存在本地，无数据收集

## 系统要求

- macOS 26 Tahoe 或更高版本
- Apple Silicon 芯片（M1 及以上），不支持 Intel Mac

## 安装

**方式一：DMG 安装包**

1. 进入本仓库的 [Releases](../../releases) 页面，下载最新的 `BrowserIsolator.dmg`
2. 打开 DMG，将浏览器多开拖入 Applications 文件夹
3. 首次启动时，macOS 可能提示"应用已损坏"或"无法验证开发者"——这是 Gatekeeper 对未付费签名应用的正常拦截，应用本身完好。在终端执行以下命令移除隔离标记：
   ```bash
   xattr -cr /Applications/BrowserIsolator.app
   ```
   之后双击即可正常启动；或右键点击 → 打开 → 弹窗中再点"打开"。

**方式二：自行编译**

1. 克隆本仓库
2. 在项目目录下执行：
   ```bash
   cd BrowserIsolator
   swift build -c release
   ```
3. 编译产物在 `.build/release/BrowserIsolator`

## 浏览器引擎

浏览器多开需要一个浏览器引擎来运行环境。首次启动时，应用会**自动下载** Google Chrome 到以下位置：

```
~/Library/Application Support/BrowserIsolator/Chromium/Google Chrome.app/
```

下载过程大约需要几分钟，取决于网络速度（约 237MB）。下载完成后会自动进入管理界面。

### macOS 可能阻止安装

首次下载浏览器时，macOS 可能弹出"隐私与安全性"提示，显示"已阻止浏览器多开修改 Mac 上的 App"。这是因为浏览器多开需要将 Chrome 安装到应用目录，macOS 把此行为识别为应用管理操作。

**解决方法**：打开 **系统设置 → 隐私与安全性 → 应用程序管理**，将浏览器多开设为允许即可。之后重新打开浏览器多开会自动继续下载。

### 如果自动下载失败

你可以手动下载浏览器并放到指定位置：

1. 访问 [Chrome 官网](https://www.google.com/chrome/) 下载，或直接下载 [dmg 安装包](https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg)
2. 双击 dmg 挂载，复制里面的 `Google Chrome.app`
3. 将 `Google Chrome.app` 放到以下目录：
   ```
   ~/Library/Application Support/BrowserIsolator/Chromium/
   ```
   确保最终路径为 `~/Library/Application Support/BrowserIsolator/Chromium/Google Chrome.app`。如果 `Chromium/` 目录不存在，先手动创建。

之后重新打开浏览器多开即可正常使用。

## 使用

- **启动环境**：点击环境右侧的"启动"按钮
- **关闭环境**：点击运行中环境右侧的"关闭"按钮，或使用工具栏"全部关闭"
- **重命名**：右键菜单 → 重命名
- **添加环境**：点击工具栏的"添加环境"按钮
- **删除环境**：右键菜单 → 删除（仅未运行时显示）
- **菜单栏**：点击菜单栏图标，可快速启动/关闭环境

## 常见问题

**为什么不用现有的 Chrome？**

浏览器多开使用独立的 Chrome 副本，放在 `~/Library/Application Support/BrowserIsolator/Chromium/` 下，数据目录也在同一位置。它和你系统里安装的 Google Chrome 完全隔离——不读取你的 Chrome 配置，不影响你的日常使用，互不干扰。

**视频能正常播放吗？**

可以。下载的是官方 Google Chrome，支持所有主流视频网站和编解码器。

**浏览器版本会自动更新吗？**

不会。当前下载的版本会一直使用。如果你需要更新，可以手动删除 `~/Library/Application Support/BrowserIsolator/Chromium/`，下次启动浏览器多开时会自动下载最新版本。

**数据保存在哪里？**

所有数据保存在 `~/Library/Application Support/BrowserIsolator/` 下：

```
~/Library/Application Support/BrowserIsolator/
├── config.json          # 配置文件
├── Chromium/            # 浏览器引擎
│   └── Google Chrome.app/
└── Profiles/            # 各环境的数据
    ├── p1/
    ├── p2/
    └── p3/
```

卸载应用后，手动删除整个 `BrowserIsolator` 目录即可完全清理。

**支持同时运行多少个环境？**

没有限制，但建议同时不超过 5 个，具体取决于你的电脑配置。