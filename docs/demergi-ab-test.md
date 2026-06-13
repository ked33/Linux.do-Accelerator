# Demergi Windows 直连包

这个包通过本机 Demergi HTTP CONNECT 代理访问 linux.do。它不走原 Linux.do Accelerator 的 HTTPS MITM 代理路径，不安装根证书，也不解密浏览器 HTTPS 流量。

## 文件说明

- `demergi.exe`：从随仓库打包的 Demergi 源码构建出的本机代理程序。
- `run-demergi-chrome.ps1`：启动 Demergi，并打开一个隔离 Chrome 配置目录访问 linux.do。
- `run-demergi-normal-chrome.ps1`：启动 Demergi，并启用 Windows 当前用户 PAC；普通 Chrome 需要手动打开 linux.do。
- `run-demergi-normal-chrome-silent.exe`：静默启动普通 Chrome 模式，适合双击运行；不会自动打开页面。
- `run-demergi-normal-chrome-silent.cmd`：普通 Chrome 模式的备用双击入口；如果 `.exe` 被安全软件拦截，可以改用它，但可能出现短暂窗口。
- `start-demergi-windows.ps1`：只启动 Demergi。默认不修改系统代理。
- `stop-demergi-windows.ps1`：停止 Demergi，并在需要时恢复之前保存的 Windows 代理设置。
- `stop-demergi-silent.exe`：静默停止 Demergi，并恢复之前保存的 Windows 代理设置。
- `stop-demergi-silent.cmd`：停止并恢复代理的备用双击入口；如果 `.exe` 被安全软件拦截，可以改用它，但可能出现短暂窗口。
- `open-demergi-chrome.ps1`：在 Demergi 已启动时，打开隔离 Chrome 配置目录并强制该窗口走 Demergi。
- `status-demergi-windows.ps1`：查看 Demergi 进程、监听端口、系统代理状态和日志路径。
- `linuxdo-demergi.pac`：PAC 文件，把 `linux.do`、`*.linux.do`、`idcflare.com`、`*.idcflare.com` 送到 `127.0.0.1:18080`，其他域名、路由器后台和内网 IP 直连。

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

这个脚本只会启动 Demergi 并启用 Windows 当前用户 PAC。默认 PAC 只让 `linux.do`、`*.linux.do`、`idcflare.com`、`*.idcflare.com` 走 Demergi：

```text
PROXY 127.0.0.1:18080
```

其他网站、路由器后台和内网 IP 会保持直连，因此不会把 `http://192.168.10.1/` 这类页面送进 Demergi。

脚本不会自动打开 `linux.do` 页面。运行后请在普通 Chrome 中手动打开：

```text
https://linux.do/
```

如果普通 Chrome 已经打开但仍未生效，关闭并重新打开 Chrome，或执行：

```powershell
taskkill /IM chrome.exe /F
```

使用完普通 Chrome 模式后，停止并恢复之前的 Windows 代理设置：

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

默认 DoH：

```text
https://1.0.0.1/dns-query
```

如果你的网络访问 `1.0.0.1:443` 超时，可以改用其他 DoH：

```powershell
.\run-demergi-chrome.ps1 -DohUrl "https://dns.alidns.com/dns-query"
.\run-demergi-normal-chrome.ps1 -DohUrl "https://dns.alidns.com/dns-query"
```

Demergi 默认会对 HTTPS CONNECT 流量做 ClientHello 分片，默认分片大小是 `40`：

```powershell
.\run-demergi-chrome.ps1 -ClientHelloSize 40
```

## 注意事项

- 不要同时运行原 Linux.do Accelerator 的 GUI/CLI 代理核心和 Demergi 测试包，否则 CPU 和连通性判断会互相干扰。
- `run-demergi-chrome.ps1` 使用隔离 Chrome 配置目录，是最稳的测试和使用方式。
- `run-demergi-normal-chrome.ps1` 会改 Windows 当前用户的 PAC 设置，普通 Chrome 和部分跟随系统代理的应用会按 PAC 规则只把 linux.do/idcflare 相关域名送进 Demergi。
- 使用普通 Chrome 模式后，建议用 `.\stop-demergi-windows.ps1` 恢复之前的代理设置。
