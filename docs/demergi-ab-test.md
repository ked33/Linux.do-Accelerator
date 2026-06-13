# Demergi Windows 直连包

这个包通过本机 Demergi HTTP CONNECT 代理访问 linux.do。它不走原 Linux.do Accelerator 的 HTTPS MITM 代理路径，不安装根证书，也不解密浏览器 HTTPS 流量。

## 文件说明

- `demergi.exe`：从随仓库打包的 Demergi 源码构建出的本机代理程序。
- `run-demergi-chrome.ps1`：启动 Demergi，并打开一个隔离 Chrome 配置目录访问 linux.do。
- `run-demergi-normal-chrome.ps1`：启动 Demergi，不修改 Windows 当前用户系统代理；普通 Chrome 是否使用 Demergi 由现有系统代理或 mihomo 规则决定。
- `run-demergi-normal-chrome-silent.exe`：静默启动普通 Chrome 模式，适合双击运行；不会自动打开页面。
- `run-demergi-normal-chrome-silent.cmd`：普通 Chrome 模式的备用双击入口；如果 `.exe` 被安全软件拦截，可以改用它，但可能出现短暂窗口。
- `start-demergi-windows.ps1`：只启动 Demergi。默认不修改系统代理。
- `stop-demergi-windows.ps1`：停止 Demergi；只有显式用 `-UseSystemProxy` 或 `-UseSystemPac` 启动过时，才恢复 Demergi 保存的 Windows 代理设置。
- `stop-demergi-silent.exe`：静默停止 Demergi；只有存在当前 Demergi 管理标记时才恢复代理。
- `stop-demergi-silent.cmd`：停止并恢复代理的备用双击入口；如果 `.exe` 被安全软件拦截，可以改用它，但可能出现短暂窗口。
- `open-demergi-chrome.ps1`：在 Demergi 已启动时，打开隔离 Chrome 配置目录并强制该窗口走 Demergi。
- `status-demergi-windows.ps1`：查看 Demergi 进程、监听端口、系统代理状态和日志路径。
- `linuxdo-demergi.pac`：PAC 文件，把 `linux.do`、`*.linux.do`、`idcflare.com`、`*.idcflare.com` 送到 `127.0.0.1:18080`，其他域名、路由器后台和内网 IP 直连。
- `linuxdo_dpi_overrides.json`：Demergi DNS IP 覆写表，把 mihomo fake-ip 或已知污染 IP 映射到可用的 Cloudflare IP。

## 推荐：隔离 Chrome 模式

这个模式不会改系统代理，只影响脚本新开的独立 Chrome 配置目录。

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\run-demergi-chrome.ps1
```

停止：

```powershell
.\stop-demergi-windows.ps1 -NoSystemProxy
```

## 普通 Chrome 模式

如果要在普通 Chrome 窗口里访问 linux.do，运行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\run-demergi-normal-chrome.ps1
```

如果希望双击后静默启动同一模式，直接双击：

```text
run-demergi-normal-chrome-silent.exe
```

如果运行 `.exe` 被安全软件拦截，改为双击：

```text
run-demergi-normal-chrome-silent.cmd
```

这个脚本只会启动 Demergi，不会修改 Windows 当前用户的 `ProxyServer`、`ProxyEnable` 或 `AutoConfigURL`。如果检测到旧版本留下的 `linuxdo-demergi.pac`，会只清理这个 Demergi PAC 项，不会改动 mihomo 的 `127.0.0.1:20122` 等系统代理端口。

普通 Chrome 如果已经由 mihomo 接管系统代理，需要在 mihomo 中把 linux.do/idcflare 相关域名转发到本地 Demergi HTTP 代理：

```text
127.0.0.1:18080
```

脚本不会自动打开 `linux.do` 页面。完成 mihomo 分流后，请在普通 Chrome 中手动打开：

```text
https://linux.do/
```

如果普通 Chrome 已经打开但仍未生效，先确认 mihomo 已重新加载配置。必要时关闭并重新打开 Chrome，或执行：

```powershell
taskkill /IM chrome.exe /F
```

使用完普通 Chrome 模式后，停止 Demergi：

```powershell
.\stop-demergi-windows.ps1
```

如果希望双击后静默停止并恢复代理，直接双击：

```text
stop-demergi-silent.exe
```

如果运行 `.exe` 被安全软件拦截，改为双击：

```text
stop-demergi-silent.cmd
```

## 仅启动代理

只启动 Demergi，不改系统代理：

```powershell
.\start-demergi-windows.ps1
```

显式启用 Windows 手动系统代理：

```powershell
.\start-demergi-windows.ps1 -UseSystemProxy -Restart
```

这个模式会让更多跟随 Windows 系统代理的流量进入 Demergi。脚本会绕过 `10.*`、`172.16.*` 到 `172.31.*`、`192.168.*`、`169.254.*`、`127.*` 等常见内网/本机地址，但非 linux.do 的公网流量仍可能受影响。一般使用优先选 PAC 模式。

显式启用 PAC 模式：

```powershell
.\start-demergi-windows.ps1 -UseSystemPac -Restart
```

在 mihomo 已经管理 Windows 系统代理的环境中，不推荐使用 `-UseSystemProxy` 或 `-UseSystemPac`，因为它们会和 mihomo 写同一组 Windows 当前用户代理设置。推荐保持 Windows 系统代理归 mihomo 管理，只让 mihomo 把 linux.do/idcflare 转发到本地 Demergi。

## mihomo 配置文本

本包不会修改 mihomo 或 GUI.for.Clash 的任何配置文件。下面只是配置思路文本，需要你放到自己的持久化覆写脚本或规则生成逻辑里。

概念上的 mihomo 片段：

```yaml
proxies:
  - name: linuxdo-demergi
    type: http
    server: 127.0.0.1
    port: 18080

rules:
  - PROCESS-NAME,demergi.exe,DIRECT
  - PROCESS-NAME,linuxdo-accelerator.exe,DIRECT
  - DOMAIN-SUFFIX,linux.do,linuxdo-demergi
  - DOMAIN-SUFFIX,idcflare.com,linuxdo-demergi
```

在 GUI.for.Clash 这类生成配置的工具里，不建议只改生成后的 `config.yaml`。应放到持久化的生成脚本/覆写逻辑中，并保证：

- `linuxdo-demergi` 代理节点先存在，再引用到规则。
- `DOMAIN-SUFFIX,linux.do,linuxdo-demergi` 放在更宽泛的 `custom-direct` / `DIRECT` / `MATCH` 规则之前。
- `PROCESS-NAME,demergi.exe,DIRECT` 可以避免 Demergi 自己连接 Cloudflare 上游时被 mihomo 转回本地代理链。新版 Windows 脚本默认使用 `plain` DNS 并加载 `linuxdo_dpi_overrides.json`，不再依赖 Demergi 自己直连外部 DoH。
- fake-ip / DNS 仍可按你现有 linux.do 策略处理；关键是普通 Chrome 的 HTTP CONNECT 流量要由 mihomo 转交给 `127.0.0.1:18080`。

## 状态和日志

查看状态：

```powershell
.\status-demergi-windows.ps1
.\status-demergi-windows.ps1 -SampleSeconds 5
```

日志和状态文件目录：

```text
%LOCALAPPDATA%\linuxdo\demergi-ab-test
```

## 参数说明

Demergi 默认监听：

```text
127.0.0.1:18080
```

默认 DNS 模式：

```text
plain
```

Windows 脚本会默认加载同目录的 `linuxdo_dpi_overrides.json`。在 mihomo fake-ip 环境下，Demergi 可能先看到 `198.18.0.0/16` fake-ip；覆写表会把这类地址和已知污染 IP 替换成可用的 Cloudflare IP 后再连接上游。

如果你需要显式测试 DoH，可以切到 `doh` 模式。默认 DoH 参数使用 IP 形式，避免 DoH 服务器域名本身被错误解析：

```powershell
.\run-demergi-chrome.ps1 -DnsMode doh -DohUrl "https://223.5.5.5/dns-query"
.\run-demergi-normal-chrome.ps1 -DnsMode doh -DohUrl "https://223.5.5.5/dns-query"
```

Demergi 默认会对 HTTPS CONNECT 流量做 ClientHello 分片，默认分片大小是 `40`：

```powershell
.\run-demergi-chrome.ps1 -ClientHelloSize 40
```

## 注意事项

- 不要同时运行原 Linux.do Accelerator 的 GUI/CLI 代理核心和 Demergi 测试包，否则 CPU 和连通性判断会互相干扰。
- `run-demergi-chrome.ps1` 使用隔离 Chrome 配置目录，是最稳的测试和使用方式。
- `run-demergi-normal-chrome.ps1` 默认不改 Windows 代理设置，适合 mihomo 已管理系统代理的环境。
- 显式 `-UseSystemProxy` / `-UseSystemPac` 只是无 mihomo 或排障时的备用模式；在 mihomo 环境中优先使用 mihomo 规则转发到 Demergi。
