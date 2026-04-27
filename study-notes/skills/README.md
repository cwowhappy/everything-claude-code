# Skills 学习笔记

本笔记整理了 everything-claude-code 项目中的所有 Skills（技能），按类别归类以便查阅。

> 总计 183 个 Skills（截至 2026-04-27）
> 每个 skill 是一个目录，内含 `SKILL.md` 文件，格式为 Markdown + YAML frontmatter

---

## 📁 目录

- [一、工作流与开发方法论](#一工作流与开发方法论)
- [二、AI / Agent 开发](#二ai--agent-开发)
- [三、ECC 自身工具](#三ecc-自身工具)
- [四、前端开发](#四前端开发)
- [五、后端开发](#五后端开发)
- [六、语言 / 框架专项](#六语言--框架专项)
- [七、测试](#七测试)
- [八、安全](#八安全)
- [九、DevOps 与部署](#九devops-与部署)
- [十、数据库](#十数据库)
- [十一、内容创作与媒体](#十一内容创作与媒体)
- [十二、商业与运营](#十二商业与运营)
- [十三、知识管理与研究](#十三知识管理与研究)
- [十四、设计系统与 UI](#十四设计系统与-ui)
- [十五、其他 / 跨领域](#十五其他--跨领域)

---

## 一、工作流与开发方法论

涵盖项目开发全流程的方法论和最佳实践。

| Skill | 说明 |
|-------|------|
| **tdd-workflow** | 测试驱动开发工作流，要求 80%+ 覆盖率（单元、集成、E2E） |
| **coding-standards** | 跨项目通用编码规范：命名、可读性、不可变性 |
| **agentic-engineering** | 以 eval 驱动、分解任务、成本感知模型路由的工程模式 |
| **ai-first-engineering** | AI 生成大量代码时的团队工程运营模式 |
| **design-system** | 设计系统生成与审计，检查视觉一致性 |
| **product-lens** | 在开始写代码前验证"为什么做"，进行产品诊断 |
| **product-capability** | 将 PRD 需求转化为可落地的能力规划，暴露约束和未决决策 |
| **codebase-onboarding** | 分析陌生代码库并生成结构化入门指南，含架构图和 CLAUDE.md |
| **code-tour** | 创建 CodeTour walkthrough，分角色引导代码浏览 |
| **architecture-decision-records** | 记录架构决策为结构化 ADR，含上下文、备选方案和理由 |
| **verification-loop** | 全面的验证系统，确保代码质量 |
| **santa-method** | 多智能体对抗验证，两个独立审查 agent 都通过才能发布 |
| **council** | 召集四角色委员会处理模糊决策、权衡分析和 go/no-go 判断 |
| **strategic-compact** | 在任务阶段之间建议手动压缩上下文，避免任意自动压缩 |
| **benchmark** | 测量性能基线，检测回归，比较技术栈方案 |
| **eval-harness** | Claude Code 会话的正式评估框架，实现 eval 驱动开发 |

---

## 二、AI / Agent 开发

针对 AI 应用和 Agent 开发的技能。

| Skill | 说明 |
|-------|------|
| **claude-api** | Anthropic Claude API 模式（Python/TS）：Messages、Streaming、Tool Use、Vision、Prompt Caching 等 |
| **claude-devfleet** | 多 agent 编码任务编排，在独立 worktree 中并行分发 agent |
| **agent-eval** | 编码 agent 横向对比（Claude Code vs Aider vs Codex 等），含通过率/成本/时间/一致性 |
| **agent-harness-construction** | AI agent 动作空间、工具定义和观察格式的设计与优化 |
| **agent-introspection-debugging** | AI agent 失败的结构化自调试工作流 |
| **agent-payment-x402** | 为 AI agent 添加 x402 支付能力（按任务预算、支出控制） |
| **agent-sort** | 为特定仓库裁剪 ECC 安装，排序技能到 DAILY vs LIBRARY 桶 |
| **autonomous-agent-harness** | 将 Claude Code 转为完全自主 agent（持久记忆、定时任务、桌面操控） |
| **autonomous-loops** | 自主 agent 循环的模式和架构，从简单流水线到 RFC 驱动的多 agent DAG |
| **continuous-agent-loop** | 持续自主 agent 循环，含质量门控、eval 和恢复控制 |
| **continuous-learning** | 自动从会话中提取可复用模式并保存为 learned skills |
| **continuous-learning-v2** | 基于"直觉"的学习系统，创建带置信度的原子直觉，可演化为 skills/commands/agents |
| **iterative-retrieval** | 渐进式上下文检索优化模式 |
| **llm-trading-agent-security** | 自主交易 agent 的安全模式（注入防护、消费限制、断路器） |
| **cost-aware-llm-pipeline** | LLM API 成本优化：按任务复杂度路由模型、预算跟踪、重试逻辑 |
| **context-budget** | 审计 Claude Code 上下文窗口消耗，识别膨胀组件并提供 token 节省建议 |
| **prompt-optimizer** | Prompt 优化工具 |
| **dmux-workflows** | 使用 dmux（tmux pane manager）多 agent 编排 |
| **ralphinho-rfc-pipeline** | RFC 驱动的多 agent DAG 执行模式 |
| **team-builder** | 交互式 agent 选择器，组合并分发并行团队 |
| **nanoclaw-repl** | NanoClaw v2 REPL，基于 `claude -p` 的零依赖会话感知 REPL |
| **gan-style-harness** | 生成器-评估器双 agent 对抗式构建框架（基于 Anthropic 2026 年 3 月论文） |
| **gateguard** | 事实核查门控，阻止 Edit/Write/Bash 并要求具体调查 |
| **search-first** | 先研究再编码：写代码前先搜索已有工具/库/模式 |
| **workspace-surface-audit** | 审计当前仓库/MCP/插件/连接器等，推荐最高价值的 ECC 技能 |

---

## 三、ECC 自身工具

管理和维护 ECC 项目自身的工具。

| Skill | 说明 |
|-------|------|
| **configure-ecc** | ECC 交互式安装器，选择并安装 skills/rules 到用户级或项目级 |
| **rules-distill** | 扫描 skills 提取跨领域原则并提炼为 rules 文件 |
| **skill-stocktake** | 审计 skills 和 commands 质量，支持快速扫描和全面盘点模式 |
| **skill-comply** | 可视化验证 skills/rules/agents 是否被实际遵守，生成 3 级严格度测试 |
| **automation-audit-ops** | 自动化清单和重叠审计，找出损坏/冗余/缺失的组件 |
| **hookify-rules** | 创建 hookify 规则，将 rules 转为 hooks 执行 |
| **ck** | 持久化每项目记忆：会话启动时自动加载项目上下文 |
| **repo-scan** | 跨技术栈源码审计，分类每个文件，生成交互式 HTML 报告 |
| **security-scan** | 扫描 Claude Code 配置（claude/）的安全漏洞和注入风险 |
| **ecc-tools-cost-audit** | ECC Tools 账单审计，调查 PR 创建失控、quota 绕过等问题 |
| **token-budget-advisor** | Token 预算建议 |
| **context-budget** | 上下文窗口消耗审计和优化建议 |
| **plankton-code-quality** | 写入时代码质量管控：自动格式化、lint、Claude 修复 |

---

## 四、前端开发

前端框架和模式。

| Skill | 说明 |
|-------|------|
| **frontend-patterns** | 前端开发模式：React、Next.js、状态管理、性能优化 |
| **frontend-design** | 高质量前端界面设计，视觉方向与代码同样重要 |
| **frontend-slides** | 创建动画丰富的 HTML 演示文稿（支持 PPT 转换） |
| **ui-demo** | 使用 Playwright 录制 UI 演示视频，生成 WebM |
| **nextjs-turbopack** | Next.js 16+ 与 Turbopack：增量打包、FS 缓存、开发速度 |
| **nuxt4-patterns** | Nuxt 4 应用模式：水合安全、性能、路由规则、SSR 数据获取 |
| **swiftui-patterns** | SwiftUI 架构模式、状态管理、视图组合、导航、性能优化 |
| **liquid-glass-design** | iOS 26 Liquid Glass 设计系统：动态玻璃材质 |
| **flutter-dart-code-review** | Flutter/Dart 代码审查清单 |
| **dart-flutter-patterns** | 生产级 Dart 和 Flutter 模式 |
| **compose-multiplatform-patterns** | Compose Multiplatform 和 Jetpack Compose 模式 |
| **remotion-video-creation** | Remotion 视频创建最佳实践（React 视频制作） |
| **browser-qa** | 浏览器自动化视觉测试和 UI 交互验证 |
| **e2e-testing** | Playwright E2E 测试（Page Object Model、CI/CD 集成） |
| **click-path-audit** | 追踪每个用户按钮的完整状态变更序列，发现函数间互斥的 Bug |
| **accessibility** | WCAG 2.2 Level AA 无障碍设计与审计 |

---

## 五、后端开发

后端架构和 API 设计模式。

| Skill | 说明 |
|-------|------|
| **api-design** | REST API 设计：资源命名、状态码、分页、过滤、错误响应、版本化 |
| **api-connector-builder** | 按现有集成模式精确构建新的 API 连接器 |
| **backend-patterns** | 后端架构模式：Node.js、Express、Next.js API 路由 |
| **hexagonal-architecture** | 端口适配器架构设计，含领域边界、依赖反转 |
| **mcp-server-patterns** | 构建 MCP 服务器（Node/TypeScript SDK）：tools、resources、prompts |
| **nestjs-patterns** | NestJS 架构模式：模块、控制器、Provider、DTO 验证、守卫 |
| **database-migrations** | 数据库迁移最佳实践：模式变更、回滚、零停机部署 |
| **deployment-patterns** | 部署工作流、CI/CD 模式、Docker 化、健康检查、回滚策略 |

---

## 六、语言 / 框架专项

针对特定编程语言和框架的编码规范、模式和测试。

| 语言/框架 | Skills |
|-----------|--------|
| **Python** | python-patterns, python-testing, pytorch-patterns, django-patterns, django-security, django-tdd, django-verification |
| **TypeScript/Node.js** | nestjs-patterns, nodejs-keccak256 |
| **Go** | golang-patterns, golang-testing |
| **Rust** | rust-patterns, rust-testing |
| **Java/Kotlin** | java-coding-standards, springboot-patterns, springboot-security, springboot-tdd, springboot-verification, jpa-patterns, kotlin-patterns, kotlin-testing, kotlin-coroutines-flows, kotlin-exposed-patterns, kotlin-ktor-patterns, android-clean-architecture |
| **C#/.NET** | dotnet-patterns, csharp-testing |
| **C++** | cpp-coding-standards, cpp-testing |
| **PHP/Laravel** | laravel-patterns, laravel-security, laravel-tdd, laravel-verification, laravel-plugin-discovery |
| **Swift/iOS** | swiftui-patterns, swift-concurrency-6-2, swift-actor-persistence, swift-protocol-di-testing, foundation-models-on-device |
| **Perl** | perl-patterns, perl-security, perl-testing |
| **Dart/Flutter** | dart-flutter-patterns, flutter-dart-code-review, compose-multiplatform-patterns |
| **Bun** | bun-runtime |

---

## 七、测试

涵盖各语言测试模式和通用测试策略。

| Skill | 说明 |
|-------|------|
| **tdd-workflow** | TDD 工作流，80%+ 覆盖率 |
| **e2e-testing** | Playwright E2E 测试 |
| **ai-regression-testing** | AI 辅助开发的回归测试策略 |
| **verification-loop** | 全面验证系统 |
| **browser-qa** | 浏览器自动化视觉测试 |
| **canary-watch** | 部署后监控 URL 回归 |
| **eval-harness** | Claude Code 会话评估框架 |
| **agent-eval** | 编码 agent 横向对比评估 |
| **skill-comply** | 验证 skills/rules 是否被遵守 |
| **benchmark** | 性能基线测量 |
| **santa-method** | 双 agent 对抗验证 |

各语言测试 skills：python-testing, golang-testing, rust-testing, kotlin-testing, cpp-testing, csharp-testing, perl-testing, django-tdd, laravel-tdd, springboot-tdd

---

## 八、安全

安全审查、合规和防护。

| Skill | 说明 |
|-------|------|
| **security-review** | 安全审查 checklist（认证、输入处理、密钥管理、支付） |
| **security-scan** | 扫描 Claude Code 配置安全漏洞 |
| **security-bounty-hunter** | 挖掘可被利用的漏洞，侧重远程可达的赏金级问题 |
| **safety-guard** | 防止生产系统上的破坏性操作 |
| **llm-trading-agent-security** | 交易 agent 安全模式 |
| **defi-amm-security** | Solidity AMM 合约安全 checklist |
| **hipaa-compliance** | HIPAA 合规入口 |
| **healthcare-phi-compliance** | PHI/PII 合规模式 |
| **gateguard** | 事实核查门控 |

各框架安全：django-security, laravel-security, springboot-security, perl-security, healthcare-cdss-patterns

---

## 九、DevOps 与部署

CI/CD、容器化、监控。

| Skill | 说明 |
|-------|------|
| **deployment-patterns** | 部署工作流、CI/CD、Docker、健康检查、回滚 |
| **docker-patterns** | Docker 和 Docker Compose 模式 |
| **git-workflow** | Git 分支策略、commit 规范、merge vs rebase |
| **github-ops** | GitHub 仓库操作：Issue/PR 管理、CI/CD、Release |
| **canary-watch** | 部署后监控 URL 回归 |
| **dashboard-builder** | 构建监控仪表盘（Grafana、SigNoz） |
| **unified-notifications-ops** | 统一通知工作流（GitHub、Linear、桌面提醒） |

---

## 十、数据库

数据库相关模式。

| Skill | 说明 |
|-------|------|
| **database-migrations** | 数据库迁移最佳实践 |
| **postgres-patterns** | PostgreSQL 查询优化、Schema 设计、索引 |
| **clickhouse-io** | ClickHouse 查询优化和分析 |
| **jpa-patterns** | JPA/Hibernate 实体设计、关系映射、查询优化 |
| **kotlin-exposed-patterns** | JetBrains Exposed ORM 模式 |

---

## 十一、内容创作与媒体

文章、视频、图片等内容生产。

| Skill | 说明 |
|-------|------|
| **article-writing** | 撰写文章、指南、教程、新闻通讯等长文内容 |
| **content-engine** | 跨平台原生内容系统（X、LinkedIn、TikTok、YouTube） |
| **crosspost** | 多平台内容分发（X、LinkedIn、Threads、Bluesky） |
| **brand-voice** | 从真实内容构建写作风格档案 |
| **seo** | SEO 审计、规划和实施（技术 SEO、结构化数据、Core Web Vitals） |
| **manim-video** | 使用 Manim 制作技术解说动画 |
| **remotion-video-creation** | React 视频制作（Remotion） |
| **video-editing** | AI 辅助视频编辑（FFmpeg、Remotion、ElevenLabs、fal.ai） |
| **ui-demo** | Playwright 录制 UI 演示视频 |
| **videodb** | 视频/音频理解、检索和编辑 |
| **fal-ai-media** | 统一媒体生成（图片/视频/音频） |
| **nutrient-document-processing** | 文档处理（PDF、DOCX、OCR、提取、签名） |
| **visa-doc-translate** | 签证文档翻译为双语 PDF |
| **frontend-slides** | 创建 HTML 演示文稿 |

---

## 十二、商业与运营

市场营销、销售、投资者关系、运营。

| Skill | 说明 |
|-------|------|
| **investor-materials** | 创建 Pitch Deck、一页纸、投资者备忘录、财务模型 |
| **investor-outreach** | 起草投资者冷邮件、跟进、更新邮件 |
| **market-research** | 市场研究、竞争分析、投资者尽调 |
| **lead-intelligence** | AI 驱动的线索挖掘和触达（替代 Apollo、Clay、ZoomInfo） |
| **connections-optimizer** | 整理 X 和 LinkedIn 人脉网络 |
| **social-graph-ranker** | 加权社交图谱排序，发现热引荐路径 |
| **email-ops** | 邮箱分类、起草、发送验证 |
| **messages-ops** | 短信/DM 消息工作流 |
| **terminal-ops** | 命令执行验证工作流 |
| **research-ops** | 基于实证的研究工作流 |
| **customer-billing-ops** | 客户计费操作（订阅、退款、流失） |
| **finance-billing-ops** | 收入/定价/退款/团队计费审计 |
| **carrier-relationship-management** | 承运商关系管理 |
| **customs-trade-compliance** | 海关贸易合规 |
| **energy-procurement** | 能源采购 |
| **inventory-demand-planning** | 库存需求规划 |
| **logistics-exception-management** | 物流异常管理 |
| **production-scheduling** | 生产调度 |
| **quality-nonconformance** | 质量不合格管理 |
| **returns-reverse-logistics** | 退货逆向物流 |

---

## 十三、知识管理与研究

知识管理、检索和研究。

| Skill | 说明 |
|-------|------|
| **knowledge-ops** | 知识库管理、摄入、同步、检索 |
| **deep-research** | 多源深度研究，搜索结果综合并给出引用报告 |
| **documentation-lookup** | 通过 Context7 MCP 查询最新库/框架文档 |
| **exa-search** | 通过 Exa MCP 进行神经搜索 |
| **search-first** | 研究优先工作流，搜索已有方案再写代码 |
| **content-hash-cache-pattern** | 基于 SHA-256 内容哈希的缓存模式 |

---

## 十四、设计系统与 UI

UI 设计、组件库和视觉一致性。

| Skill | 说明 |
|-------|------|
| **design-system** | 设计系统生成与审计 |
| **frontend-design** | 高质量前端界面设计 |
| **liquid-glass-design** | iOS 26 Liquid Glass 设计系统 |
| **accessibility** | WCAG 2.2 无障碍设计 |
| **openclaw-persona-forge** | 用户角色塑造工具 |

---

## 十五、其他 / 跨领域

难以归类的跨领域技能。

| Skill | 说明 |
|-------|------|
| **x-api** | X/Twitter API 集成（推文、时间线、搜索、分析） |
| **jira-integration** | Jira 集成（获取 ticket、分析需求、更新状态） |
| **google-workspace-ops** | Google Workspace 操作（Drive、Docs、Sheets、Slides） |
| **project-flow-ops** | GitHub + Linear 执行流协调 |
| **opensource-pipeline** | 将私有项目分叉、脱敏、打包为开源发布 |
| **data-scraper-agent** | 构建自动 AI 数据采集 agent |
| **regex-vs-llm-structured-text** | 解析结构化文本时选择 regex 还是 LLM 的决策框架 |
| **evm-token-decimals** | 防止 EVM 链上小数位数不匹配 Bug |
| **nodejs-keccak256** | 防止 Node.js 中 Keccak-256 哈希 Bug |
| **content-hash-cache-pattern** | 基于内容哈希的缓存模式 |
| **healthcare-eval-harness** | 患者安全评估测试框架 |
| **healthcare-emr-patterns** | EMR/EHR 开发模式 |

---

## Skill 文件格式参考

每个 skill 是一个目录，格式如下：

```
skills/<skill-name>/
├── SKILL.md          # 主文件（YAML frontmatter + Markdown 内容）
├── references/       # 可选：参考文档
└── examples/         # 可选：示例
```

`SKILL.md` YAML frontmatter 字段：

| 字段 | 说明 |
|------|------|
| `name` | Skill 名称（目录名） |
| `description` | 简要描述，触发时用于匹配 |
| `origin` | 来源（ECC 为内置） |

---

## 笔记

可以在各子目录下新增 `.md` 文件深入学习具体的 skill，例如：

- [连续学习系统 v2.1 深度解析](continuous-learning-v2.md) — 深入学习持续学习系统 v2
- `study-notes/skills/tdd-workflow.md` — 深入学习 TDD 工作流
- `study-notes/skills/claude-api.md` — 学习 Claude API 模式
