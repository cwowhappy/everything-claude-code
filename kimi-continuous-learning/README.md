# Kimi Code CLI Continuous Learning

> 让 Kimi Code CLI 自动从你的每次会话中学习，记住你的偏好、习惯和项目约定。

## 目录

- [快速开始](#快速开始)
- [核心概念](#核心概念)
- [安装](#安装)
- [配置](#配置)
- [日常使用](#日常使用)
- [命令参考](#命令参考)
- [项目隔离](#项目隔离)
- [隐私与安全](#隐私与安全)
- [故障排除](#故障排除)
- [卸载](#卸载)

---

## 快速开始

```bash
# 1. 安装
bash install.sh

# 2. 启动后台分析进程
~/.kimi/learning/agents/start-observer.sh start

# 3. 正常使用 kimi，每次会话结束后系统自动学习

# 4. 查看学到了什么
python3 ~/.kimi/learning/scripts/instinct-cli.py status
```

---

## 核心概念

### Observation（观察）

每次你在 Kimi CLI 中使用工具（如 ReadFile、Edit、Grep）时，系统会无感地记录：

```json
{"timestamp": "2025-05-04T14:30:00Z", "event": "tool_complete", "tool": "ReadFile", "session": "...", "project_id": "a1b2c3d4e5f6"}
```

这些数据**只保存在你的本地**（`~/.kimi/learning/projects/<hash>/observations.jsonl`），默认 30 天后自动归档。

### Instinct（本能）

从大量观察中提取出的**原子级行为模式**，例如：

```yaml
---
id: grep-before-edit
confidence: 0.75
domain: workflow
scope: project
---
# Grep Before Edit
## Action
Always use Grep to locate content before using Edit or WriteFile.
```

| 属性 | 说明 |
|------|------|
| `id` | 唯一标识（kebab-case） |
| `confidence` | 0.3~0.9，反映模型对这个模式的确信程度 |
| `domain` | 分类：`code-style` / `testing` / `git` / `workflow` / `security` |
| `scope` | `project`（仅当前项目）或 `global`（跨项目共享） |

### Evolved Skill（进化技能）

当 Instinct 的置信度达到阈值（默认 0.7）时，可聚类为标准 Skill：

```markdown
---
name: grep-before-edit
description: Always search before editing files.
---
# Grep Before Edit
...
```

进化后的 Skill 会自动放入 `~/.kimi/skills/learned/`，下次 Kimi CLI 启动时**自动注入 system prompt**。

---

## 安装

### 前置条件

- macOS / Linux
- Kimi Code CLI（`~/.kimi` 目录存在）
- Python 3（用于脱敏和分析）

### 一键安装

```bash
git clone <repo>  # 或直接下载本目录
cd kimi-continuous-learning
bash install.sh
```

`install.sh` 会：

1. 创建 `~/.kimi/learning/` 目录结构
2. 复制所有脚本和配置
3. 自动在 `~/.kimi/config.toml` 中注册 3 个 Hook

### 手动安装

如果你不想运行 install.sh，可以手动配置：

```bash
mkdir -p ~/.kimi/learning/{hooks,scripts,agents,projects}
mkdir -p ~/.kimi/skills/learned

cp hooks/observe.sh ~/.kimi/learning/hooks/
cp scripts/*.py ~/.kimi/learning/scripts/
cp scripts/*.sh ~/.kimi/learning/scripts/
cp agents/*.sh ~/.kimi/learning/agents/
cp config.default.toml ~/.kimi/learning/config.toml
```

然后在 `~/.kimi/config.toml` 中添加：

```toml
[[hooks]]
event = "PreToolUse"
command = "~/.kimi/learning/hooks/observe.sh pre"
timeout = 5

[[hooks]]
event = "PostToolUse"
command = "~/.kimi/learning/hooks/observe.sh post"
timeout = 5

[[hooks]]
event = "SessionEnd"
command = "~/.kimi/learning/hooks/observe.sh stop"
timeout = 30
```

---

## 配置

编辑 `~/.kimi/learning/config.toml`：

```toml
[learning.observer]
enabled = false          # 是否启动后台 Observer（默认关闭，手动启动）
run_interval_minutes = 5 # Observer 分析周期
min_observations_to_analyze = 20  # 触发分析的最低观察数
model = "kimi-mini"      # 分析用模型（预留，当前用启发式规则）

[learning.observation]
max_file_size_mb = 10    # 单个 observations.jsonl 上限，超限自动归档
archive_after_days = 30  # 旧数据自动清理
secret_scrubbing = true  # 是否脱敏 api_key / token / password

[learning.instinct]
default_confidence = 0.5              # 新 Instinct 初始置信度
confidence_decay_days = 30            # 置信度衰减周期
auto_promote_threshold = 0.8          # Project → Global 晋升阈值
auto_promote_min_projects = 2         # 晋升所需最少项目数

[learning.evolution]
min_confidence_for_skill = 0.7        # 进化为 Skill 的最低置信度
output_dir = "~/.kimi/skills/learned" # Skill 输出目录
sync_to_learned = true                # 是否自动同步到 Kimi Skill 路径
```

---

## 日常使用

### 启动后台 Observer（推荐）

```bash
# 启动
~/.kimi/learning/agents/start-observer.sh start

# 查看状态
~/.kimi/learning/agents/start-observer.sh status

# 停止
~/.kimi/learning/agents/start-observer.sh stop

# 重启
~/.kimi/learning/agents/start-observer.sh restart
```

Observer 会：
- 每 5 分钟扫描一次所有项目的 observations
- 从 SIGUSR1 信号触发即时分析（每次会话结束 20 次工具调用后）
- 自动归档过期的 observations 文件

### 查看学习成果

```bash
# 列出所有 instincts
python3 ~/.kimi/learning/scripts/instinct-cli.py status

# 只看当前项目的
python3 ~/.kimi/learning/scripts/instinct-cli.py status --project-only

# 查看某个 instinct 详情
python3 ~/.kimi/learning/scripts/instinct-cli.py show grep-before-edit
```

### 进化 Skill

```bash
# 将高置信度 Instinct 转化为 Skill
python3 ~/.kimi/learning/scripts/instinct-cli.py evolve

# 预览但不写入
python3 ~/.kimi/learning/scripts/instinct-cli.py evolve --dry-run
```

### 晋升 Global

```bash
# 手动晋升某个 project instinct
python3 ~/.kimi/learning/scripts/instinct-cli.py promote grep-before-edit

# 自动晋升所有符合条件的（≥2 项目 + confidence ≥ 0.8）
python3 ~/.kimi/learning/scripts/instinct-cli.py promote --auto
```

### 备份与迁移

```bash
# 导出所有 instincts
python3 ~/.kimi/learning/scripts/instinct-cli.py export -o my-instincts.yaml

# 按 domain 过滤导出
python3 ~/.kimi/learning/scripts/instinct-cli.py export --domain workflow -o workflow.yaml

# 导入到另一台机器
python3 ~/.kimi/learning/scripts/instinct-cli.py import my-instincts.yaml
```

### 维护

```bash
# 删除旧的归档 observations
python3 ~/.kimi/learning/scripts/instinct-cli.py purge --days 30

# 执行置信度衰减（长时间未更新的 instinct 降权）
python3 ~/.kimi/learning/scripts/instinct-cli.py decay

# 删除某个 instinct（同时删除 evolved skill）
python3 ~/.kimi/learning/scripts/instinct-cli.py delete grep-before-edit
```

---

## 命令参考

### `instinct-cli.py` 子命令

| 命令 | 参数 | 说明 |
|------|------|------|
| `status` | `[--project-only] [--global-only]` | 列出 instincts |
| `show` | `<id>` | 显示详情 |
| `evolve` | `[--dry-run] [--project <hash>]` | 聚类为 Skill |
| `promote` | `[<id>] [--auto] [--dry-run]` | Project → Global |
| `export` | `[-o file] [--scope] [--domain] [--project-id]` | 导出 |
| `import` | `<file>` | 导入 |
| `purge` | `[--days N]` | 清理旧数据 |
| `decay` | — | 置信度衰减 |
| `delete` | `<id>` | 删除 |

### Shell 别名建议

添加到 `~/.bashrc` 或 `~/.zshrc`：

```bash
alias kl-status='python3 ~/.kimi/learning/scripts/instinct-cli.py status'
alias kl-evolve='python3 ~/.kimi/learning/scripts/instinct-cli.py evolve'
alias kl-promote='python3 ~/.kimi/learning/scripts/instinct-cli.py promote --auto'
alias kl-observer='~/.kimi/learning/agents/start-observer.sh'
```

---

## 项目隔离

本系统默认使用 **project-scoped instincts**，防止 React 项目的习惯污染 Python 项目。

### 项目检测优先级

1. `KIMI_PROJECT_DIR` 环境变量
2. `git remote get-url origin` → SHA256 前 12 字符
3. `~/.kimi/kimi.json` 中的 `work_dirs` 匹配
4. `git rev-parse --show-toplevel`

### Scope 决策指南

| 模式类型 | 默认 Scope | 示例 |
|----------|-----------|------|
| 语言/框架约定 | **project** | "Python 类型注解必填" |
| 项目结构偏好 | **project** | "测试放 `__tests__/`" |
| 通用工作流 | **global** | "先 grep 再 edit" |
| 安全实践 | **global** | "验证用户输入" |
| Git 实践 | **global** | "conventional commits" |

### 自动晋升

同一 Instinct 在 ≥2 个项目中出现，平均置信度 ≥0.8 → 自动晋升 global。

---

## 隐私与安全

### 数据本地性

| 数据 | 位置 | 是否联网 |
|------|------|---------|
| 原始 observations | `~/.kimi/learning/` 本地 | ❌ 不上传 |
| Instincts | `~/.kimi/learning/` 本地 | ❌ 不上传 |
| Skills | `~/.kimi/skills/learned/` 本地 | ❌ 不上传 |

### 脱敏

Hook 脚本自动对以下字段脱敏：

```
api_key, token, secret, password, authorization, credentials, auth
```

示例：`"api_key": "sk-abc123"` → `"api_key": "[REDACTED]"`

### 用户控制

| 操作 | 效果 |
|------|------|
| `touch ~/.kimi/learning/disabled` | **完全禁用**所有 Hook |
| `ECC_SKIP_OBSERVE=1 kimi` | 单次会话跳过 |
| `ECC_HOOK_PROFILE=minimal` | 关闭非必要 Hook（包括观察） |
| `~/.kimi/learning/agents/start-observer.sh stop` | 停止后台分析 |

---

## 故障排除

### Hook 没有触发

```bash
# 1. 检查 config.toml 中 hooks 是否注册
grep -A2 "kimi/learning/hooks" ~/.kimi/config.toml

# 2. 检查 disabled 文件
ls ~/.kimi/learning/disabled 2>/dev/null && echo "已禁用" || echo "未禁用"

# 3. 测试 Hook 手动执行
echo '{"tool_name":"ReadFile","cwd":"'$(pwd)'"}' | ~/.kimi/learning/hooks/observe.sh pre

# 4. 查看 observations 是否写入
ls ~/.kimi/learning/projects/*/observations.jsonl
```

### Observer 没有启动

```bash
# 检查 PID
~/.kimi/learning/agents/start-observer.sh status

# 查看日志（当前输出到 stdout，后台运行时无日志文件）
# 手动前台运行观察：
bash ~/.kimi/learning/agents/observer-loop.sh
```

### Instinct 置信度太低，无法 evolve

```bash
# 方案 A：降低阈值
sed -i '' 's/min_confidence_for_skill = 0.7/min_confidence_for_skill = 0.5/' ~/.kimi/learning/config.toml

# 方案 B：手动创建高置信度 instinct
# 编辑 ~/.kimi/learning/projects/<hash>/instincts/personal/*.yaml
# 将 confidence: 改为 ≥ 0.7
```

### 项目检测错误

```bash
# 手动指定项目
cd /your/project
export KIMI_PROJECT_DIR=$(pwd)
kimi

# 或检查 git remote
git remote get-url origin
```

---

## 卸载

```bash
# 1. 停止 Observer
~/.kimi/learning/agents/start-observer.sh stop

# 2. 移除 hooks（手动编辑 ~/.kimi/config.toml，删除 Kimi Continuous Learning Hooks 区块）

# 3. 删除目录
rm -rf ~/.kimi/learning
rm -rf ~/.kimi/skills/learned

# 4. 清理 alias（如已添加）
```

---

## 文件结构

```
~/.kimi/learning/
├── config.toml              # 配置
├── observations.jsonl       # Global fallback
├── projects.json            # 项目注册表
├── disabled                 # 存在时禁用所有 Hook
├── hooks/
│   └── observe.sh           # 核心 Hook
├── scripts/
│   ├── instinct-cli.py      # 管理 CLI
│   ├── analyze-observations.py  # 分析引擎
│   └── detect-project.sh    # 项目检测
├── agents/
│   ├── start-observer.sh    # Observer 启动器
│   └── observer-loop.sh     # Observer 主循环
├── projects/
│   └── <hash>/
│       ├── observations.jsonl
│       ├── observations.archive/
│       └── instincts/personal/
└── instincts/
    ├── personal/            # Global instincts
    └── evolved/skills/      # 生成的 Skill

~/.kimi/skills/learned/      # Kimi CLI 自动加载
└── <skill>/
    └── SKILL.md
```

---

*让 Kimi 记住你的每一次纠正，一次学习，终身受益。*
