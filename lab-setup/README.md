# 实验室环境搭建

> 搭建 AD 域 + Wazuh SIEM + Sysmon 的完整监控环境

## 执行顺序

```
1. 虚拟机网络配置 (VirtualBox Host-Only)
2. AD 域控搭建 (DC01)
3. Wazuh Server 安装 (Ubuntu)
4. Windows 客户端加入域
5. Sysmon 部署到所有 Windows 主机
6. Wazuh Agent 部署到所有 Windows 主机
7. 验证日志采集与告警
```

## 前置要求

- VirtualBox 7.0+ / VMware Workstation 17+
- Windows Server 2022 评估版 ISO
- Windows 10/11 企业版 ISO
- Ubuntu Server 22.04 LTS ISO
- Kali Linux 2024.x ISO
- 至少 16GB 内存（同时运行 3-4 台虚拟机）

## 各子目录说明

| 目录 | 内容 |
|------|------|
| `ad-dc/` | AD 域控自动化配置脚本 |
| `wazuh-server/` | Wazuh 一键安装脚本与配置 |
| `windows-client/` | 客户端加域与基础加固脚本 |
| `sysmon/` | Sysmon 配置文件与安装脚本 |

## 验证清单

- [ ] AD 域控可正常解析 `corp.local`
- [ ] 两台 Windows 客户端已加入域
- [ ] Wazuh Dashboard 可通过 `https://192.168.56.10` 访问
- [ ] 所有 Windows 主机在 Wazuh 中显示为 Active
- [ ] Sysmon 事件（Event ID 1/3/11）可在 Wazuh 中搜索到
- [ ] 触发一次测试登录失败，Wazuh 产生告警
