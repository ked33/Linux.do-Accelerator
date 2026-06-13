# Demergi 与 mihomo 兼容启动设计

## 问题

Demergi 普通 Chrome 模式曾经把 Windows 当前用户代理改成
`127.0.0.1:18080`，或改成本地 `linuxdo-demergi.pac`。这在没有其他代理接管系统
代理时可用，但在 Windows + GUI.for.Clash/mihomo 环境里会和 mihomo 写同一组
WinINet 代理设置。

当前目标环境中，普通 Chrome 应继续使用 mihomo 的系统代理端口。Demergi 只作为
本机 linux.do 专用 HTTP 代理，由 mihomo 规则把 linux.do/idcflare 相关流量转发到
`127.0.0.1:18080`。这样不会影响路由器后台、国内网页或 mihomo 已有系统代理状态。

## 决策

普通 Chrome/silent 入口默认只启动 Demergi，并传 `-NoSystemProxy`。它不再修改
Windows `ProxyServer`、`ProxyEnable` 或 `AutoConfigURL`。

如果旧版本留下 `linuxdo-demergi.pac`，默认启动路径只清理这个 Demergi 自己写入的
PAC 项，不改 mihomo 的 `ProxyServer=127.0.0.1:20122` 等代理端口。

`-UseSystemProxy` 和 `-UseSystemPac` 仍保留为显式备用/排障模式，并用 marker 文件
标记“当前代理状态由 Demergi 管理”。停止脚本只有看到 marker 时才恢复 Demergi
保存的代理备份，避免误把 mihomo 代理状态回滚到旧快照。

GUI.for.Clash 覆写脚本负责持久化 mihomo 侧分流：新增本地 HTTP 代理节点
`linuxdo-demergi`，把 `linux.do` 和 `idcflare.com` 规则前置到该节点，并让
`demergi.exe` 出站 `DIRECT`。

## 范围

- `run-demergi-normal-chrome.ps1` 默认只启动 Demergi，不改 Windows 代理。
- `start-demergi-windows.ps1` 默认清理旧 Demergi PAC 残留，但不改 mihomo 的手动
  系统代理端口。
- `start-demergi-windows.ps1 -UseSystemProxy` 继续可用，但增加内网 bypass 列表和
  风险提示。
- `start-demergi-windows.ps1 -UseSystemPac` 继续可用，但只作为显式备用模式。
- `stop-demergi-windows.ps1` 只在存在 Demergi 管理 marker 时恢复代理备份。
- `open-demergi-chrome.ps1` 增加 `--proxy-bypass-list`。
- GUI.for.Clash `profiles.yaml` 中用户授权的 `onGenerate` 脚本加入
  `linuxdo-demergi` 本地 HTTP 节点、前置规则和 fake-ip-filter 例外。
- 文档说明普通 Chrome 的推荐路径是 mihomo 规则转发，而不是 Demergi 抢系统代理。

## 验证

使用脚本 DryRun、PowerShell 解析检查、PAC 语法检查、GUI.for.Clash 覆写脚本
Node 模拟和 diff 检查。这里属于脚本/静态验证；是否符合真实浏览器行为，需要在
GUI.for.Clash 重新生成配置并让 mihomo 重新加载后确认。
