# Demergi PAC 与内网绕过设计

## 问题

Demergi 普通 Chrome 模式原先会把 Windows 当前用户的手动代理改成
`127.0.0.1:18080`。旧 bypass 列表只覆盖本机名称和回环地址，因此
`http://192.168.10.1/ch/index.html` 这类路由器后台页面会被浏览器送进
Demergi。

Demergi 是面向 linux.do 的 HTTP CONNECT 代理，不是通用全流量代理。让它接管路
由器后台、内网页面或普通国内站点，会造成可达性和排障上的副作用。

## 决策

普通 Chrome 入口默认改为 Windows PAC 模式。随包 PAC 只把 linux.do/idcflare 相
关域名送到 Demergi，其他流量返回 `DIRECT`。这和包的目标一致：只帮助 linux.do
可用，不接管全部浏览器流量。

手动系统代理仍保留为显式调试模式。使用该模式时，脚本需要绕过常见私网和
link-local 地址段，避免路由器后台和局域网服务进入 Demergi。

隔离 Chrome 入口使用显式 `--proxy-server`，因此也需要传入浏览器级
`--proxy-bypass-list`。

## 范围

- `run-demergi-normal-chrome.ps1` 默认启动 PAC 模式。
- `start-demergi-windows.ps1 -UseSystemProxy` 继续可用，但增加内网 bypass 列表和
  风险提示。
- 进入 PAC 模式时清理当前注册表里的手动代理字段，同时保留启动前备份用于停止时
  恢复。
- 成功恢复代理设置后删除备份文件，避免后续运行复用过期设置。
- `open-demergi-chrome.ps1` 增加 `--proxy-bypass-list`。
- PAC 文件显式标注 localhost、私网 IP 字面量和 link-local 地址直连。
- 文档说明普通 Chrome 默认 PAC，手动系统代理只是影响更广的备用调试模式。

## 验证

使用脚本 DryRun、PowerShell 解析检查、PAC 语法检查和 diff 检查。这里属于脚本/
静态验证；是否符合真实浏览器行为，需要打包后在 Windows + Chrome 环境中实际运
行确认。
