# Continuous Learning v2 学习笔记

> 版本：v2.1.0 | 来源：ECC 内置 Skill
> 核心思想：通过 Hook 采集会话数据 → 后台分析模式 → 生成原子化的"直觉"(Instinct) → 聚合成技能/命令/代理

---

## 一、概述

Continuous Learning v2 是一个**基于直觉的学习系统**，可以自动从 Claude Code 会话中提取可复用的知识。

**v1 的局限**：
- 依赖 skill 来观察会话，而 skill 是概率触发的（约 50-80%），经常遗漏
- 只能生成完整的 skill，粒度太粗
- 没有置信度评分

**v2 的改进**：
- 使用 Hook 替代 Skill 来观察，**100% 可靠**
- 后台使用 Haiku 模型分析，不占用主会话
- 生成原子化的"直觉"（Instinct），粒度更细
- 引入置信度评分（0.3-0.9）
- 直觉可以聚合成 skill/command/agent

**v2.1 新增项目级作用域**：
- React 项目的模式只保留在 React 项目中
- Python 项目的约定只保留在 Python 项目中
- 跨项目通用的模式（如"总是验证输入"）才提升为全局

---

## 二、核心概念：Instinct（直觉）

### 什么是 Instinct

Instinct 是一个微小的学习到的行为，格式如下：

```yaml
---
id: prefer-functional-style
trigger: "when writing new functions"
confidence: 0.7
domain: "code-style"
source: "session-observation"
scope: project
project_id: "a1b2c3d4e5f6"
project_name: "my-react-app"
---

# Prefer Functional Style

## Action
Use functional patterns over classes when appropriate.

## Evidence
- Observed 5 instances of functional pattern preference
- User corrected class-based approach to functional on 2025-01-15
```

### 关键属性

| 属性 | 说明 |
|------|------|
| **Atomic** | 一个触发器对应一个动作 |
| **Confidence-weighted** | 0.3=试探性，0.9=近乎确定 |
| **Domain-tagged** | 按领域标记：code-style, testing, git, debugging, workflow |
| **Evidence-backed** | 追踪创建它的观察证据 |
| **Scope-aware** | project（项目级）或 global（全局） |

### 置信度评分体系

| 分数 | 含义 | 行为 |
|------|------|------|
| 0.3 | 试探性 | 被建议但不强制 |
| 0.5 | 中等 | 在相关时应用 |
| 0.7 | 强 | 自动批准应用 |
| 0.9 | 近乎确定 | 核心行为 |

**置信度增加**：
- 模式被重复观察到
- 用户没有纠正建议的行为
- 来自其他来源的类似直觉一致

**置信度降低**：
- 用户明确纠正了该行为
- 长时间未观察到该模式
- 出现矛盾的证据

---

## 三、系统架构

### 整体流程

```
会话活动 (在 git 仓库中)
      |
      | Hook 捕获 prompt + tool use（100% 可靠）
      | + 检测项目上下文（git remote / 仓库路径）
      v
+---------------------------------------------+
|  projects/<project-hash>/observations.jsonl  |
|   (prompt, tool 调用, 结果, 项目信息)         |
+---------------------------------------------+
      |
      | Observer agent 读取（后台，Haiku 模型）
      v
+---------------------------------------------+
|          模式检测                            |
|   * 用户纠正 → 生成 instinct                |
|   * 错误解决 → 生成 instinct                |
|   * 重复工作流 → 生成 instinct              |
|   * 范围决策：project 还是 global？         |
+---------------------------------------------+
      |
      | 创建/更新
      v
+---------------------------------------------+
|  projects/<project-hash>/instincts/personal/ |
|   * prefer-functional.yaml (0.7) [project]  |
|   * use-react-hooks.yaml (0.9) [project]    |
+---------------------------------------------+
|  instincts/personal/  (全局)                 |
|   * always-validate-input.yaml (0.85)[global]|
+---------------------------------------------+
      |
      | /evolve 聚类 + /promote
      v
+---------------------------------------------+
|  evolved/ (project 或 global)               |
|   * commands/new-feature.md                 |
|   * skills/testing-workflow.md              |
|   * agents/refactor-specialist.md           |
+---------------------------------------------+
```

### 组件构成

| 文件 | 作用 |
|------|------|
| `hooks/observe.sh` | **观察 Hook** — 在 PreToolUse 和 PostToolUse 时触发，采集工具调用数据 |
| `scripts/detect-project.sh` | **项目检测** — 检测当前所在 git 项目，计算项目 hash |
| `scripts/instinct-cli.py` | **CLI 工具** — 管理 instinct 的命令行入口 |
| `agents/observer.md` | **Observer Agent 定义** — 后台分析 agent，使用 Haiku 模型 |
| `agents/observer-loop.sh` | **Observer 循环** — 后台分析的主循环逻辑 |
| `agents/start-observer.sh` | **Observer 启动器** — 启动/停止/查看后台分析进程 |
| `agents/session-guardian.sh` | **会话守卫** — 三重门控：时段限制 + 冷却 + 空闲检测 |
| `config.json` | 配置文件 |

---

## 四、项目检测机制

系统自动检测当前项目，优先级如下：

1. **`CLAUDE_PROJECT_DIR` 环境变量**（最高优先级）
2. **`git remote get-url origin`** — 哈希化生成可移植的项目 ID
3. **`git rev-parse --show-toplevel`** — 回退方案（机器相关）
4. **Global 回退** — 如果都没检测到，放入全局作用域

每个项目通过 git remote URL 算出 12 字符的 hash ID（例如 `a1b2c3d4e5f6`），保证了**同一项目在不同机器上 hash 一致**。

### 作用域决策指南

| 模式类型 | 作用域 | 示例 |
|---------|-------|------|
| 语言/框架约定 | **project** | "使用 React hooks", "遵循 Django REST 模式" |
| 文件结构偏好 | **project** | "测试放在 `__tests__/`", "组件在 src/components/" |
| 代码风格 | **project** | "使用函数式风格", "优先使用 dataclasses" |
| 错误处理策略 | **project** | "使用 Result 类型处理错误" |
| 安全实践 | **global** | "验证用户输入", "转义 SQL" |
| 通用最佳实践 | **global** | "先写测试", "总是处理错误" |
| 工具工作流偏好 | **global** | "先 Grep 后 Edit", "先 Read 后 Write" |
| Git 实践 | **global** | "约定式提交", "小而聚焦的 commit" |

---

## 五、观察 Hook 详解 (observe.sh)

`hooks/observe.sh` 是整个系统的数据采集层，有几个关键设计：

### 5.1 多层级会话过滤

防止 observer 观察自身或其他自动化会话，形成"自循环"：

| 层级 | 检查项 | 说明 |
|------|--------|------|
| Layer 1 | Entrypoint | 仅允许 `cli`, `sdk-ts`, `claude-desktop` |
| Layer 2 | Hook profile | `ECC_HOOK_PROFILE=minimal` 时跳过 |
| Layer 3 | 环境变量 | `ECC_SKIP_OBSERVE=1` 时跳过 |
| Layer 4 | Agent ID | 子 agent 会话跳过 |
| Layer 5 | 路径排除 | 包含 `observer-sessions`, `.claude-mem` 的路径跳过 |

### 5.2 数据采集流程

1. 读取 stdin 的 JSON 数据
2. 解析获取 tool_name、tool_input、tool_output、session_id 等
3. **截断**大输入/输出到 5000 字符
4. **脱敏**密钥信息（api_key、token、secret、password 等用 [REDACTED] 替换）
5. 写入 `observations.jsonl`（每条一行 JSON）
6. 文件超过 10MB 自动归档到 `observations.archive/`
7. 自动清理 30 天前的归档文件

### 5.3 Observer 惰性启动

配置了 `observer.enabled: true` 时，observe.sh 会在检测到足够观察数据后自动启动后台 observer 进程，使用 `flock`（Linux）或 `mkdir` 原子操作（macOS）做竞态控制。

### 5.4 信号节流 (Issue #521)

每 20 次观察才向 observer 发送一次 SIGUSR1 信号，防止频繁触发导致并行分析爆炸。

---

## 六、Observer 后台分析 (observer-loop.sh)

### 6.1 触发方式

- **定时触发**：每 5 分钟（可配置）运行一次分析
- **信号触发**：observe.sh 每 N 次写入后发送 SIGUSR1 信号
- **冷却机制**：两次分析之间至少间隔 60 秒

### 6.2 分析执行

1. 取 `observations.jsonl` 末尾 500 行（采样分析，防止内存爆炸）
2. 通过 `claude --model haiku --max-turns 20 --print` 调用 Haiku 模型
3. Haiku 读取观察数据，使用 Write 工具直接写入 instinct 文件
4. 分析超时 120 秒后自动终止 watchdag
5. 分析完成后将 `observations.jsonl` 归档清空

### 6.3 模式检测类型

Observer 从观察中寻找四类模式：

1. **用户纠正** — 用户的后续消息纠正了 Claude 的先前操作 → "做 X 时，优先用 Y"
2. **错误解决** — 错误出现后被修复 → "遇到错误 X 时，尝试 Y"
3. **重复工作流** — 相同工具序列反复出现 → "做 X 时，按步骤 Y、Z、W"
4. **工具偏好** — 某些工具被一致优先使用 → "需要 X 时，使用工具 Y"

---

## 七、会话守卫 (session-guardian.sh)

三重门控机制，防止 observer 在不合适的时候运行：

### Gate 1: 时间段限制
- 默认仅在 8:00-23:00 运行
- 支持跨夜时间段（如 22:00-6:00）
- 可通过 `OBSERVER_ACTIVE_HOURS_START/END` 配置

### Gate 2: 项目冷却
- 同一项目冷却期默认为 300 秒
- 使用 `mkdir` 原子锁防止并发
- 日志文件跟踪每个项目的上次分析时间

### Gate 3: 空闲检测
- 检测用户无操作时间
- 超过 30 分钟空闲时跳过
- macOS 通过 `ioreg` 获取空闲时间
- Linux 通过 `xprintidle`（如果安装）
- Windows 通过 PowerShell 调用 `GetLastInputInfo`
- 不支持时失败开放（fail open）

---

## 八、CLI 工具 (instinct-cli.py)

### 支持的命令

| 命令 | 说明 | 新增于 |
|------|------|--------|
| `/instinct-status` | 显示所有 instinct（项目级 + 全局）及其置信度 | v2.0 |
| `/evolve` | 聚类相关 instinct 生成 skills/commands/agents | v2.0 |
| `/instinct-export` | 导出 instincts（可按作用域/领域过滤） | v2.0 |
| `/instinct-import` | 导入 instincts | v2.0 |
| `/promote` | 将项目级 instinct 提升为全局 | v2.1 |
| `/projects` | 列出所有已知项目及其 instinct 数量 | v2.1 |
| `prune` | 删除超过 TTL（30 天）的待定 instinct | — |

### Evolve 聚类逻辑

1. 按领域（domain）分组
2. 高置信度（>=0.8）的 instinct 作为 skill 候选
3. 标准化 trigger 关键词后找相似集群（2+ 个相似 trigger 聚类）
4. workflow 领域 + >=0.7 置信度的作为 command 候选
5. 3+ 个 instinct + >=0.75 置信度的集群作为 agent 候选

### Promote 逻辑（v2.1）

- **自动晋升条件**：同一 instinct ID 出现在 2+ 项目中，平均置信度 >= 0.8
- 可通过 `instinct-cli.py promote <id>` 手动晋升
- `--dry-run` 预览不执行
- 支持从 `Skill Creator`（仓库分析）导入的 instinct

---

## 九、文件存储结构

```
~/.claude/homunculus/
├── identity.json               # 用户画像、技术等级
├── projects.json               # 注册表：project hash → 名称/路径/remote
├── observations.jsonl           # 全局观察数据（回退）
├── instincts/
│   ├── personal/               # 全局自动学习的 instinct
│   └── inherited/              # 全局导入的 instinct
├── evolved/
│   ├── agents/                 # 全局生成的 agent
│   ├── skills/                 # 全局生成的 skill
│   └── commands/               # 全局生成的 command
└── projects/
    ├── a1b2c3d4e5f6/           # 项目 hash（来自 git remote URL）
    │   ├── project.json        # 项目元数据
    │   ├── observations.jsonl   # 项目级观察数据
    │   ├── observations.archive/
    │   ├── instincts/
    │   │   ├── personal/       # 项目特定自动学习
    │   │   └── inherited/      # 项目特定导入
    │   └── evolved/
    │       ├── skills/
    │       ├── commands/
    │       └── agents/
    └── f6e5d4c3b2a1/           # 另一个项目
```

---

## 十、与 v1 的对比总结

| 特性 | v1 | v2 |
|------|----|----|
| 观察方式 | Skill（概率触发 ~50-80%） | Hook（100% 可靠） |
| 分析位置 | 主会话上下文 | 后台 Haiku agent |
| 粒度 | 完整 skill | 原子化 instinct |
| 置信度 | 无 | 0.3-0.9 加权 |
| 演变路径 | 直接生成 skill | Instinct → 聚类 → skill/command/agent |
| 共享 | 无 | 导出/导入 |
| 作用域（v2.1） | 全部全局 | 项目级 + 全局，可晋升 |

---

## 十一、安全与隐私

- 所有观察数据**存储在本地**，不上传
- 项目级 instinct 隔离，不同项目互不干扰
- 只能导出 instinct（模式），不能导出原始观察数据
- 不包含实际代码或对话内容
- 脱敏处理：API key、token、secret 等敏感信息自动替换为 `[REDACTED]`
- 用户完全控制导出和晋升的内容

---

## 十二、配置

```json
{
  "version": "2.1",
  "observer": {
    "enabled": false,
    "run_interval_minutes": 5,
    "min_observations_to_analyze": 20
  }
}
```

| 键 | 默认值 | 说明 |
|-----|---------|------|
| `observer.enabled` | `false` | 启用后台 observer agent |
| `observer.run_interval_minutes` | `5` | 分析间隔（分钟） |
| `observer.min_observations_to_analyze` | `20` | 触发分析的最小观察数 |

环境变量：
- `ECC_SKIP_OBSERVE=1` — 跳过观察（自动化会话使用）
- `ECC_HOOK_PROFILE=minimal` — 禁止非核心 hook
- `ECC_OBSERVER_SIGNAL_EVERY_N=20` — 信号节流
- `ECC_OBSERVER_TIMEOUT_SECONDS=120` — 分析超时
- `ECC_OBSERVER_MAX_ANALYSIS_LINES=500` — 最大分析行数
- `ECC_OBSERVER_ANALYSIS_COOLDOWN=60` — 分析冷却秒数
- `ECC_OBSERVER_IDLE_TIMEOUT_SECONDS=1800` — 空闲超时
- `OBSERVER_ACTIVE_HOURS_START=800` — 活跃时段开始
- `OBSERVER_ACTIVE_HOURS_END=2300` — 活跃时段结束
- `CLV2_PYTHON_CMD` — 指定 Python 命令路径
- `CLV2_CONFIG` — 指定配置文件路径

---

## 十三、关键设计决策总结

1. **为什么用 Hook 而不用 Skill？** — Hook 确定性 100% 触发，Skill 只有 50-80%
2. **为什么用 Haiku 模型？** — 成本效益，分析任务不需要强推理
3. **为什么用原子化 Instinct？** — 粒度更细，可以灵活组合，比整块 skill 更易管理
4. **为什么引入项目作用域？** — 避免跨项目污染，React 模式不该影响 Python 项目
5. **为什么用 git remote URL 哈希？** — 同一项目在不同机器上有相同 ID，便于迁移
6. **为什么用 tail 采样 500 行？** — 防止观察文件过大导致 LLM 调用负载爆炸
7. **为什么需要冷却机制？** — 防止工具调用频繁时触发大量并行分析
