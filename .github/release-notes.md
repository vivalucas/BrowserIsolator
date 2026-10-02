# BrowserIsolator 2.1.0

## 2.1.0 更新

- 新增随应用发行的原生 `isolator` CLI 和本地 MCP，其他项目及 AI Agent 可接入现有浏览器环境。
- 支持分层读取网页、展开节点、完整 DOM/AX 导出、iframe 与 Shadow DOM、页面交互、动态观察和等待。
- 默认提供精简结构与变化结果，详细内容按需获取；截图返回文件，只有支持识图的模型才应读取图片，纯文本模型可使用结构与文本。
- 设置新增“自动化”入口，支持查看连接状态、复制 CLI 路径和 MCP 配置；中文、英文、日文同步。
- 保持旧环境配置、采集／差异模式、端口和外部链接调用契约兼容。

接入方式和能力边界见 [自动化指南](https://github.com/vivalucas/BrowserIsolator/blob/v2.1.0/handbook/14-automation.md)。

适用于 Apple Silicon、macOS 13 或更新版本。安装包沿用 ad-hoc 签名，未做 Apple 公证。
