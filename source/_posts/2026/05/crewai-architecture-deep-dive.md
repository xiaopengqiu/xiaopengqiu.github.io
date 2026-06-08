---
title: crewAI 源码解析：多 Agent 智能化的架构设计
date: 2026-05-20 10:00:00
tags:
  - AI Agent
  - 开源项目
  - 架构设计
  - Python
  - RAG
categories:
  - 技术架构
---

## 项目简介

crewAI 是一个 Python 编写的多 AI Agent 编排框架，GitHub 51.7k 星，MIT 许可。核心理念是让多个 AI Agent 扮演不同角色，像团队一样协作完成复杂任务。名字源自 **Crew**（团队）+ **AI**——让 Agent 组成 Crew 协同工作。

与 LangGraph 等框架不同，crewAI 完全从零构建，不依赖 LangChain，在高性能和灵活性上有自己的取舍。

<!-- more -->

## 架构总览

crewAI 是一个四层架构，从底层到上层分别是：

```
┌─────────────────────────────────────────────────┐
│              Flow（流程层）                        │  事件驱动、状态管理、条件分支
│         @start / @listen / @router               │
├─────────────────────────────────────────────────┤
│              Crew（团队层）                        │  Agent 编排、任务分配、流程控制
│     Process.sequential / Process.hierarchical    │
├─────────────────────────────────────────────────┤
│              Agent（智能体层）                      │  角色化执行、工具调用、推理决策
│   role / goal / backstory / tools / LLM         │
├─────────────────────────────────────────────────┤
│              基础设施层                             │
│  Memory │ Knowledge(RAG) │ Tools │ LLM          │
└─────────────────────────────────────────────────┘
```

- **Flow**：生产级事件驱动工作流，用 `@start` / `@listen` / `@router` 装饰器编排多步骤流程，支持 Pydantic 结构化状态管理
- **Crew**：Agent 的编排容器，支持 sequential（顺序执行）和 hierarchical（Manager Agent 统筹委派）两种模式
- **Agent**：自主执行单元，拥有角色、目标、背景故事，可调用工具、委派任务、自主推理
- **基础设施**：统一 Memory、Knowledge RAG、工具系统、多 LLM 适配层

## 上下文管理：分层注入与自动压缩

Agent 执行 Task 时的 prompt 不是简单地拼接历史消息，而是**分层注入、按需裁剪**：

```
System Prompt (角色 + 目标 + 背景故事)
  + Task Context (任务描述 + 期望输出)
    + Memory Context (从 Memory recall 的相关记忆)
      + Knowledge Context (从 Knowledge RAG 检索的文档片段)
```

### Cache Breakpoint 优化

从源码 `crew_agent_executor.py` 的 `_setup_messages()` 可以看到，prompt 按 system 和 user 两段分别设置 **cache breakpoint**。这利用了 LLM API 的 prefix caching 机制——同一 Agent 在 ReAct 循环中，system prompt 不变部分可以复用缓存，减少重复计算和 token 消耗。

### 上下文窗口自动管理

`respect_context_window=True` 时，框架会：

- 检测消息总长度是否超过 LLM 上下文窗口限制
- 超限时调用 `handle_context_length()` 对历史消息进行**摘要压缩**
- 保留最近的交互，对早期内容生成摘要替代

这避免了 Agent 因上下文溢出而崩溃，同时保留关键信息不丢失。

### 多模态上下文

`_inject_multimodal_files()` 将文件（图片、PDF 等）注入到最后一条 user message 的 `files` 字段，支持多模态 Agent 处理非文本输入。文件来源优先级：输入参数 > Crew/Task 级别存储。

## RAG 知识召回：双轨设计

crewAI 的知识系统是**静态知识 + 动态记忆**的双轨 RAG 架构：

### Knowledge（静态 RAG）

Knowledge 是纯粹的 RAG 管道，处理预先提供的外部知识源：

```
知识源 (PDF/CSV/JSON/Text) → 分块 + Embedding → 向量存储 (ChromaDB/Qdrant)
                                                              ↓
Agent 执行时 → query → storage.search(query, limit, score_threshold=0.6) → Top-K 片段
```

从 `knowledge.py` 源码看，关键设计：

- **score_threshold=0.6** — 低于相似度阈值的结果直接丢弃，避免噪声注入上下文
- **多源异构** — 不同文件类型有各自的 `BaseKnowledgeSource` 子类处理分块逻辑
- **Crew 级别共享** — `knowledge_sources` 设在 Crew 上时，所有 Agent 共享同一知识库
- **异步支持** — `aquery()` 和 `aadd_sources()` 提供完整的异步 API

### Memory（动态 RAG）

Memory 的召回远比 Knowledge 复杂。核心是 **RecallFlow**——一个用 Flow 框架实现的多步检索流程：

```
Step 1: analyze_query_step
  ├── 短查询 (<200字符) → 跳过 LLM，直接 embed 原始查询
  └── 长查询 → LLM 分析: 提取关键词、建议 scope、判断复杂度、
               蒸馏为 1-3 个子查询、解析时间过滤

Step 2: filter_and_chunk
  └── 根据 LLM 建议的 scope 选择候选搜索范围

Step 3: search_chunks
  └── (embeddings × scopes) 并行搜索，隐私过滤，时间过滤

Step 4: decide_depth (router)
  ├── 高置信度 (≥0.8) → 直接合成返回
  ├── 低置信度 (<0.5) + 有预算 → explore_deeper (迭代探索)
  └── 中间置信度 → 合成返回

Step 5: synthesize
  └── 合并去重，复合评分排序，返回 Top-K
```

从 `recall_flow.py` 源码中可以看到几个关键设计点：

**短查询跳过 LLM** — 查询长度小于 `query_analysis_threshold`（默认 200 字符）时，跳过 LLM 分析直接 embed 原始查询。简单问题省去 1-3 秒延迟，复杂问题才走完整的蒸馏流程。

**查询蒸馏** — "总结本季度所有架构决策"这类长查询会被 LLM 蒸馏为多个子查询（"架构决策"、"技术选型"、"迁移计划"），每个子查询独立 embed 并行搜索，提高召回率。

**时间感知** — "上周的决定"这类查询，LLM 自动解析为 ISO 日期过滤，搜索时只返回时间范围内的记忆。

**置信度路由** — 高置信度直接返回（快），低置信度迭代探索（准），平衡速度和准确性。

**复合评分** — 检索结果不是单纯按语义相似度排序，而是三维度加权：

```
composite = 0.5 × similarity + 0.3 × recency + 0.2 × importance
```

其中 recency 使用指数衰减：`0.5^(age_days / half_life_days)`，默认半衰期 30 天。这意味着最近 30 天的记忆权重是 60 天前的 2 倍。

## 工具调用：双模式与安全防护

### 双模式工具调用

从 `crew_agent_executor.py` 的 `_invoke_loop()` 可以看到：

```python
if use_native_tools:
    return self._invoke_loop_native_tools()   # 原生 function calling
else:
    return self._invoke_loop_react()           # ReAct 文本模式
```

- **Native Tools 模式**：LLM 支持 function calling 时，直接用结构化工具调用协议，输入输出更可靠
- **ReAct 模式**：LLM 不支持 function calling 时，在 prompt 中嵌入工具描述，LLM 输出 `Action: tool_name\nAction Input: {...}` 文本，由 parser 解析执行

两种模式自动检测，开发者无需关心。

### 安全防护体系

从 `tool_usage.py` 源码分析，工具调用不是"调用就完事"，而是有完整的安全网：

- **重复调用检测**：`_check_tool_repeated_usage()` — 如果 Agent 重复调用同一工具同一参数，返回错误提示打破死循环
- **格式记忆刷新**：`_remember_format_after_usages` — 每隔 N 次工具调用后重新注入工具格式说明，防止 LLM "忘记"工具调用格式
- **JSON 修复容错**：使用 `json_repair` 的 `repair_json()` 修复 LLM 输出的畸形 JSON，提高工具调用成功率
- **错误计数追踪**：`task.increment_tools_errors()` 追踪工具错误次数，支持后续分析

### 智能委派

`allow_delegation=True` 的 Agent 获得 `delegate_work_tool` 和 `ask_question_tool`：

- Agent 可以将子任务委派给其他更合适的 Agent
- 可以向其他 Agent 提问获取信息
- 这让 Agent 不只是被动执行，还能**主动协作**

### MCP 工具生态

框架完整支持 MCP（Model Context Protocol）：

```
mcp/client.py      — MCP 客户端
mcp/transports/    — HTTP / SSE / stdio 三种传输协议
mcp/tool_resolver.py — 工具解析器
mcp_native_tool.py — 原生 MCP 工具封装
```

这意味着 crewAI Agent 可以接入任何 MCP 兼容的外部工具服务，生态扩展能力很强。

## 记忆更新：EncodingFlow 五步流水线

记忆存储是 crewAI 最精巧的部分。从 `encoding_flow.py` 源码看，`remember()` 不是简单的"存入向量数据库"，而是一个**五步流水线**：

```
Step 1: batch_embed
  └── 所有待存内容一次 embed（而非逐条调用），减少 API 开销

Step 2: intra_batch_dedup
  └── 批次内余弦相似度矩阵，≥0.98 的近重复直接丢弃（纯向量计算，无 LLM）

Step 3: parallel_find_similar
  └── 对每条记忆并行搜索已有相似记录（最多 5 条）

Step 4: parallel_analyze（核心智能）
  ├── Group A: 字段齐全 + 无相似 → 0 次 LLM 调用，直接插入
  ├── Group B: 字段齐全 + 有相似 → 1 次 LLM 调用（整合决策）
  ├── Group C: 字段缺失 + 无相似 → 1 次 LLM 调用（推断 scope/分类/重要性）
  └── Group D: 字段缺失 + 有相似 → 2 次并发 LLM 调用（推断 + 整合）

Step 5: execute_plans
  └── 批量 re-embed 更新内容 + bulk insert 新记录
```

### LLM 分析的结构化输出

`analyze.py` 定义了严格的 LLM 输出 schema：

**存储分析（MemoryAnalysis）**：

- `suggested_scope` — 推断记忆应存放的层级路径（如 `/project/decisions`）
- `categories` — 自动分类标签
- `importance` — 0.0~1.0 重要性评分
- `extracted_metadata` — 提取实体、日期、主题等元数据

**整合决策（ConsolidationPlan）**：

- 对每条相似记录决定：keep / update / delete
- `insert_new` — 是否同时插入新记录
- `insert_reason` — 决策理由

**查询分析（QueryAnalysis）**：

- `keywords` — 关键词提取
- `suggested_scopes` — 建议搜索范围
- `complexity` — 简单/复杂判断
- `recall_queries` — 蒸馏后的子查询
- `time_filter` — 时间过滤条件

### 记忆整合机制

这是让 Agent 避免记忆膨胀的关键。当新记忆与已有记忆相似度 > 0.85 时，LLM 判断：

| 决策 | 含义 | 示例 |
|------|------|------|
| keep | 旧记忆仍准确，不改动 | 新旧信息一致 |
| update | 旧记忆需更新 | "PostgreSQL 从 14 升级到 16" |
| delete | 旧记忆已被替代 | 旧配置被新配置覆盖 |
| insert_new | 新内容虽相似但值得独立存储 | 不同视角的决策记录 |

这解决了多 Agent 场景下记忆膨胀的经典问题：三个 Agent 都存了 "CrewAI 支持复杂工作流"，不会变成三条重复记录。

### 原子化记忆提取

`extract_memories_from_content()` 将一段长文本拆分为原子化的事实：

```
输入: "会议纪要：决定下季度从 MySQL 迁移到 PostgreSQL，预算 5 万，Sarah 负责迁移"
输出:
  - "下季度计划从 MySQL 迁移到 PostgreSQL"
  - "数据库迁移预算为 5 万"
  - "Sarah 负责数据库迁移"
```

好处是召回时能精确匹配到单个事实，而不是从一大段文本中寻找关键信息。LLM 失败时优雅降级——将完整内容作为一条记忆存储，确保不丢失数据。

### 非阻塞存储与读屏障

```python
# 后台线程池存储，不阻塞 Agent 执行
self._save_pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="memory-save")

# recall() 自动等待未完成的写入（读屏障）
def recall(...):
    self.drain_writes()  # 确保一致性
    # 然后搜索
```

Agent 执行完 Task 后可以立即开始下一个 Task，记忆存储在后台完成。Crew 结束时 `kickoff()` 的 `finally` 块确保所有写入完成，不丢失任何记忆。

### 层级化 Scope 隔离

记忆按类似文件系统的树形结构组织：

```
/
  /project
    /project/alpha
    /project/beta
  /agent
    /agent/researcher     ← 研究员私有记忆
    /agent/writer         ← 写手私有记忆
  /company
    /company/knowledge    ← 公司共享知识
```

三种隔离机制：

- **MemoryScope** — 限制 Agent 只能看到某个子树，如研究员只能看到 `/agent/researcher`
- **MemorySlice** — 组合多个子树的视图，如写手可以读取自己的记忆 + 公司共享知识（只读）
- **private 标记** — 标记为私有的记忆只对匹配 source 的召回可见，多租户场景下实现数据隔离

LLM 自动推断 scope 是一个巧妙的设计——存入记忆时不指定 scope，LLM 会分析内容并自动归类到合适的分支。树结构随内容积累自然生长，不需要预先设计。

## 推理能力：执行前反思

`reasoning=True` 的 Agent 会在执行 Task 前先进行推理规划。从 `reasoning_handler.py` 源码看，推理输出是结构化的：

```python
class ReasoningPlan(BaseModel):
    plan: str          # 整体计划概述
    steps: list[PlanStep]  # 结构化步骤
    ready: bool        # 是否准备好执行

class PlanStep(BaseModel):
    step_number: int
    description: str        # 这步做什么
    tool_to_use: str | None # 用什么工具
    depends_on: list[int]   # 依赖哪些步骤
```

Agent 通过 LLM function calling 生成结构化执行计划，包含**工具选择和步骤依赖关系**。这让 Agent 不是盲目地试错，而是先想清楚再动手。`max_reasoning_attempts` 控制最大推理尝试次数，`ready=False` 时 Agent 会继续反思直到找到可行方案。

## 值得借鉴的设计模式

### 1. 统一 Memory 替代碎片化记忆

早期多 Agent 框架（包括 crewAI 早期版本）将短期记忆、长期记忆、实体记忆分开管理，开发者需要手动选择存储类型。统一 Memory 用一个 `Memory` 类 + LLM 自动分类，大幅降低了使用复杂度。**让 LLM 做分类决策，而非让开发者做**——这是 AI-native 设计的典范。

### 2. 复合评分检索

纯向量检索只能回答"语义最相近"，但 Agent 的记忆检索需要回答"现在最相关"。复合评分 `semantic + recency + importance` 将时间维度和重要性维度纳入考量，且权重可调。冲刺回顾场景可以加大 recency 权重，架构知识库可以加大 importance 权重。

### 3. 置信度路由

RecallFlow 的 `decide_depth()` 根据搜索结果的置信度决定是直接返回还是迭代探索。这比固定深度的检索更智能——简单问题不浪费 LLM 调用，复杂问题不放弃深入探索。类似的思想可以用在任何需要平衡"快"和"准"的检索场景。

### 4. 记忆整合防止膨胀

多 Agent 协作时，每个 Agent 都在产生记忆，不加整合会导致记忆库膨胀、检索质量下降。ConsolidationPlan 的 keep/update/delete/insert_new 四种决策，让记忆库像数据库的 compaction 一样保持紧凑。

### 5. 非阻塞存储 + 读屏障

后台线程池存储记忆、`drain_writes()` 读屏障保证一致性。这个模式在数据库领域很常见（WAL + checkpoint），但在 AI Agent 框架中很少见。它让 Agent 的执行不被记忆存储阻塞，同时保证读取时看到完整数据。

### 6. 优雅降级

整个系统在 LLM 失败时都能优雅降级：

- 记忆存储分析失败 → 使用默认值存储，不丢失数据
- 查询分析失败 → 回退到纯向量搜索
- 记忆提取失败 → 存储完整内容而非丢弃
- LLM 初始化失败 → 延迟报错，不阻止 Memory 对象创建

**不完美但永远可用**，比完美但经常崩溃好得多。

## 潜在不足

1. **LLM 调用开销** — 记忆的存储和深度检索都依赖 LLM，每次存储可能产生 0~2 次 LLM 调用，高频率场景下成本和延迟可能显著
2. **Scope 树维护** — LLM 自动推断 scope 方便但缺乏约束，长期运行后树结构可能变得混乱
3. **Memory 与 Knowledge 的统一查询** — 两者是独立的检索路径，Agent 需要同时处理两个来源的结果，没有统一的合并排序
4. **单线程写入** — 后台写入线程池 `max_workers=1`，大批量记忆存储时可能成为瓶颈

## 总结

crewAI 的架构体现了几个核心洞察：

1. **让 LLM 做分类决策** — 统一 Memory 用 LLM 推断 scope、分类、重要性，而非让开发者手动管理
2. **复合评分优于单一相似度** — 语义 + 时效 + 重要性的三维评分，比纯向量检索更贴近"现在最相关"
3. **置信度路由优于固定深度** — 简单问题快、复杂问题准，动态平衡检索效率和质量
4. **整合优于堆积** — 记忆整合让知识库像数据库 compaction 一样保持紧凑
5. **优雅降级优于完美崩溃** — 每个环节都能在 LLM 失败时继续工作

如果你在构建需要长期记忆和多 Agent 协作的 AI 系统，crewAI 的记忆管线设计值得深入参考。

---

> 项目地址：[github.com/crewAIInc/crewAI](https://github.com/crewAIInc/crewAI)
