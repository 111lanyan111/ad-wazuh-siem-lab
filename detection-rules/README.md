# 检测规则编写

> 基于攻击场景采集的日志，编写 Sigma 格式检测规则和 Wazuh 自定义规则

## 规则总览

| # | 规则名称 | 类型 | 攻击场景 | 严重级别 |
|---|----------|------|----------|----------|
| 1 | win_brute_force_login | Sigma | 暴力破解 | high |
| 2 | win_brute_force_then_success | Sigma | 暴力破解 | critical |
| 3 | win_mimikatz_detection | Sigma | Pass-the-Hash | critical |
| 4 | win_pass_the_hash_ntlm | Sigma | Pass-the-Hash | high |
| 5 | win_lateral_movement_psexec | Sigma | 横向移动 | high |
| 6 | win_lateral_movement_service | Sigma | 横向移动 | high |
| 7 | win_privilege_escalation_service | Sigma | 权限提升 | critical |
| 8 | win_privilege_escalation_juicypotato | Sigma | 权限提升 | critical |
| 9 | win_suspicious_admin_user_creation | Sigma | 权限提升/横向移动 | high |

## Sigma 规则规范

### 规则结构

```yaml
title: 规则名称
id: UUID (唯一标识)
status: experimental / stable
description: 规则描述
references:
  - 参考链接
tags:
  - attack.tactic
  - attack.technique
author: 作者
date: YYYY-MM-DD
modified: YYYY-MM-DD
logsource:
  product: windows
  service: security / sysmon
detection:
  selection:
    # 匹配条件
  condition: selection
falsepositives:
  - 误报场景
level: low / medium / high / critical
```

### 字段映射

| Windows 字段 | Sigma 字段 | 说明 |
|-------------|-----------|------|
| EventID | EventID | 事件 ID |
| SubjectUserName | SubjectUserName | 主体用户名 |
| TargetUserName | TargetUserName | 目标用户名 |
| IpAddress | IpAddress | 源 IP 地址 |
| LogonType | LogonType | 登录类型 |
| Image | Image | 进程镜像路径 |
| CommandLine | CommandLine | 命令行 |
| ParentImage | ParentImage | 父进程镜像 |

## Wazuh 自定义规则

Wazuh 规则使用 XML 格式，存放在 `/var/ossec/etc/rules/` 目录下。

### 规则级别

| 级别 | 名称 | 说明 |
|------|------|------|
| 1-2 | 低 | 信息性事件 |
| 3-5 | 中 | 需要关注的异常 |
| 6-8 | 高 | 安全事件，需要调查 |
| 9-10 | 严重 | 确认的攻击，需要立即响应 |
| 11-12 | 紧急 | 系统已失陷 |

## 规则验证流程

1. **语法检查**：使用 `sigmac` 或 `sigma-cli` 验证 Sigma 规则语法
2. **离线测试**：使用攻击场景采集的日志样本测试规则匹配
3. **在线部署**：将规则导入 Wazuh，触发攻击验证告警
4. **误报调优**：根据实际环境调整阈值和排除条件
5. **性能测试**：确认规则不会导致 Wazuh 性能下降

## 目录结构

```
detection-rules/
├── README.md                    # 本文件
├── sigma/                       # Sigma 规则
│   ├── win_brute_force_login.yml
│   ├── win_brute_force_then_success.yml
│   ├── win_mimikatz_detection.yml
│   ├── win_pass_the_hash_ntlm.yml
│   ├── win_lateral_movement_psexec.yml
│   ├── win_lateral_movement_service.yml
│   ├── win_privilege_escalation_service.yml
│   ├── win_privilege_escalation_juicypotato.yml
│   └── win_suspicious_admin_user_creation.yml
└── wazuh-custom/                # Wazuh 自定义规则
    └── local_ad_lab_rules.xml
```
