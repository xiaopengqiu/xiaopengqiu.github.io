---
title: Multica 源码解析：让 AI Agent 成为真正队友的架构设计
date: 2026-05-12 20:00:00
tags:
  - AI Agent
  - 开源项目
  - 架构设计
  - Go
  - Next.js
categories:
  - 技术架构
---

## 项目简介

Multica 是一个开源的 AI Agent 管理平台，核心理念是 **"Your next 10 hires won't be human"**——让编码 Agent 成为团队中真正的队友。你可以像给同事分配任务一样给 Agent 分配 Issue，Agent 会自主认领、执行、报告阻塞项并更新状态。

名字源自 **Mul**tiplexed **I**nformation and **C**omputing **A**gent，致敬 1960 年代分时操作系统 Multics——当年 Multics 让多个用户共享一台机器，而 Multica 让人类和 Agent 共享同一个工作空间。

<!-- more -->

## 技术栈全景

| 层级 | 技术选型 |
|------|---------|
| 前端 | Next.js 16 (App Router) + TypeScript + Tailwind CSS + shadcn/ui |
| 后端 | Go 1.26 + Chi 路由器 + gorilla/websocket |
| 数据库 | PostgreSQL 17 + pgvector |
| 缓存/消息 | Redis (多节点实时事件中继) |
| 对象存储 | S3 兼容 / 本地文件系统 |
| 实时通信 | WebSocket (作用域房间 + Redis Stream 分片) |
| 认证 | JWT + PAT (Personal Access Token) + Daemon Token |
| Monorepo | Turborepo + pnpm workspace |
| Agent 支持 | Claude Code / Codex / GitHub Copilot CLI / OpenClaw / OpenCode / Hermes / Gemini / Pi / Cursor Agent / Kimi / Kiro CLI |

整体架构图：

```
┌──────────────┐     ┌──────────────┐     ┌──────────────────┐
│   Next.js    │────>│  Go Backend  │────>│   PostgreSQL     │
│   Frontend   │<────│  (Chi + WS)  │<────│   (pgvector)     │
└──────────────┘     └──────┬───────┘     └──────────────────┘
                            │
                     ┌──────┴───────┐
                     │ Agent Daemon │  ← 运行在本机
                     └──────────────┘
```

## 核心设计思想

### 1. Agent 是一等公民

这不是一个"后台跑脚本"的工具，Agent 在系统中拥有完整的身份：

- **Agent Profile**：每个 Agent 有名字、头像、能力描述
- **Issue 分配**：Assignee Picker 里 Agent 和人类并列
- **活动时间线**：Agent 的操作记录与人类操作同流展示
- **主动沟通**：Agent 能发评论、创建 Issue、报告阻塞

这种设计将 Agent 从"工具"提升为"协作者"，改变了团队协作的心智模型。

### 2. 事件驱动架构

系统内部采用事件总线驱动组件间通信：

```
HTTP 请求 → Handler → Service → Event → Listener → WebSocket Hub → 客户端
```

好处是解耦——新增功能只需订阅相关事件，无需修改已有逻辑。事件同时触发实时推送，保证前端状态同步。

### 3. 任务队列与租约机制

Agent 任务不是简单的"派发-执行"模型，而是基于数据库的任务队列 + 租约（Lease）机制：

1. 用户创建 Issue → 任务入队 (`agent_task_queue` 表)
2. Daemon 通过 HTTP 轮询或 WebSocket 通知发现待执行任务
3. Daemon Claim 任务 → 获得租约（带超时）
4. 执行过程中通过 WebSocket 流式推送进度
5. 完成/失败 → 更新数据库 → 触发事件

租约机制确保任务不会因为 Daemon 崩溃而永远悬挂——超时后其他 Daemon 可以重新认领。

### 4. 可复用技能（Skills）

每个解决方案可以被提取为 Skill，供整个团队复用。部署脚本、数据库迁移、代码审查模板——技能随时间复合增长，让团队的能力不随人员流动而流失。

## 后端架构深入

### 分层设计

```
HTTP Handlers → Services → Data Access → Database
                ↓
            Event Bus → WebSocket Hub
                ↓
            Redis Cache
```

- **Handler 层**：请求验证、认证、参数解析，委托给 Service
- **Service 层**：核心业务逻辑（任务调度、自动领航、邮件通知等）
- **实时层**：WebSocket Hub 管理连接，Redis Relay 支持多节点部署

### WebSocket 实时系统

这是系统中最精巧的部分之一。

**作用域房间（Scoped Rooms）**

WebSocket 连接按 scope 分组：workspace、user、task、chat。客户端订阅特定 scope，Hub 只推送相关事件，避免消息风暴。

**慢客户端驱逐**

每个连接有写缓冲区，当客户端消费速度跟不上推送速度时，Hub 直接断开该连接，防止一个慢客户端拖垮整个节点。

**消息去重**

使用有界 LRU 缓存追踪已发送的事件 ID，防止重复推送。

**Redis Relay 多节点扩展**

单节点模式下，WebSocket Hub 纯内存运行。多节点模式下，事件通过 Redis Stream 分片中继：

```
Node A 发生事件 → Redis Stream → Node B/C/D 的 Relay → 各节点本地 Hub → 客户端
```

支持三种模式：
- `sharded`：不同流量类型使用不同 Redis 客户端，减少争用
- `dual`：兼容模式
- `legacy`：向后兼容

### Daemon 通信

Daemon 是运行在本机的轻量进程，负责：

- **心跳保活**：WebSocket 心跳 + HTTP 回退
- **CLI 自动发现**：扫描 PATH 上的 `claude`、`codex`、`copilot` 等命令
- **任务认领**：收到通知后通过 HTTP Claim 任务
- **进度流式推送**：执行过程通过 WebSocket 实时上报

**Runtime 状态计算**：

| 状态 | 判定条件 |
|------|---------|
| Online | Runtime 可达 |
| Unstable | Runtime 断连 < 5 分钟 |
| Offline | Runtime 长时间无响应 |

后台有 Runtime Sweeper 定期扫描，将失联的 Runtime 标记为离线。

### Agent 抽象层

`pkg/agent/` 提供统一接口适配多种编码 Agent：

```go
type Agent interface {
    Stream(ctx context.Context, messages []Message) <-chan Event
    // 会话管理、Token 追踪等
}
```

每个 Agent 后端（Claude、Codex、Copilot 等）实现此接口，上层代码无需关心具体 Agent 类型。这样新增 Agent 支持只需添加一个实现，无需改动业务逻辑。

## 前端架构

### Monorepo 结构

```
apps/
├── web/          # 主 Web 应用 (Next.js 16)
└── desktop/      # Electron 桌面端
packages/
├── core/         # 共享类型、API Client、工具函数
├── ui/           # shadcn/ui 组件库
└── views/        # 共享视图组件 (Board、List、Form)
```

### 关键技术选型

- **状态管理**：Zustand (轻量全局状态) + TanStack React Query (服务端状态)
- **富文本编辑**：Tiptap（支持 Markdown、代码高亮、@提及、表格）
- **拖拽排序**：dnd-kit（Issue Board 拖拽）
- **图表**：Recharts（分析仪表盘）
- **API 层**：`packages/core` 中的统一 API Client，带认证和 Zod schema 验证

### 容错设计

API 响应使用 Zod schema 验证，后端字段变更时前端优雅降级而非崩溃。这是实际项目中很有价值的实践——后端迭代不应导致前端白屏。

## 数据库设计

经过 80+ 次迁移，核心表结构包括：

- `user` / `workspace` / `member`：用户与团队
- `agent`：Agent 定义（名称、类型、Runtime 关联）
- `issue` / `comment`：Issue 追踪与评论
- `agent_task_queue`：任务队列（带租约）
- `runtime`：运行时实例
- `skill`：可复用技能
- `chat` / `chat_message`：对话系统
- `attachment`：文件附件

关键设计决策：

- **UUID 主键**：`gen_random_uuid()`，分布式友好
- **全文搜索索引**：Issue 和 Comment 支持 `tsvector` 全文搜索
- **pgvector**：为语义搜索预留向量索引
- **任务触发摘要缓存**：创建任务时缓存触发上下文（评论内容等），避免后续查询回源表，且不受原始内容编辑/删除影响

## 任务执行全流程

```
用户创建 Issue
    ↓
HTTP API → TaskService → 任务入队 (PostgreSQL)
    ↓
Redis 缓存 "有待执行任务" 信号
    ↓
Daemon 收到 WebSocket 通知 (或 HTTP 轮询发现)
    ↓
Daemon → HTTP Claim → 获得任务租约
    ↓
Daemon 调用 Agent CLI (claude / codex / ...)
    ↓
Agent 执行 → WebSocket 流式进度 → 前端实时更新
    ↓
完成/失败 → 更新数据库 → 事件总线 → 通知相关方
```

**Empty Claim Cache** 是一个值得注意的优化：当没有待执行任务时，Redis 缓存该结果，避免 Daemon 频繁查数据库。任务入队时清除缓存。

## 部署与运维

### 快速启动

```bash
# Cloud 模式
multica setup

# Self-host 模式 (需要 Docker)
curl -fsSL https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.sh | bash -s -- --with-server
multica setup self-host
```

### 开发模式

```bash
make dev  # 自动检测环境、创建配置、安装依赖、初始化数据库、启动服务
```

### 环境变量

| 变量 | 说明 |
|------|------|
| `DATABASE_URL` | PostgreSQL 连接串 |
| `JWT_SECRET` | JWT 签名密钥 |
| `REDIS_URL` | Redis 连接串（多节点必须） |
| `PORT` | API 端口 (默认 8080) |
| `RESEND_API_KEY` | 邮件服务 API Key |
| `ALLOW_SIGNUP` | 是否开放注册 |

### 监控

集成了 Prometheus 指标暴露，可以对接 Grafana 等监控体系。

## 值得借鉴的设计模式

### 1. 租约而非锁

任务队列用 Lease 而非 Database Lock。Lease 有超时，即使 Daemon 崩溃也不会死锁。这是分布式系统中更健壮的并发控制方式。

### 2. 缓存触发摘要

任务创建时缓存触发上下文，后续查询无需回源。这在事件溯源系统中很实用——解耦了任务和触发源的生命周期。

### 3. 慢客户端驱逐

WebSocket 服务端主动断开消费不过来的客户端，防止雪崩。这是生产级 WebSocket 服务的必备模式。

### 4. 分片 Redis Relay

多节点 WebSocket 通过 Redis Stream 分片中继，比 Pub/Sub 更可控，支持消费组、消息持久化和回溯。

### 5. Agent 工厂模式

统一接口 + 多后端实现，新增 Agent 类型零改动业务逻辑。经典的策略模式在 Go 中的落地。

## 总结

Multica 的架构体现了几个核心洞察：

1. **Agent 不是工具，是队友**——这决定了整个系统的 UI/UX 和数据模型
2. **事件驱动优于直接调用**——解耦让系统可持续演进
3. **租约优于锁**——分布式环境下的容错之道
4. **优雅降级优于崩溃**——Zod 验证 + 回退保证前端健壮性
5. **可复用技能是复利**——解决方案积累成组织能力

对于一个 0.2 版本的开源项目来说，架构已经相当成熟。如果你在构建类似的多 Agent 协作平台，Multica 的设计值得参考。

---

> 项目地址：[github.com/multica-ai/multica](https://github.com/multica-ai/multica)
