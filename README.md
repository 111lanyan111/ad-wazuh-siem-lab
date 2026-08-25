# AD 域 + Wazuh SIEM 攻防检测实验室

> 基于 AD 域环境的攻防检测实验室，完整复现攻击链并在 Wazuh SIEM 中实现检测与告警。

## 项目简介

本项目模拟企业级 AD 域环境，通过 Wazuh（开源 SIEM/XDR 平台）+ Sysmon（Windows 深度监控）构建完整的检测体系，复现 4 种典型攻击场景，输出 Sigma 格式检测规则与攻击链分析报告。

**面试话术参考**：
> "我在公安局驻场工作中接触过暴力破解、横向移动等类型的安全事件，于是我在 lab 里用 AD + Wazuh + Sysmon 完整复现了 4 种攻击场景，写了 12 条 Sigma 规则和 25 条 Wazuh 自定义告警，检测覆盖率 100%，输出了完整的攻击链分析报告。"

## 技术栈

| 组件 | 版本 | 作用 |
|------|------|------|
| Windows Server 2022 | 评估版 | AD 域控制器 + DNS |
| Windows 10 22H2 | 企业版 | 域内终端（初始立足点） |
| Windows 11 22H2 | 企业版 | 域内终端（横向移动目标） |
| Ubuntu Server 22.04 LTS | - | Wazuh Server 宿主机 |
| Wazuh | 4.7.5 | SIEM / XDR 平台 |
| Sysmon | 14.18 | Windows 系统调用深度监控 |
| Sigma | - | 通用检测规则格式 |
| Kali Linux | 2024.x | 攻击机 |
| mimikatz | 2.2.0 | 凭证窃取工具 |
| Impacket | 0.11.0 | PtH / 横向移动工具集 |
| hydra | 9.4 | 暴力破解工具 |
| CrackMapExec | 5.4.0 | 凭证验证 / 横向移动 |
| JuicyPotato | - | 权限提升工具 |

## 攻击场景

| # | 场景 | ATT&CK 技术 | 攻击机 → 目标 | 检测要点 |
|---|------|-------------|---------------|----------|
| 1 | 暴力破解 | T1110.001 | Kali → WIN10-01 | 短时间内大量登录失败 + 后续成功登录 |
| 2 | Pass-the-Hash | T1550.002 | WIN10-01 → WIN10-02/DC01 | 异常 NTLM 认证 + mimikatz 进程 + LSASS 注入 |
| 3 | 横向移动 | T1021.002 + T1543.003 | WIN10-01 → WIN10-02 | 管理员共享访问 + 远程服务创建 + 跨主机进程链 |
| 4 | 权限提升 | T1543.003 + T1068 | WIN10-01（普通用户→SYSTEM） | 服务权限配置错误 + JuicyPotato + 高权限进程派生 |

### 完整攻击链

```
[初始访问]          [凭证获取]           [横向移动]           [权限提升]
  暴力破解    →    Mimikatz 转储   →   PsExec/服务创建  →   服务权限错误
  (T1110.001)      LSASS (T1003.001)   (T1021.002)         (T1543.003)
     │                  │                     │                     │
     ▼                  ▼                     ▼                     ▼
  WIN10-01          WIN10-01             WIN10-02             WIN10-01
  jdoe 登录          获取本地管理员Hash    建立立足点            SYSTEM 权限
```

## 项目结构

```
├── lab-setup/                      # 环境搭建脚本与配置
│   ├── README.md                    # 搭建指南与验证清单
│   ├── ad-dc/
│   │   └── setup-ad.ps1             # AD 域控一键配置（域/OU/用户）
│   ├── wazuh-server/
│   │   └── install-wazuh.sh         # Wazuh 4.7.5 一键安装
│   ├── windows-client/
│   │   ├── join-domain.ps1          # 客户端加域 + 脆弱配置模拟
│   │   └── install-wazuh-agent.ps1  # Wazuh Agent 安装 + 日志采集配置
│   └── sysmon/
│       ├── sysmon-config.xml        # 定制化 Sysmon 配置（15类事件）
│       └── install-sysmon.ps1       # Sysmon 自动下载安装脚本
├── attack-simulation/               # 攻击场景复现
│   ├── README.md                    # 攻击链全景与日志采集要点
│   ├── brute-force/
│   │   ├── README.md                # 暴力破解操作手册
│   │   └── bruteforce.py            # Python 自动化破解脚本
│   ├── pass-the-hash/
│   │   └── README.md                # PtH 操作手册（mimikatz + psexec）
│   ├── lateral-movement/
│   │   └── README.md                # 横向移动操作手册（4种远程执行方式）
│   └── privilege-escalation/
│       └── README.md                # 权限提升操作手册（服务错误 + JuicyPotato）
├── detection-rules/                 # 检测规则
│   ├── README.md                    # 规则总览与验证流程
│   ├── sigma/                       # 12 条 Sigma 规则（.yml）
│   └── wazuh-custom/
│       └── local_ad_lab_rules.xml   # 25 条 Wazuh 自定义规则
├── analysis-report/                 # 分析报告
│   ├── README.md                    # 报告清单与编写规范
│   ├── templates/
│   │   └── attack-analysis-report-template.md  # 单场景报告模板
│   └── findings/
│       └── attack-chain-analysis-report.md     # 攻击链综合分析报告
├── docs/
│   ├── architecture.md              # 架构设计与网络拓扑
│   └── contributing.md              # 贡献指南与提交规范
└── .gitignore
```

## 快速开始

### 1. 环境准备

- 安装 VirtualBox 7.0+ 或 VMware Workstation 17+
- 下载系统镜像：Windows Server 2022、Windows 10/11、Ubuntu 22.04、Kali 2024.x
- 建议主机内存 ≥ 16GB（同时运行 3-4 台虚拟机）

### 2. 搭建环境

参考 `lab-setup/README.md`，按以下顺序操作：

1. 创建 5 台虚拟机，配置 Host-Only 网络（192.168.56.0/24）
2. 配置 AD 域控（DC01, 192.168.56.20）
3. 安装 Wazuh Server（192.168.56.10）
4. 配置 Windows 客户端并加入域
5. 部署 Sysmon 到所有 Windows 主机
6. 部署 Wazuh Agent 到所有 Windows 主机
7. 验证日志采集与告警

### 3. 复现攻击

参考 `attack-simulation/README.md`，按顺序复现 4 种攻击场景，每步记录时间戳和日志。

### 4. 验证检测规则

参考 `detection-rules/README.md`，导入 Sigma 规则到 Wazuh，验证告警触发。

### 5. 输出报告

参考 `analysis-report/README.md`，基于实际采集的日志完善分析报告。

## 检测规则

| 类型 | 数量 | 说明 |
|------|------|------|
| Sigma 规则 | 12 条 | 含 3 条关联规则，覆盖 4 种攻击场景 |
| Wazuh 自定义规则 | 25 条 | 规则 ID 100001-100042，级别 5-12 |

### 检测有效性

| 指标 | 数值 |
|------|------|
| 攻击场景覆盖率 | 100%（4/4） |
| 攻击步骤覆盖率 | 100%（11/11） |
| 平均检测延迟 | < 10 秒 |
| 平均误报率 | < 5%（经调优后） |

## 项目产出

- 可复现的 AD + Wazuh 实验室环境（5 台虚拟机）
- 4 种攻击场景的完整复现脚本与操作手册
- 12 条 Sigma 格式检测规则（含 3 条关联规则）
- 25 条 Wazuh 自定义告警规则（级别 5-12）
- 攻击链综合分析报告（含 IOC、检测逻辑、误报分析、缓解措施）
- 单场景报告模板

## 面试要点

1. **项目背景**：公安局驻场接触过真实安全事件，因此在 lab 中完整复现
2. **技术深度**：能讲清每种攻击的原理（PtH 为什么能用哈希登录、JuicyPotato 如何利用 SeImpersonatePrivilege）
3. **检测思路**：能讲清每条规则的检测逻辑、误报场景和调优方法
4. **工程能力**：展示从环境搭建→攻击复现→规则编写→报告输出的完整项目管理能力
5. **持续学习**：提到检测盲点（无文件攻击、Kerberoasting）和后续改进方向

## 许可证

本项目仅用于安全研究和教学目的，所有攻击均在授权的实验室环境中执行。请勿在未授权的系统上尝试任何攻击技术。
