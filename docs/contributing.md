# 贡献指南

## 提交规范

采用 [Conventional Commits](https://www.conventionalcommits.org/) 规范：

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Type 类型

| Type | 用途 | 示例 |
|------|------|------|
| `feat` | 新功能/新文件 | `feat: 添加暴力破解检测规则` |
| `fix` | 修复问题 | `fix: 修正规则中的 EventID` |
| `docs` | 文档变更 | `docs: 更新环境搭建步骤` |
| `refactor` | 重构（不改变功能） | `refactor: 统一变量命名` |
| `test` | 测试相关 | `test: 添加攻击脚本验证用例` |
| `chore` | 构建/工具/杂项 | `chore: 更新 .gitignore` |

### Scope 范围

- `setup`：环境搭建相关
- `attack`：攻击模拟相关
- `detection`：检测规则相关
- `report`：分析报告相关
- `scripts`：通用脚本
- `docs`：架构/设计文档

### 示例

```
feat(detection): 添加 Pass-the-Hash Sigma 检测规则

- 基于 Sysmon Event ID 1 监控 mimikatz 等凭证窃取工具
- 基于 Windows 安全日志 4624 监控异常 NTLM 认证
- 关联分析：凭证窃取进程 + 后续远程登录
```

## 分支策略

```
main (保护分支，始终可运行)
  │
  └── feature/xxx       (功能开发分支)
```

**工作流**：
1. 从 `main` 创建特性分支
2. 在特性分支上频繁提交（小步快跑）
3. 功能完成后合并回 `main`（用 `--no-ff` 保留合并记录）
4. 发布版本时打 Tag：`v1.0.0`、`v1.1.0` 等

## 提交前检查清单

- [ ] 不包含真实生产环境密码、Hash、Token
- [ ] 脚本中的敏感信息使用占位符或环境变量
- [ ] 文档中 IP 地址使用实验室规划地址（192.168.56.x）
- [ ] Commit message 符合规范
- [ ] 每个 Commit 只做一件事（原子性）
- [ ] 代码/脚本有基本注释

## .gitignore 配置

```gitignore
# 操作系统
Thumbs.db
.DS_Store
desktop.ini

# 虚拟机
*.vbox
*.vdi
*.vmdk
*.ova
VirtualBox VMs/

# 敏感信息
*.env
*.key
*.pem
secrets/
credentials/

# 日志
*.log
logs/

# 临时文件
*.tmp
*.bak
*.swp
*~
```

## 代码风格

### PowerShell

- 使用 4 空格缩进
- 函数名使用 PascalCase
- 变量名使用 camelCase
- 关键步骤添加注释

### Python

- 遵循 PEP 8
- 使用 4 空格缩进
- 函数名使用 snake_case
- 添加 docstring

### YAML (Sigma 规则)

- 2 空格缩进
- 必须包含 title、id、status、description、logsource、detection、level 字段
- id 使用 UUID v4
