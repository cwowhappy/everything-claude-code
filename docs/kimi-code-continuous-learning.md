# Kimi Code CLI Continuous Learning v2 方案

> 为 Kimi Code CLI 设计一套类似 ECC `continuous-learning-v2` 的 instinct-based 持续学习系统。
>
> 版本：v1.0-draft  
> 状态：设计阶段

---

## 目录

1. [背景与动机](#1-背景与动机)
2. [Kimi CLI 现有机制盘点](#2-kimi-cli-现有机制盘点)
3. [总体架构](#3-总体架构)
4. [核心设计决策](#4-核心设计决策)
5. [数据模型](#5-数据模型)
6. [目录与文件结构](#6-目录与文件结构)
7. [核心组件详细设计](#7-核心组件详细设计)
8. [与 Kimi CLI 的无缝集成](#8-与-kimi-cli-的无缝集成)
9. [隐私与安全](#9-隐私与安全)
10. [MVP Roadmap](#10-mvp-roadmap)
11. [附录：与 ECC v2 的差异对照](#11-附录与-ecc-v2-的差异对照)

---

## 1. 背景与动机

### 1.1 问题

当前的 AI Coding Agent（包括 Kimi Code CLI）存在以下局限：

- **每次会话从零开始**：模型不会记住你在上一个项目中学到的偏好、纠正、工作流。
- **项目知识无法沉淀**："这个项目的测试放 `__tests__/`"、"这个团队用 functional style"——这些知识随会话结束而丢失。
- **跨会话模式提取困难**：用户需要手动写 `SKILL.md`，维护成本高。

### 1.2 目标

构建一个**自动化、项目隔离、置信度驱动**的持续学习系统，让 Kimi Code CLI 能够：

1. **自动观察**：在每次工具调用中无侵入地捕获行为模式。
2. **原子提取**：将模式提炼为带置信度的 "Instinct"（原子本能）。
3. **项目隔离**：React 项目的习惯不污染 Python 项目。
4. **自动进化**：高置信度的 Instinct 自动聚类为 Skill，注入后续会话的 system prompt。
5. **用户可控**：随时查看、编辑、导出、删除学到的内容。

---

## 2. Kimi CLI 现有机制盘点

本方案**不修改 Kimi CLI 源码**，完全基于其公开扩展点构建。以下是关键机制：

### 2.1 Hook 系统

| 属性 | 详情 |
|------|------|
| 配置位置 | `~/.kimi/config.toml` 中的 `hooks = []` 数组 |
| 支持事件 | `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `UserPromptSubmit`, `Stop`, `StopFailure`, `SessionStart`, `SessionEnd`, `SubagentStart`, `SubagentStop`, `PreCompact`, `PostCompact`, `Notification` |
| 触发方式 | 事件发生时异步执行 shell 命令 |
| 输入 | 事件详情通过 **stdin** 以 JSON 传入 |
| 输出 | `exit_code=0` 正常，`exit_code=2` block（权限决策），stdout JSON 可结构化 |
| 超时 | 默认 30s，超时 fail-open（allow） |
| 并发 | 多个 hook 并行执行 |

### 2.2 Skill 系统

| 属性 | 详情 |
|------|------|
| 发现优先级 | `Project > User > Extra(config) > Extra(plugins) > Built-in` |
| 用户级路径 | `~/.kimi/skills/`, `~/.claude/skills/`, `~/.codex/skills/`（brand group） |
| 通用用户路径 | `~/.config/agents/skills/`, `~/.agents/skills/` |
| 项目级路径 | `<project_root>/.kimi/skills/`, `<project_root>/.agents/skills/` |
| 格式 | 子目录 `<name>/SKILL.md` 或扁平 `<name>.md` |
| Frontmatter | 支持 `name`, `description`, `type` |
| 加载 | `merge_all_available_skills = true` 时自动合并到 system prompt |

### 2.3 后台任务系统

| 属性 | 详情 |
|------|------|
| API | `BackgroundTaskManager.create_agent_task()` / `create_bash_task()` |
| 类型 | Bash 脚本 或 Agent 子任务 |
| 并发 | `max_running_tasks = 4` |
| 超时 | `agent_task_timeout_s = 900` |
| 存储 | `~/.kimi/sessions/<workdir_hash>/<session_id>/tasks/<task_id>/` |
| 限制 | 内部 API，Hook 脚本无法直接调用；需通过 CLI 命令或独立进程触发 |

### 2.4 会话存储

| 文件 | 内容 |
|------|------|
| `~/.kimi/sessions/<workdir_hash>/<session_id>/context.jsonl` | 完整上下文历史（消息、工具调用） |
| `~/.kimi/sessions/<workdir_hash>/<session_id>/wire.jsonl` | Wire 协议原始消息 |
| `~/.kimi/sessions/<workdir_hash>/<session_id>/state.json` | 会话状态（模型、参数等） |
| `~/.kimi/kimi.json` | 工作目录注册表（`work_dirs` 数组） |

### 2.5 工作目录隔离

Kimi CLI 已按 `work_dir` hash 分组会话：

```
~/.kimi/sessions/
└── <workdir_hash>/          # 如 375a564deaa167fa602a1273b2ba5193
    ├── <session_id_1>/
    └── <session_id_2>/
```

`~/.kimi/kimi.json` 中记录：`{"work_dirs": [{"path": "...", "last_session_id": "..."}]}`

**结论**：这些机制足以支撑 continuous-learning-v2 的全部需求，且目录结构天然支持项目隔离。

---

## 3. 总体架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Kimi Code CLI Session                         │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐   │
│  │  PreToolUse  │  │  PostToolUse │  │      SessionEnd          │   │
│  │    Hook      │  │    Hook      │  │      Hook                │   │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────────┘   │
│         │                  │                      │                   │
│         └──────────────────┼──────────────────────┘                   │
│                            ▼                                         │
│              ┌─────────────────────────────┐                         │
│              │    observe.sh (shell)       │                         │
│              │  - 接收 stdin JSON          │                         │
│              │  - 项目检测                 │                         │
│              │  - 数据脱敏                 │                         │
│              │  - 写入 observations.jsonl  │                         │
│              │  - 懒启动 Observer          │                         │
│              └──────────────┬──────────────┘                         │
│                             │                                        │
└─────────────────────────────┼────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────────┐
              │      ~/.kimi/learning/            │
              │  ┌─────────────────────────────┐  │
              │  │  observations.jsonl         │  │  ← Global fallback
              │  │  config.toml                │  │
              │  │  projects.json              │  │  ← 项目注册表
              │  └─────────────────────────────┘  │
              │  projects/                        │
              │  └── <workdir_hash>/              │
              │      ├── observations.jsonl       │
              │      ├── observations.archive/    │
              │      └── instincts/               │
              │          └── personal/            │
              │  instincts/                       │
              │  ├── personal/                    │  ← Global instincts
              │  └── evolved/                     │
              │      ├── skills/                  │
              │      ├── commands/                │
              │      └── agents/                  │
              └─────────────────┬─────────────────┘
                                │
              ┌─────────────────┴─────────────────┐
              │                                   │
              ▼                                   ▼
    ┌───────────────────┐             ┌─────────────────────┐
    │  Observer Agent   │             │  Manual /evolve     │
    │  (独立后台进程)   │             │  (SessionEnd 触发)  │
    │                   │             │                     │
    │  - 聚类模式       │             │  - 会话总结         │
    │  - 生成 Instinct  │             │  - 即时生成 Skill   │
    │  - 晋升判断       │             │                     │
    └─────────┬─────────┘             └─────────────────────┘
              │
              ▼
    ┌─────────────────────────┐
    │    Instinct YAML        │
    │  (atomic + confidence)  │
    └────────────┬────────────┘
                 │
                 ▼
    ┌─────────────────────────┐
    │  ~/.kimi/skills/learned/│
    │    <skill>/SKILL.md     │
    └─────────────────────────┘
                 │
                 ▼
    ┌─────────────────────────┐
    │  Kimi CLI Skill Loader  │
    │  (自动注入 system prompt)│
    └─────────────────────────┘
```

### 3.1 架构原则

1. **Hook 只做观察，不做分析**：保证轻量、不卡主线程。
2. **分析异步进行**：Observer 是独立进程，失败不影响主会话。
3. **原子粒度**：Instinct 是最小单位，Skill 是聚合单位。
4. **项目优先**：默认 project-scoped，global 需晋升。
5. **证据驱动**：每个 Instinct 必须附带 evidence（观察次数、时间、来源）。

---

## 4. 核心设计决策

### 4.1 观察层：PreToolUse + PostToolUse + SessionEnd

**为什么不用 Stop Hook（v1 方案）**：

| 问题 | 说明 |
|------|------|
| 概率性触发 | Stop Hook 依赖模型在会话结束时主动评估，容易遗漏 |
| 丢失过程信号 | 无法捕获用户实时纠正（UserPromptSubmit 后立即修正的模式） |
| 粒度太粗 | 整会话总结容易淹没细节 |

**采用双 Hook 策略**：

```toml
# ~/.kimi/config.toml

[[hooks]]
event = "PreToolUse"
command = "~/.kimi/learning/hooks/observe.sh pre"
timeout = 5
matcher = ""          # 空表示匹配所有

[[hooks]]
event = "PostToolUse"
command = "~/.kimi/learning/hooks/observe.sh post"
timeout = 5

[[hooks]]
event = "SessionEnd"
command = "~/.kimi/learning/hooks/observe.sh stop"
timeout = 30
```

| Hook | 职责 |
|------|------|
| `PreToolUse` | 记录工具调用意图（tool_name, tool_input, cwd） |
| `PostToolUse` | 记录执行结果（tool_output, 是否成功），与 Pre 配对 |
| `SessionEnd` | 触发 Observer 分析信号；或作为懒启动触发器 |

**自动化守卫（在 observe.sh 中实现）**：

| 守卫层 | 逻辑 | 目的 |
|--------|------|------|
| Layer 1 | 检查 `KIMI_CODE_ENTRYPOINT`，排除非交互式会话 | 防止 SDK 自动化会话被观察 |
| Layer 2 | `ECC_HOOK_PROFILE=minimal` 时退出 | 支持用户显式关闭非必要 hook |
| Layer 3 | `ECC_SKIP_OBSERVE=1` 时退出 | 自动化脚本可自行声明跳过 |
| Layer 4 | stdin JSON 中包含 `agent_id` 时退出 | 子 Agent 会话不观察 |
| Layer 5 | cwd 包含 `observer-sessions`、`.kimi-mem` 等路径时退出 | 防止 Observer 观察自己 |

### 4.2 项目检测与隔离

复用 Kimi CLI 的 `work_dir` hash，建立 **4 层项目检测优先级**：

```
1. KIMI_PROJECT_DIR 环境变量（最高优先级，显式指定）
2. git remote get-url origin → SHA256 前 12 字符（跨机器一致）
3. Kimi CLI work_dirs 匹配 → 复用已有 hash
4. git rev-parse --show-toplevel → 本地路径 hash（兜底）
```

**项目注册表**（`~/.kimi/learning/projects.json`）：

```json
{
  "projects": {
    "a1b2c3d4e5f6": {
      "name": "everything-claude-code",
      "root": "/Users/lixiaoyi/GitRepository/everything-claude-code",
      "remote": "https://github.com/...",
      "first_seen": "2025-05-01T10:00:00Z",
      "last_seen": "2025-05-04T15:30:00Z",
      "instinct_count": 12
    }
  }
}
```

### 4.3 作用域决策指南

| 模式类型 | 默认 Scope | 示例 |
|----------|-----------|------|
| 语言/框架特定约定 | **project** | "Python 类型注解必填", "React 用 hooks" |
| 项目结构偏好 | **project** | "测试放 `__tests__/`", "组件按 feature 组织" |
| 代码风格 | **project** | "函数不超过 50 行", "优先 dataclass" |
| 错误处理策略 | **project** | "Go 返回 `(T, error)`", "Rust 用 `Result`" |
| 安全实践 | **global** | "验证用户输入", "SQL 参数化", "XSS 过滤" |
| 通用工作流 | **global** | "先 grep 再 edit", "先 read 再 write" |
| Git 实践 | **global** | "conventional commits", "小步提交" |
| 调试技巧 | **global** | "先检查文件是否存在", "用 `set -e`" |

**自动晋升规则**：

- 同一 `id` 的 Instinct 出现在 ≥2 个项目中
- 平均 `confidence >= 0.8`
- `/evolve` 或 Observer 自动触发晋升

### 4.4 分析层：Observer 方案选择

由于 Kimi CLI 的 `BackgroundTaskManager` 是内部 Python API，Hook 脚本无法直接调用。提供两种方案：

#### 方案 A：独立 Python Observer（推荐）

```bash
~/.kimi/learning/agents/start-observer.sh
```

- 独立进程，通过文件系统（`observations.jsonl`）与 Hook 通信
- 使用轻量模型（如 `kimi-mini`）或本地小模型分析
- `flock`/`lockfile` 防止多实例
- 信号节流（每 N 条 observations 触发一次分析）

**优点**：简单、可靠、不依赖 Kimi CLI 内部状态、成本低  
**缺点**：需要独立管理进程生命周期

#### 方案 B：Kimi CLI 后台 Agent 任务

在 `SessionEnd` Hook 中，通过 `kimi` CLI 命令启动后台 Agent：

```bash
kimi agent --background \
  --prompt "分析 ~/.kimi/learning/observations.jsonl，提取可复用模式..." \
  --type coder
```

**优点**：与 Kimi CLI 深度集成，利用其 Agent 审批和状态管理  
**缺点**：
- 需要处理 Agent 的 approval 流程
- 成本不可控（与主会话使用相同模型）
- 并发受限（`max_running_tasks = 4`）

**建议**：Phase 1-2 使用方案 A，Phase 3+ 探索方案 B 作为可选增强。

---

## 5. 数据模型

### 5.1 Observation（原始观察）

```json
{
  "timestamp": "2025-05-04T14:30:00Z",
  "event": "tool_complete",
  "tool": "EditFile",
  "session": "session-uuid",
  "project_id": "a1b2c3d4e5f6",
  "project_name": "everything-claude-code",
  "input": "{\"path\":\"src/main.py\",\"old\":\"...\",\"new\":\"...\"}",
  "output": "Edit applied successfully",
  "tool_use_id": "toolu_01AbCdEf"
}
```

### 5.2 Instinct（原子本能）

```yaml
---
id: grep-before-edit
trigger: "when asked to modify existing code files"
confidence: 0.75
domain: workflow
scope: global
source: session-observation
project_id: null
project_name: null
created_at: "2025-05-01T10:00:00Z"
updated_at: "2025-05-04T14:30:00Z"
observation_count: 15
---

# Grep Before Edit

## Action
Always use Grep to locate content before using Edit or WriteFile.

## Evidence
- Observed 12 Pre/PostToolUse sequences: Grep → Read → Edit
- User approved without correction on 2025-05-01, 2025-05-03
- No contradicting evidence in past 30 days

## Counter-evidence
- None

## Related Instincts
- read-before-write (0.82)
- verify-before-apply (0.60)
```

**字段说明**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | kebab-case 唯一标识 |
| `trigger` | string | 自然语言触发条件 |
| `confidence` | float | 0.3~0.9，初始 0.5 |
| `domain` | string | `code-style`, `testing`, `git`, `debugging`, `workflow`, `security` |
| `scope` | enum | `project` / `global` |
| `project_id` | string\|null | project scope 时必填 |
| `source` | string | `session-observation`, `user-explicit`, `imported` |
| `observation_count` | int | 支撑该 instinct 的观察次数 |

**置信度演化规则**：

| 事件 | 变化 |
|------|------|
| 新增观察支撑 | +0.05（上限 0.9） |
| 用户明确纠正（如"不对，应该先..."） | -0.2（下限 0.3） |
| 30 天无相关观察 | -0.05 |
| 出现矛盾证据 | -0.15 |
| 用户显式确认（"对的，以后都这么做"） | +0.1 |

### 5.3 Evolved Skill（进化后的技能）

当 Instinct 聚类后，生成符合 Kimi CLI 规范的 Skill：

```markdown
---
name: grep-before-edit
description: Always search before editing files to avoid blind replacements.
---

# Grep Before Edit

## When to Use
When asked to modify existing code files.

## Pattern
1. Use Grep to locate the exact lines and context.
2. Verify findings with Read if ambiguous.
3. Then apply Edit or WriteFile.

## Why
Prevents accidental over-replacement and validates scope before mutation.

## Evidence
Extracted from 15 observations across 3 projects. Confidence: 0.82.
Source instincts: grep-before-edit (0.75), locate-then-edit (0.70).
```

---

## 6. 目录与文件结构

```
~/.kimi/
├── learning/                          # 本系统主目录
│   ├── config.toml                    # 学习系统配置
│   ├── observations.jsonl             # Global fallback 观察
│   ├── projects.json                  # 项目注册表
│   ├── disabled                       # 存在时禁用所有 Hook
│   │
│   ├── hooks/
│   │   └── observe.sh                 # 核心 Hook 脚本
│   │
│   ├── scripts/
│   │   ├── instinct-cli.py            # Instinct 管理 CLI
│   │   ├── detect-project.sh          # 项目检测辅助
│   │   └── test_parse_instinct.py     # 测试
│   │
│   ├── agents/
│   │   ├── start-observer.sh          # Observer 启动器
│   │   └── observer-loop.sh           # Observer 主循环
│   │
│   ├── projects/                      # 项目级数据
│   │   └── <workdir_hash>/            # 复用 Kimi CLI hash
│   │       ├── project.json           # 项目元数据镜像
│   │       ├── observations.jsonl
│   │       ├── observations.archive/  # 自动归档
│   │       └── instincts/
│   │           ├── personal/          # 项目级自动学习
│   │           │   └── grep-before-edit.yaml
│   │           └── inherited/         # 项目级导入
│   │
│   └── instincts/                     # Global 数据
│       ├── personal/                  # Global 自动学习
│       ├── inherited/                 # Global 导入
│       └── evolved/
│           ├── skills/                # 生成的 SKILL.md
│           │   └── grep-before-edit/
│           │       └── SKILL.md
│           ├── commands/              # 未来扩展
│           └── agents/                # 未来扩展
│
├── skills/
│   └── learned/                       # 软链或实际输出到 Kimi Skill 路径
│       └── (由 evolved/skills/ 同步)
│
└── sessions/                            # Kimi CLI 原生
    └── <workdir_hash>/
        └── <session_id>/
            ├── context.jsonl
            ├── wire.jsonl
            └── ...
```

---

## 7. 核心组件详细设计

### 7.1 `observe.sh`（Hook 脚本）

**输入**：Kimi CLI 通过 stdin 传入的 JSON（PreToolUse / PostToolUse / SessionEnd 格式）。

**关键处理流程**：

```bash
1. 读取 stdin JSON
2. 提取 cwd → 项目检测 → 确定 PROJECT_ID / PROJECT_NAME
3. 自动化守卫检查（5 层过滤）
4. 解析工具信息（tool_name, input, output, session_id）
5. 数据脱敏（正则替换 api_key, token, password 等）
6. 追加到 observations.jsonl（项目级优先，fallback 到 global）
7. 文件大小检查（>10MB 自动归档）
8. 懒启动 Observer（信号节流，每 20 条触发一次 SIGUSR1）
```

**脱敏正则**（与 ECC v2 一致）：

```python
_SECRET_RE = re.compile(
    r"(?i)(api[_-]?key|token|secret|password|authorization|credentials?|auth)"
    r"([\"'\s:=]+)"
    r"([A-Za-z]+\s+)?"
    r"([A-Za-z0-9_\-/.+=]{8,})"
)
```

**与 Kimi CLI Hook JSON 的字段映射**：

| Kimi CLI 字段 | observe.sh 内部 | 说明 |
|---------------|----------------|------|
| `tool_name` | `tool` | 工具名称 |
| `tool_input` | `input` | 工具输入参数 |
| `tool_output` | `output` | 工具输出（PostToolUse） |
| `tool_call_id` | `tool_use_id` | 唯一标识，用于 Pre/Post 配对 |
| `session_id` | `session` | 会话标识 |
| `cwd` | `cwd` | 当前工作目录 |

### 7.2 `instinct-cli.py`（管理 CLI）

```bash
# 查询
python3 instinct-cli.py status                    # 列出所有 instincts（按 scope 分组）
python3 instinct-cli.py status --project-only     # 只看当前 project
python3 instinct-cli.py status --global-only      # 只看 global
python3 instinct-cli.py show <id>                 # 显示单个 instinct 详情

# 进化
python3 instinct-cli.py evolve                    # 聚类 instincts 为 skills
python3 instinct-cli.py evolve --dry-run          # 预览，不写入
python3 instinct-cli.py evolve --project <hash>   # 只进化指定项目

# 晋升
python3 instinct-cli.py promote <id>              # Project → Global
python3 instinct-cli.py promote --auto            # 自动晋升所有符合条件的
python3 instinct-cli.py promote --dry-run         # 预览晋升候选

# 导入/导出
python3 instinct-cli.py export --output instincts-backup.yaml
python3 instinct-cli.py export --scope global --domain workflow
python3 instinct-cli.py import instincts-backup.yaml

# 维护
python3 instinct-cli.py purge --days 30           # 删除 30 天前的 observations
python3 instinct-cli.py decay                     # 执行置信度衰减计算
python3 instinct-cli.py delete <id>               # 删除 instinct
```

### 7.3 `start-observer.sh` + `observer-loop.sh`（后台分析）

**启动流程**：

```bash
1. 检查 PID 文件，防止重复启动
2. 使用 flock/lockfile/mkdir 获取原子锁
3. 读取 config.toml 获取 observer 配置
4. 进入主循环：
   a. 等待 SIGUSR1（来自 observe.sh 的信号）或定时唤醒
   b. 读取 observations.jsonl 新条目
   c. 过滤已处理条目（通过 offset 或 checksum）
   d. 调用 LLM API 进行模式检测
   e. 创建/更新 Instinct YAML
   f. 检查晋升候选
   g. 休眠（可配置间隔，默认 5 分钟）
```

**分析提示词模板**（发送给 LLM）：

```
你是一个模式提取专家。请分析以下 observations，提取可复用的行为模式。

Observations:
{observations_jsonl}

要求：
1. 只提取用户反复使用或明确偏好的模式
2. 忽略一次性的错误修复
3. 区分 project-specific 和 universal 模式
4. 输出 YAML 格式的 Instinct 列表
5. 每个 instinct 必须包含 id, trigger, action, confidence, domain, scope, evidence
```

### 7.4 `config.toml`（学习系统配置）

```toml
[learning]
version = "2.0"

[learning.observer]
enabled = false                # 默认关闭，用户手动开启
run_interval_minutes = 5
min_observations_to_analyze = 20
model = "kimi-mini"            # 分析用模型，可配置轻量模型

[learning.observation]
max_file_size_mb = 10
archive_after_days = 30
secret_scrubbing = true

[learning.instinct]
default_confidence = 0.5
confidence_decay_days = 30
auto_promote_threshold = 0.8
auto_promote_min_projects = 2

[learning.evolution]
min_confidence_for_skill = 0.7
output_dir = "~/.kimi/skills/learned"
sync_to_learned = true         # 是否自动同步 evolved/skills → ~/.kimi/skills/learned/
```

---

## 8. 与 Kimi CLI 的无缝集成

### 8.1 一键安装

```bash
# install.sh
#!/bin/bash
set -e

LEARNING_DIR="${HOME}/.kimi/learning"
SKILLS_DIR="${HOME}/.kimi/skills/learned"

mkdir -p "${LEARNING_DIR}"/{
    hooks,scripts,agents,
    instincts/{personal,inherited,evolved/{skills,commands,agents}},
    projects
}
mkdir -p "${SKILLS_DIR}"

# 复制脚本
cp observe.sh "${LEARNING_DIR}/hooks/"
cp instinct-cli.py "${LEARNING_DIR}/scripts/"
cp start-observer.sh observer-loop.sh "${LEARNING_DIR}/agents/"

# 创建默认配置（如果不存在）
if [ ! -f "${LEARNING_DIR}/config.toml" ]; then
    cp config.default.toml "${LEARNING_DIR}/config.toml"
fi

# 注册 Hooks 到 ~/.kimi/config.toml
if ! grep -q "kimi/learning/hooks/observe.sh" "${HOME}/.kimi/config.toml"; then
    cat >> "${HOME}/.kimi/config.toml" << 'HOOKS'

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
HOOKS
fi

echo "Kimi Continuous Learning installed to ${LEARNING_DIR}"
echo "Hooks registered in ~/.kimi/config.toml"
echo "Run 'python3 ${LEARNING_DIR}/scripts/instinct-cli.py status' to check status"
```

### 8.2 自动同步机制

`evolved/skills/` 与 `~/.kimi/skills/learned/` 的同步策略：

| 策略 | 方式 | 适用场景 |
|------|------|----------|
| **软链** | `ln -s ~/.kimi/learning/instincts/evolved/skills ~/.kimi/skills/learned` | 简单，推荐 |
| **硬拷贝** | `instinct-cli.py evolve` 时自动复制 | 需要版本控制时 |
| **Git 子模块** | `~/.kimi/skills/learned` 作为独立 git 仓库 | 团队共享 learned skills |

### 8.3 与 Kimi CLI 工作流的融合

```
用户启动 kimi → 进入项目目录
    │
    ▼
Kimi CLI 自动加载 skills（包括 learned/）
    │
    ▼
用户与 kimi 交互 → 工具调用触发 Pre/PostToolUse Hook
    │
    ▼
observe.sh 记录 observations（用户无感知）
    │
    ▼
SessionEnd 触发 Observer 分析（后台异步）
    │
    ▼
新 Instinct 生成 / 已有 Instinct 置信度更新
    │
    ▼
用户下次进入该项目 → 相关 Instinct 已通过 Skill 注入 system prompt
```

### 8.4 快速查看命令建议

```bash
# 在 ~/.kimi/config.toml 中可配置 alias 或推荐用户添加到 shell rc
alias kl-status='python3 ~/.kimi/learning/scripts/instinct-cli.py status'
alias kl-evolve='python3 ~/.kimi/learning/scripts/instinct-cli.py evolve'
alias kl-promote='python3 ~/.kimi/learning/scripts/instinct-cli.py promote --auto'
```

---

## 9. 隐私与安全

### 9.1 数据本地性

| 数据 | 存储位置 | 是否可导出 |
|------|----------|-----------|
| 原始 observations | `~/.kimi/learning/` 本地 | 否（默认不导出） |
| Instincts | `~/.kimi/learning/` 本地 | 是（仅导出模式） |
| 生成的 Skills | `~/.kimi/skills/learned/` 本地 | 是 |
| 分析用的 LLM API 调用 | 可选本地模型 | 可控 |

### 9.2 脱敏机制

```python
# observe.sh 内置的脱敏逻辑
_SECRET_RE = re.compile(
    r"(?i)(api[_-]?key|token|secret|password|authorization|credentials?|auth)"
    r"([\"'\s:=]+)"
    r"([A-Za-z]+\s+)?"
    r"([A-Za-z0-9_\-/.+=]{8,})"
)

def scrub(val):
    if val is None:
        return None
    return _SECRET_RE.sub(
        lambda m: m.group(1) + m.group(2) + (m.group(3) or "") + "[REDACTED]",
        str(val)
    )
```

### 9.3 用户控制

| 控制手段 | 效果 |
|----------|------|
| `touch ~/.kimi/learning/disabled` | 完全禁用所有 Hook，零开销 |
| `ECC_SKIP_OBSERVE=1 kimi` | 单次会话跳过观察 |
| `instinct-cli.py delete <id>` | 删除指定 instinct |
| 编辑 `~/.kimi/learning/config.toml` | 调整阈值、关闭 observer |
| 审查 `~/.kimi/skills/learned/` | 手动编辑或删除生成的 skills |

---

## 10. MVP Roadmap

### Phase 1：观察 + 简单提取（Week 1-2）

- [ ] `observe.sh`：Pre/PostToolUse Hook 实现
- [ ] 项目检测（git remote / cwd hash）
- [ ] 数据脱敏
- [ ] `SessionEnd` Hook：读取 `context.jsonl`，调用 LLM 提取 Skill
- [ ] 输出到 `~/.kimi/skills/learned/<name>/SKILL.md`
- [ ] 安装脚本 `install.sh`

**目标**：每次会话结束后，自动提炼 0~1 个 Skill。

### Phase 2：Instinct 原子化（Week 3-4）

- [ ] Instinct YAML 数据模型
- [ ] 项目隔离目录结构
- [ ] 置信度评分（初始 0.5，自动调整）
- [ ] `instinct-cli.py status`
- [ ] `instinct-cli.py delete`
- [ ] `instinct-cli.py export`

**目标**：从粗粒度的 Skill 提取，进化为细粒度的 Instinct 管理。

### Phase 3：后台 Observer（Week 5-6）

- [ ] `start-observer.sh` + `observer-loop.sh`
- [ ] 文件锁防止多实例
- [ ] 信号节流（SIGUSR1）
- [ ] 自动归档（>10MB / >30 天）
- [ ] `config.toml` 配置系统

**目标**：分析异步化，主会话零感知。

### Phase 4：进化与晋升（Week 7-8）

- [ ] `instinct-cli.py evolve`（聚类）
- [ ] `instinct-cli.py promote`（Project → Global）
- [ ] 自动晋升规则
- [ ] 置信度衰减
- [ ] 冲突检测（矛盾 instinct 标记）

**目标**：形成 Instinct → Skill 的完整进化链路。

### Phase 5：深度集成（未来）

- [ ] 利用 Kimi CLI `BackgroundTaskManager` 启动 Observer Agent
- [ ] `Notification` Hook 推送学习成果通知
- [ ] 团队共享（导出/导入 instinct 包）
- [ ] Web UI 查看 instinct 图谱

---

## 11. 附录：与 ECC v2 的差异对照

| 维度 | ECC v2 (Claude Code) | 本方案 (Kimi Code CLI) |
|------|----------------------|------------------------|
| **Hook 配置** | `~/.claude/settings.json` | `~/.kimi/config.toml` |
| **Hook 超时** | 默认 30s（与 Kimi 相同） | 默认 30s |
| **Skill 目录** | `~/.claude/skills/learned/` | `~/.kimi/skills/learned/` |
| **Skill 优先级** | Project > User > Extra > Built-in | 相同（Kimi CLI 原生） |
| **后台 Agent** | 外部 shell 启动 Haiku Agent | 独立 Python 进程 / 可选 Kimi Agent 任务 |
| **项目检测** | git remote SHA256 hash | 复用 Kimi CLI work_dir hash + git remote hash |
| **会话存储** | `transcript.json` | `context.jsonl` + `wire.jsonl` |
| **审批系统** | Claude Code 原生 approval | Kimi CLI 原生 ApprovalRuntime |
| **子 Agent 识别** | `agent_id` 字段 | 相同（stdin JSON 包含） |
| **安装方式** | 手动配置 settings.json | `install.sh` 自动追加 hooks 到 config.toml |
| **观察触发** | PreToolUse + PostToolUse | 相同 |
| **数据格式** | observations.jsonl | 相同（兼容格式，可互导） |
| **Instinct 格式** | YAML frontmatter + body | 相同 |
| **晋升规则** | 2+ 项目 + confidence ≥ 0.8 | 相同 |

---

## 参考

- [ECC continuous-learning-v2 SKILL.md](/skills/continuous-learning-v2/SKILL.md)
- [ECC observe.sh](/skills/continuous-learning-v2/hooks/observe.sh)
- [Kimi CLI Hooks 文档](https://moonshotai.github.io/kimi-cli/en/customization/mcp.md)
- [Kimi CLI Skills 文档](https://moonshotai.github.io/kimi-cli/en/customization/skills.md)
