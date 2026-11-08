# Windows Server 远程控制安装脚本

安装官方 RustDesk，并将其 Windows 服务设为 **自动（延迟启动）**。配置一次固定密码后，服务器重启、尚未登录 Windows 时也可尝试连接，无需每次手动启动程序。

**[下载脚本 ZIP](https://github.com/Mageric0412/windows-remote-setup/releases/latest/download/windows-remote-setup.zip)** · [版本与校验值](https://github.com/Mageric0412/windows-remote-setup/releases/latest)

## 使用条件

- 面向 Windows Server **2016 / 2019 / 2022 / 2025 的桌面体验版**；也允许 Windows 10/11。
- x64 或 ARM64、Windows PowerShell 5.1、管理员权限。
- 本包不支持 Server Core（没有完整桌面的版本）或 Server 2012/R2；检测到不适用的系统会停止。
- ZIP 是在线安装脚本包。安装时需要访问 GitHub 官方发布页，远控时需要双方可访问 RustDesk 连接基础设施。
- “能上网”不能保证远控可用：出口限制、代理、云服务器网络策略、无可捕获的桌面等都可能影响连接。需要在目标机器实际验证。

## 安装与连接

1. 在要被控制的 Windows 上下载 ZIP，**全部解压**，双击 `install.cmd`。
2. 允许安装程序的 UAC 提示，完成 RustDesk 安装向导；随后允许服务配置的管理员提示。
3. 脚本会设置 `RustDesk` 服务为自动（延迟启动），立即启动一次，并检查启动状态和配置。
4. 在 RustDesk 的 **设置 → 安全 → 解锁安全设置** 中设置独立的固定密码，建议至少 16 位；启用允许密码验证的连接审批方式。只允许手动批准时，无法无人值守连接。
5. 记下 RustDesk 主界面的设备 ID。在自己的电脑或手机安装 [RustDesk](https://rustdesk.com/)，输入设备 ID 和固定密码连接。
6. 先测试鼠标、键盘和锁屏登录，再安排一次服务器重启。重启后等待服务延迟启动，**在目标 Windows 无人登录时再次连接**。

固定密码不写入脚本或仓库。Windows 锁屏仍使用原来的 Windows 账号密码登录。不要公开发送远控密码。

## 重启后如何启动

脚本通过 Windows 服务管理器设置：

```powershell
sc.exe config RustDesk start= delayed-auto
```

这是系统服务，不依赖用户登录或“启动”文件夹。Windows 决定延迟启动时机，**不是精确的 30 秒或 120 秒定时器**。脚本本次会立即启动服务以便测试；后续重启才按延迟启动设置执行。

如果其他程序主动请求启动该服务，Windows 可以提前启动。若重新安装或升级 RustDesk 后启动类型被改动，可再次运行本包的 `configure-service.ps1`（以管理员身份）恢复延迟启动。

查看配置：打开 `services.msc`，找到 RustDesk，确认“自动（延迟启动）”且状态“正在运行”。也可在 PowerShell 查看：

```powershell
Get-Service RustDesk
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\RustDesk' |
    Select-Object Start, DelayedAutoStart
```

预期 `Start = 2`、`DelayedAutoStart = 1`。服务运行不等于远控连接已经成功。

## 只检查系统，不安装

在解压目录打开 PowerShell：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -CheckOnly
```

此操作只检查本机系统条件，不测试网络、不安装软件、不修改服务。

## 脚本做了什么

- 从 `github.com/rustdesk/rustdesk` 官方 1.5.1 release 下载对应架构的 MSI。
- 按已固定的官方 SHA-256 校验下载文件，校验失败则停止。
- 使用可见 MSI 安装向导，不安装可选的虚拟打印机，不自动重启。
- 将 RustDesk 服务配置为自动延迟启动，并检查它已运行。
- 打开 RustDesk，提示用户设置固定密码与完成实际连接测试。
- 安装日志保存在终端显示的 `%TEMP%\rustdesk-setup-随机字符串\install.log`。
- `ExecutionPolicy Bypass` 只作用于本次 PowerShell 进程，不更改持久执行策略。
- 默认沿用 RustDesk 的公共连接基础设施；本脚本不提供自建中继。

未设置防火墙放行规则、未开放公网 RDP 3389、未修改睡眠策略。RustDesk 安装程序本身的行为以官方版本为准。服务器须保持开机、联网且不休眠。

如果已有更高版本 RustDesk，请使用已有版本，并以管理员运行 `configure-service.ps1` 设置服务；不要为了运行本包而降级。

## 排错与移除

- 下载失败：检查 GitHub 可访问性；重试或从[官方发布页](https://github.com/rustdesk/rustdesk/releases/tag/1.5.1)下载对应 MSI。
- 可把官方 MSI 放入解压目录的 `packages` 子目录，保持原文件名；脚本会优先使用它，仍执行同样的哈希校验。
- 服务设置失败：安装可能已经完成；查看错误、管理员权限与 Windows 事件日志，修复后单独运行服务配置脚本。不要把“安装完成”当作“已能连接”。
- 连接失败：检查被控端显示就绪、服务运行、ID/密码正确、网络未阻断、Windows 未睡眠。
- 黑屏或无显示器的云主机：需要在目标虚拟化/显示环境实测；本包不自动安装显示驱动。
- Server Core：需要另行使用适合命令行管理的方案，如通过受控网络使用 PowerShell Remoting 或 SSH。
- 临时停用：在 `services.msc` 停止 RustDesk，并把启动类型改为“手动”或“禁用”；仅停止服务，下次重启仍会自动启动。
- 卸载：使用 Windows“应用”或“程序和功能”卸载 RustDesk。仅关闭主窗口通常不会停止后台服务。

## 验证范围

仓库的 Windows CI 在 Server 2022/2025 运行 PowerShell 5.1 语法检查、系统条件检查、哈希篡改拒绝测试，并创建无网络功能的临时测试服务，实际验证延迟启动设置、启动状态和重复配置。结果见 [Actions](https://github.com/Mageric0412/windows-remote-setup/actions)。

这些测试**不等于** RustDesk 实机安装、服务器重启后远控或跨网络连接已经通过。目标 Windows 的完整流程需按上述步骤验证。

## 官方依据

- [RustDesk Windows MSI](https://rustdesk.com/docs/en/client/windows/msi/)
- [RustDesk 无人值守访问](https://rustdesk.com/blog/rustdesk-unattended-access-setup/)
- [Microsoft sc.exe config](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/sc-config)
- [Windows Server Core 与桌面体验版](https://learn.microsoft.com/en-us/windows-server/get-started/install-options-server-core-desktop-experience)

本仓库只包含安装辅助脚本，不包含 RustDesk 源码或二进制。RustDesk 是独立第三方项目。
