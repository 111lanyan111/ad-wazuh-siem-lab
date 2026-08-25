# 架构设计

## 整体架构

```
                        ┌─────────────────────────────────────┐
                        │           Wazuh Server               │
                        │      (Ubuntu 22.04, 192.168.56.10)  │
                        │  ┌─────────┬──────────┬──────────┐  │
                        │  │ Wazuh   │ Filebeat │ OpenSearch│  │
                        │  │ Manager │          │ (索引)    │  │
                        │  └─────────┴──────────┴──────────┘  │
                        │  ┌─────────────────────────────────┐  │
                        │  │ Wazuh Dashboard (Web UI :443)   │  │
                        │  └─────────────────────────────────┘  │
                        └───────────────┬───────────────────────┘
                                        │ Agent 通信 (TCP 1514/1515)
            ┌───────────────────────────┼───────────────────────────┐
            │                           │                           │
  ┌─────────▼─────────┐     ┌──────────▼──────────┐     ┌────────▼────────┐
  │   AD 域控制器      │     │   Windows 客户端     │     │   Windows 客户端 │
  │  Windows Server    │     │   Windows 10/11      │     │   Windows 10/11 │
  │  192.168.56.20    │     │   192.168.56.30     │     │   192.168.56.31 │
  │  DC01.corp.local  │     │   WIN10-01.corp.local│     │   WIN10-02       │
  │  + Sysmon + Agent  │     │   + Sysmon + Agent   │     │   + Sysmon + Agent│
  └─────────┬─────────┘     └──────────┬──────────┘     └───────────────────┘
            │                           │
            │     AD 域: corp.local     │
            └───────────────────────────┘
                        │
              ┌─────────▼─────────┐
              │   Kali 攻击机      │
              │   192.168.56.100  │
              │   (仅 Host-Only)   │
              └───────────────────┘
```

## 网络规划

| 主机名 | IP 地址 | 操作系统 | 角色 | 内存 | CPU |
|--------|---------|----------|------|------|-----|
| wazuh-server | 192.168.56.10 | Ubuntu 22.04 | SIEM 平台 | 4GB | 2核 |
| DC01 | 192.168.56.20 | Windows Server 2022 | AD 域控 + DNS | 2GB | 2核 |
| WIN10-01 | 192.168.56.30 | Windows 10 22H2 | 域内终端（初始立足点） | 2GB | 2核 |
| WIN10-02 | 192.168.56.31 | Windows 11 22H2 | 域内终端（横向目标） | 2GB | 2核 |
| kali | 192.168.56.100 | Kali 2024.x | 攻击机 | 2GB | 2核 |

**网络模式**：VirtualBox Host-Only 网络（vboxnet0），所有主机在同一二层网络。Kali 可访问 Windows 主机，但 Windows 主机不主动访问 Kali。

## AD 域设计

- **域名**：`corp.local`
- **NetBIOS 名**：`CORP`
- **功能级别**：Windows Server 2016 域/林功能级别
- **OU 结构**：
  ```
  corp.local
  ├── Servers
  │   └── Domain Controllers
  ├── Workstations
  │   ├── IT
  │   └── Finance
  └── Users
      ├── Service Accounts
      └── Employees
  ```

### 测试账号

| 用户名 | 密码 | 所属组 | 用途 |
|--------|------|--------|------|
| administrator | P@ssw0rd!2024 | Domain Admins | 域管理员 |
| svc_sql | SQL@2024pass | Domain Users | 服务账号（弱口令） |
| jdoe | Winter2024! | Domain Users | 普通用户（初始立足点） |
| backup_admin | Backup@2024 | Backup Operators | 备份操作员 |

## 数据流

1. **Sysmon** 在 Windows 主机上捕获进程创建、网络连接、文件创建、注册表修改等事件，写入 Windows Event Log（`Microsoft-Windows-Sysmon/Operational`）
2. **Wazuh Agent** 读取 Windows Event Log（包括 Sysmon 通道）和系统日志，通过 TCP 1514 发送到 Wazuh Server
3. **Wazuh Manager** 对日志进行解码、规则匹配，生成告警
4. **Filebeat** 将告警和原始日志推送到 OpenSearch 进行索引
5. **Wazuh Dashboard** 提供 Web UI 进行告警查看、搜索、仪表盘

## 检测能力矩阵

| 数据来源 | 可检测的 ATT&CK 技术 |
|----------|----------------------|
| Windows 安全日志 (4624/4625/4672) | 暴力破解、异常登录、特权使用 |
| Sysmon Event ID 1 (进程创建) | 几乎所有执行类技术、可疑命令行 |
| Sysmon Event ID 3 (网络连接) | C2 通信、横向移动、端口扫描 |
| Sysmon Event ID 11 (文件创建) | 恶意软件落地、启动项写入 |
| Sysmon Event ID 13 (注册表修改) | 持久化、凭证窃取配置 |
| Wazuh FIM (文件完整性监控) | 关键系统文件篡改、Webshell 写入 |
| Wazuh SCA (安全配置评估) | 系统加固基线偏离 |
