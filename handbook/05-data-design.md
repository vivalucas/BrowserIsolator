# 数据约定

> 适用状态：启用。本项目无数据库；这里维护 JSON、UserDefaults 与目录语义。

## 当前依据

- 模型与迁移兼容入口：`BrowserIsolator/Sources/BrowserIsolator/Models.swift`。
- 运行数据根目录：`~/Library/Application Support/BrowserIsolator/`，由 `AppPaths` 统一计算。
- 配置文件：`config.json`；保存前备份为 `config.json.bak`。
- 浏览器数据：`Profiles/pN/`；内置 Chrome：`Chromium/Google Chrome.app`。
- 无独立迁移工具；`Codable` 的 `decodeIfPresent` 默认值承担向后兼容，复杂变化需新增显式迁移。

## 实体地图

| 业务概念 | 存储 | 身份与语义 | 权威来源 |
| --- | --- | --- | --- |
| 环境 | `Profile` / `config.profiles[]` | `folder=pN` 唯一；名称、备注、两种模式和最近使用时间为属性 | `Models.swift` |
| 应用配置 | `AppConfig` / `config.json` | 当前仅含 profile 数组 | `Models.swift` |
| 环境浏览器数据 | `Profiles/pN/` | 与 `Profile.folder` 一一对应；可能在配置损坏后仍独立存在 | Chrome 文件系统 |
| 本机偏好 | UserDefaults | 语言、外观、窗口、分栏、默认外链环境等设备偏好 | `App.swift` / `Localization.swift` |
| 运行态 | BrowserManager 内存字典与集合 | 进程、注入器、端口、排队链接、错误；不持久化 | `BrowserManager.swift` |

`Profile` 当前字段：`folder`、`displayName`、`note`、`fingerprintEnabled`、`collectorDebugEnabled`、`lastUsed`。新增可选行为字段应为旧配置提供安全默认值；不能因字段缺失让整个配置解码失败。

## 一致性与恢复

- 新建环境统一经 `Profile.newEnvironment(folder:)` 创建，默认采集开启、差异关闭。普通初始化和旧配置解码仍默认采集关闭，供已有数据及磁盘恢复使用；新建默认值不用于迁移旧配置。
- 首次生成或默认回退的配置在创建环境目录前保存，避免直接退出后被当作磁盘恢复而丢失采集默认值。加载正常配置不重写文件；生成或恢复后的保存失败必须显示错误，恢复后的保存失败信息合并到恢复提示中，避免同时弹出两个提示。
- 读取时过滤非正数编号和重复 `folder`，避免运行状态字典冲突。
- 磁盘重建只识别名称为 `pN` 的真实目录，不接受普通文件。
- `lastUsed` 以持久化值为主，旧配置或磁盘重建才用目录修改时间兜底。
- 保存使用临时文件和原子替换；有主文件时先复制到 `.bak`。批量模式变更合并为一次保存，避免备份落在中间状态。
- 主配置损坏时保留 `config.corrupt-<时间戳>.json`，依次尝试备份、磁盘重建和默认配置，并向用户说明采用了哪一级恢复。
- 删除 profile 使用系统废纸篓。先持久化移除结果再移动目录，保存失败不移动，移动失败回滚配置；卸载应用后的整体数据清理由用户手动执行。
- 真实 profile、配置、备份和 Chrome 副本不进入 Git，不作为测试样本复制。

## 变更要求

数据字段变化需要验证旧配置解码、保存后重载、损坏主文件恢复、重复/非法 folder 过滤和磁盘重建。若未来引入数据库，先说明 JSON 无法满足的需求，并设计一次性迁移、备份和回滚，不能长期维护两套权威数据。

## 语言兼容

界面仅支持中文（zh）、英文（en）、日文（ja）。旧偏好中的其他语言按受支持的系统语言回退，无匹配时使用中文；不迁移或删除环境数据，也不因语言回退重写配置。
