# 攻击场景模拟

> 复现 4 种典型攻击场景，采集攻击日志，为检测规则编写提供数据

## 攻击场景总览

| # | 场景 | ATT&CK 技术 | 攻击机 | 目标 | 预计耗时 |
|---|------|-------------|--------|------|----------|
| 1 | 暴力破解 | T1110.001 (Password Guessing) | Kali | WIN10-01 (RDP/SMB) | 15分钟 |
| 2 | Pass-the-Hash | T1550.002 (Pass the Hash) | Kali/WIN10-01 | DC01 / WIN10-02 | 20分钟 |
| 3 | 横向移动 | T1021.002 (SMB/Admin Shares) + T1543.003 (Windows Service) | WIN10-01 | WIN10-02 | 20分钟 |
| 4 | 权限提升 | T1068 (Exploitation for Privilege Escalation) + T1548.002 (Bypass UAC) | WIN10-01 (普通用户) | WIN10-01 (本地管理员) | 25分钟 |

## 攻击链全景

```
[初始访问]          [凭证窃取]          [横向移动]          [权限提升]
  暴力破解    →    Pass-the-Hash  →    SMB/Psexec    →    服务权限配置错误
  (T1110)         (T1550.002)         (T1021.002)         (T1068)
     │                  │                    │                    │
     ▼                  ▼                    ▼                    ▼
  WIN10-01          获取域管Hash         WIN10-02            WIN10-01 SYSTEM
  (jdoe账号)        (mimikatz)          (创建服务)           (JuicyPotato)
```

## 执行前准备

1. 确保所有虚拟机已启动并加入域
2. Wazuh Agent 状态为 Active
3. Sysmon 已安装并运行
4. 在 Wazuh Dashboard 中打开实时告警视图
5. 记录攻击开始时间，便于后续日志筛选

## 各场景目录

| 目录 | 内容 |
|------|------|
| `brute-force/` | 暴力破解脚本 + 操作手册 |
| `pass-the-hash/` | PtH 操作手册 + mimikatz 命令 |
| `lateral-movement/` | 横向移动脚本 + 操作手册 |
| `privilege-escalation/` | 权限提升脚本 + 操作手册 |

## 日志采集要点

每个攻击场景执行时，需在 Wazuh 中记录以下信息：

- **攻击开始时间戳**：精确到秒
- **攻击源 IP**：Kali (192.168.56.100) 或 WIN10-01 (192.168.56.30)
- **目标 IP/主机名**
- **使用的工具/命令**
- **关键 Event ID**：
  - Windows 安全日志：4624 (登录成功), 4625 (登录失败), 4672 (特权登录), 4688 (进程创建)
  - Sysmon：1 (进程创建), 3 (网络连接), 11 (文件创建), 13 (注册表修改)
- **Wazuh 告警 ID**：攻击触发的所有告警
