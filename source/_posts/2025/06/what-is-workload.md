---
title: 云原生资源类型
date: 2025-06-03 23:45:20
tags:
    - Docker
    - k8s
categories:
    - 技术介绍
---

介绍一下云原生资源中常见的几种资源类型。
<!-- more --> 

云原生资源类型：
* 工作负载（Workload）资源
* 服务发现与负载均衡资源（Service & Networking）
* 配置与存储资源（Configuration & Storage）
* 身份与访问控制（Security & RBAC）
* 调度与运行时资源（Scheduling & Runtime）
* 集群元数据与控制资源（Meta & Control）

## workload
workload是指运行在k8s集群上的应用程序实例，workload通常管理着一组Pod。

常见的 Workload 类型（以 Kubernetes 为例）：
1. Pod
最基本的计算单元，通常包含一个或多个容器。

2. Deployment
用于管理无状态服务，支持自动扩缩容、滚动更新等。

3. StatefulSet
用于管理有状态服务，比如数据库，提供稳定的网络标识、存储等。

4. DaemonSet
保证每个（或指定）节点上运行一个 Pod，常用于日志收集、监控等。

5. Job
一次性任务，执行完成后退出，适用于批处理任务。

6. CronJob
类似于 Linux 的定时任务，定时运行 Job。

Workload 的作用
* 部署应用：你可以通过定义 Deployment 或 StatefulSet 来部署服务。

* 生命周期管理：自动控制副本数量、重启策略、滚动升级等。

* 解耦基础设施与应用：Workload 资源定义了“运行什么、怎么运行”，与底层节点、操作系统解耦。

* 可观测性和伸缩性：配合服务网格、监控工具和自动扩缩容机制，提高系统弹性。

## ZPAAS 与 workload
蚂蚁集团在经典的部署资源叫做ZPAAS，以虚拟机为载体进行部署。

云原生概念出现后，应用部署转向为workload云原生资源。但是为了兼容已有的存量ZPAAS资源，在做应用发布时保留了ZPAAS发布、ZPAAS与workload混合发布。

在应用发布之前先判断应用所属的部署类型，然后在运行时通过SPI（service provider interface）调用对应的部署实现。



